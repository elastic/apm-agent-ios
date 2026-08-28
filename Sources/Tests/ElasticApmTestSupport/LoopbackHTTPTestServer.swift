// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0
//
// Adapted from opentelemetry-swift's Tests/Shared/TestUtils/HttpTestServer.swift.

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

// EDOT currently supports iOS only; macOS retains the SwiftPM development loop.
#if os(iOS) || os(macOS)

public final class LoopbackHTTPTestServer {
  private static let host = "127.0.0.1"
  private static let requestReadTimeout: TimeInterval = 10

  public struct Request: Equatable {
    public let method: String
    public let path: String
    public let headers: [String: String]

    public func header(named name: String) -> String? {
      headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
  }

  public enum ServerError: Error {
    case socketCreationFailed
    case socketConfigurationFailed
    case bindFailed
    case portLookupFailed
    case listenFailed
  }

  public private(set) var port = 0

  public var baseURL: URL {
    guard let url = URL(string: "http://\(Self.host):\(port)") else {
      preconditionFailure("Failed to construct loopback server URL")
    }
    return url
  }

  private let requestsQueue = DispatchQueue(label: "LoopbackHTTPTestServer.requests")
  private let serverQueue = DispatchQueue(label: "LoopbackHTTPTestServer.server")
  private var recordedRequests: [Request] = []
  private var recordedEvents: [String] = []
  private var serverSocket: Int32 = -1
  private var isRunning = false

  public init() {}

  public func start() throws {
    #if canImport(Darwin)
      serverSocket = socket(AF_INET, SOCK_STREAM, 0)
    #else
      serverSocket = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    #endif
    guard serverSocket >= 0 else {
      throw ServerError.socketCreationFailed
    }

    var reuseAddress: Int32 = 1
    guard setsockopt(
      serverSocket,
      SOL_SOCKET,
      SO_REUSEADDR,
      &reuseAddress,
      socklen_t(MemoryLayout<Int32>.size)
    ) == 0 else {
      closeServerSocket()
      throw ServerError.socketConfigurationFailed
    }

    let flags = fcntl(serverSocket, F_GETFL, 0)
    guard flags >= 0, fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK) == 0 else {
      closeServerSocket()
      throw ServerError.socketConfigurationFailed
    }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)

    let bindResult = withUnsafePointer(to: &address) { pointer in
      bind(
        serverSocket,
        UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        socklen_t(MemoryLayout<sockaddr_in>.size)
      )
    }
    guard bindResult == 0 else {
      closeServerSocket()
      throw ServerError.bindFailed
    }

    var boundAddress = sockaddr_in()
    var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let lookupResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      getsockname(
        serverSocket,
        UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
        &boundAddressLength
      )
    }
    guard lookupResult == 0 else {
      closeServerSocket()
      throw ServerError.portLookupFailed
    }

    port = Int(UInt16(bigEndian: boundAddress.sin_port))
    guard listen(serverSocket, 16) == 0 else {
      closeServerSocket()
      throw ServerError.listenFailed
    }

    recordEvent("listening on \(Self.host):\(port)")
    isRunning = true
    serverQueue.async { [weak self] in
      self?.acceptRequests()
    }
  }

  public func stop() {
    guard isRunning else {
      return
    }
    isRunning = false
    closeServerSocket()
    serverQueue.sync {}
  }

  public var requests: [Request] {
    requestsQueue.sync { recordedRequests }
  }

  public var diagnostics: String {
    requestsQueue.sync {
      let requestDescriptions = recordedRequests.enumerated().map { index, request in
        let headers = ["Authorization", "Content-Type", "Content-Encoding", "Content-Length"]
          .compactMap { name in
            request.header(named: name).map { "\(name)=\($0)" }
          }
          .joined(separator: ", ")
        return "[\(index)] \(request.method) \(request.path) {\(headers)}"
      }
      return """
        Loopback server port: \(port)
        Events: \(recordedEvents.isEmpty ? "none" : recordedEvents.joined(separator: " | "))
        Requests: \(requestDescriptions.isEmpty ? "none" : requestDescriptions.joined(separator: " | "))
        """
    }
  }

  public func waitForRequest(
    timeout: TimeInterval,
    where predicate: (Request) -> Bool
  ) -> Request? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let request = requests.first(where: predicate) {
        return request
      }
      Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return nil
  }

  deinit {
    stop()
  }

  private func acceptRequests() {
    while isRunning {
      var clientAddress = sockaddr_in()
      var clientAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
      let clientSocket = withUnsafeMutablePointer(to: &clientAddress) { pointer in
        accept(
          serverSocket,
          UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: sockaddr.self),
          &clientAddressLength
        )
      }

      guard clientSocket >= 0 else {
        if isRunning, errno == EAGAIN || errno == EWOULDBLOCK {
          Thread.sleep(forTimeInterval: 0.01)
        } else if isRunning {
          recordEvent("accept failed with errno \(errno)")
        }
        continue
      }

      recordEvent("accepted connection")
      #if canImport(Darwin)
        var noSignal: Int32 = 1
        _ = setsockopt(
          clientSocket,
          SOL_SOCKET,
          SO_NOSIGPIPE,
          &noSignal,
          socklen_t(MemoryLayout<Int32>.size)
        )
      #endif

      handle(clientSocket)
      close(clientSocket)
    }
  }

  private func handle(_ clientSocket: Int32) {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    let headerSeparator = Data("\r\n\r\n".utf8)
    let readDeadline = Date().addingTimeInterval(Self.requestReadTimeout)

    while data.range(of: headerSeparator) == nil {
      let result = receive(
        from: clientSocket,
        into: &buffer,
        count: buffer.count,
        deadline: readDeadline)
      guard result.count > 0 else {
        recordEvent(
          result.error.map { "header receive failed with errno \($0)" }
            ?? "connection closed before complete headers")
        sendResponse("HTTP/1.1 400 Bad Request", to: clientSocket)
        return
      }
      data.append(contentsOf: buffer.prefix(result.count))
    }

    guard
      let headerRange = data.range(of: headerSeparator),
      let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
    else {
      recordEvent("request headers were not valid UTF-8")
      sendResponse("HTTP/1.1 400 Bad Request", to: clientSocket)
      return
    }

    let lines = headerText.components(separatedBy: "\r\n")
    let requestLine = lines[0].split(separator: " ")
    guard requestLine.count >= 2 else {
      recordEvent("request line was malformed: \(lines[0])")
      sendResponse("HTTP/1.1 400 Bad Request", to: clientSocket)
      return
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let separator = line.firstIndex(of: ":") else {
        continue
      }
      let name = line[..<separator].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }

    let contentLength = headers.first {
      $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame
    }.flatMap { Int($0.value) } ?? 0
    var receivedBodyBytes = data.count - headerRange.upperBound
    while receivedBodyBytes < contentLength {
      let result = receive(
        from: clientSocket,
        into: &buffer,
        count: min(buffer.count, contentLength - receivedBodyBytes),
        deadline: readDeadline)
      guard result.count > 0 else {
        recordEvent(
          result.error.map { "body receive failed with errno \($0)" }
            ?? "connection closed before complete body")
        sendResponse("HTTP/1.1 400 Bad Request", to: clientSocket)
        return
      }
      receivedBodyBytes += result.count
    }

    let request = Request(
      method: String(requestLine[0]),
      path: String(requestLine[1]),
      headers: headers
    )
    requestsQueue.sync {
      recordedRequests.append(request)
      recordedEvents.append("recorded \(request.method) \(request.path)")
    }
    sendResponse("HTTP/1.1 200 OK", to: clientSocket)
  }

  private func receive(
    from socket: Int32,
    into buffer: inout [UInt8],
    count: Int,
    deadline: Date
  ) -> (count: Int, error: Int32?) {
    while true {
      let receivedCount = recv(socket, &buffer, count, 0)
      guard receivedCount < 0 else {
        return (receivedCount, nil)
      }

      let receiveError = errno
      if receiveError == EINTR {
        continue
      }
      if receiveError == EAGAIN || receiveError == EWOULDBLOCK {
        guard Date() < deadline else {
          return (receivedCount, receiveError)
        }
        Thread.sleep(forTimeInterval: 0.01)
        continue
      }
      return (receivedCount, receiveError)
    }
  }

  private func recordEvent(_ event: String) {
    requestsQueue.sync {
      recordedEvents.append(event)
    }
  }

  private func sendResponse(_ statusLine: String, to socket: Int32) {
    let response = "\(statusLine)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    response.withCString { pointer in
      _ = send(socket, pointer, strlen(pointer), 0)
    }
  }

  private func closeServerSocket() {
    guard serverSocket >= 0 else {
      return
    }
    #if canImport(Darwin)
      _ = Darwin.shutdown(serverSocket, SHUT_RDWR)
    #elseif canImport(Glibc)
      _ = Glibc.shutdown(serverSocket, Int32(SHUT_RDWR))
    #endif
    close(serverSocket)
    serverSocket = -1
  }
}

#endif
