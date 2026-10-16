// Copyright © 2026 Elasticsearch BV
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.

import Foundation

#if canImport(Darwin)
  import Darwin
#endif

// The SNTP transport under test does not exist on watchOS, where ordinary apps cannot use
// low-level UDP networking.
#if !os(watchOS)

  /// A loopback UDP server for SNTP client tests. One worker thread receives each datagram,
  /// optionally waits, and sends the reply returned by `respond`. `close()` wakes the worker,
  /// waits for it to exit, and then closes the socket.
  public final class LoopbackUDPTestServer {
    public enum ServerError: Error {
      case socketCreationFailed
      case bindFailed
      case portLookupFailed
      case pipeCreationFailed
    }

    public let port: UInt16

    private let socketDescriptor: Int32
    private let wakeReadDescriptor: Int32
    private let wakeWriteDescriptor: Int32
    private let replyDelay: TimeInterval
    private let respond: (Data) -> Data?
    private let workerExited = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var requestCount = 0
    private var isClosed = false

    /// - Parameters:
    ///   - replyDelay: time to wait after each request before replying.
    ///   - respond: returns the reply for a request, or `nil` to stay silent.
    public init(replyDelay: TimeInterval = 0, respond: @escaping (Data) -> Data?) throws {
      self.replyDelay = replyDelay
      self.respond = respond

      let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
      guard descriptor >= 0 else {
        throw ServerError.socketCreationFailed
      }
      do {
        port = try Self.bindToLoopback(descriptor)
      } catch {
        Darwin.close(descriptor)
        throw error
      }

      var pipeDescriptors: [Int32] = [-1, -1]
      guard pipe(&pipeDescriptors) == 0 else {
        Darwin.close(descriptor)
        throw ServerError.pipeCreationFailed
      }
      socketDescriptor = descriptor
      wakeReadDescriptor = pipeDescriptors[0]
      wakeWriteDescriptor = pipeDescriptors[1]

      let worker = Thread { [self] in serve() }
      worker.name = "LoopbackUDPTestServer"
      worker.start()
    }

    /// Returns a loopback port with no listener.
    public static func unusedPort() throws -> UInt16 {
      let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
      guard descriptor >= 0 else {
        throw ServerError.socketCreationFailed
      }
      defer { Darwin.close(descriptor) }
      return try bindToLoopback(descriptor)
    }

    public var receivedRequestCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return requestCount
    }

    /// Stops the worker and closes the socket. Safe to call more than once.
    public func close() {
      lock.lock()
      let alreadyClosed = isClosed
      isClosed = true
      lock.unlock()
      guard !alreadyClosed else {
        return
      }
      var byte: UInt8 = 1
      _ = write(wakeWriteDescriptor, &byte, 1)
      workerExited.wait()
      Darwin.close(socketDescriptor)
      Darwin.close(wakeReadDescriptor)
      Darwin.close(wakeWriteDescriptor)
    }

    private func serve() {
      defer { workerExited.signal() }
      var buffer = [UInt8](repeating: 0, count: 512)
      while true {
        var descriptors = [
          pollfd(fd: socketDescriptor, events: Int16(POLLIN), revents: 0),
          pollfd(fd: wakeReadDescriptor, events: Int16(POLLIN), revents: 0)
        ]
        guard poll(&descriptors, 2, -1) >= 0 else {
          if errno == EINTR { continue }
          return
        }
        if descriptors[1].revents != 0 {
          return
        }
        guard descriptors[0].revents != 0 else {
          continue
        }

        var sender = sockaddr_storage()
        var senderLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let received = withUnsafeMutablePointer(to: &sender) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            recvfrom(socketDescriptor, &buffer, buffer.count, 0, $0, &senderLength)
          }
        }
        guard received >= 0 else {
          continue
        }
        lock.lock()
        requestCount += 1
        lock.unlock()

        if replyDelay > 0, wakeRequested(within: replyDelay) {
          return
        }
        guard let reply = respond(Data(buffer[0..<received])) else {
          continue
        }
        _ = reply.withUnsafeBytes { bytes in
          withUnsafePointer(to: &sender) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
              sendto(socketDescriptor, bytes.baseAddress, bytes.count, 0, $0, senderLength)
            }
          }
        }
      }
    }

    /// Waits up to `interval` and reports whether `close()` woke the worker.
    private func wakeRequested(within interval: TimeInterval) -> Bool {
      var descriptor = pollfd(fd: wakeReadDescriptor, events: Int16(POLLIN), revents: 0)
      return poll(&descriptor, 1, Int32(interval * 1000)) != 0
    }

    private static func bindToLoopback(_ descriptor: Int32) throws -> UInt16 {
      var address = sockaddr_in()
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = 0
      address.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard bindResult == 0 else {
        throw ServerError.bindFailed
      }
      var bound = sockaddr_in()
      var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
      let lookupResult = withUnsafeMutablePointer(to: &bound) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          getsockname(descriptor, $0, &boundLength)
        }
      }
      guard lookupResult == 0 else {
        throw ServerError.portLookupFailed
      }
      return UInt16(bigEndian: bound.sin_port)
    }
  }

#endif
