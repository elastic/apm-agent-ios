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

// The UDP transport does not exist on watchOS, where ordinary apps cannot use low-level UDP
// networking; watchOS keeps the system clock.
#if !os(watchOS)

  import ElasticApmTestSupport
  import Foundation
  import Network
  import XCTest

  @testable import ElasticApm

  final class SNTPUDPTransportTests: XCTestCase {
    private let request = SNTPPacket(transmitTime: 3_900_000_000 * nanosPerSecond).encoded()

    func testReturnsTheServerReply() throws {
      let server = try LoopbackUDPTestServer { request in
        sntpReply(to: request, serverAhead: 0)
      }
      defer { server.close() }

      let outcome = exchange(port: server.port, deadline: 5)

      XCTAssertEqual(try outcome.result.get(), sntpReply(to: request, serverAhead: 0))
      XCTAssertEqual(server.receivedRequestCount, 1)
      assertConnectionCancelled(outcome.exchange)
    }

    func testDefaultDeadlineEndsAnUnansweredAttemptWithinFiveSeconds() throws {
      let server = try LoopbackUDPTestServer { _ in nil }
      defer { server.close() }

      let outcome = exchange(port: server.port, deadline: nil, wait: 7)

      XCTAssertEqual(outcome.result, .failure(.timeout))
      XCTAssertGreaterThanOrEqual(outcome.elapsed, 4.9)
      XCTAssertLessThan(outcome.elapsed, 5.5)
      assertConnectionCancelled(outcome.exchange)
    }

    func testSlowServerHitsTheDeadlineAndItsLateReplyIsIgnored() throws {
      let server = try LoopbackUDPTestServer(replyDelay: 0.6) { request in
        sntpReply(to: request, serverAhead: 0)
      }
      defer { server.close() }
      let completions = CompletionCounter()

      let outcome = exchange(port: server.port, deadline: 0.2, counter: completions)
      // Let the late reply arrive.
      Thread.sleep(forTimeInterval: 0.8)

      XCTAssertEqual(outcome.result, .failure(.timeout))
      XCTAssertLessThan(outcome.elapsed, 0.5)
      XCTAssertEqual(completions.count, 1)
      assertConnectionCancelled(outcome.exchange)
    }

    func testUnreachablePortFailsWithinTheDeadline() throws {
      let port = try LoopbackUDPTestServer.unusedPort()

      let outcome = exchange(port: port, deadline: 1)

      XCTAssertNoThrow(try XCTUnwrap(outcome.result.failure))
      XCTAssertLessThan(outcome.elapsed, 1.5)
      assertConnectionCancelled(outcome.exchange)
    }

    func testCancellingWhileWaitingEndsTheAttemptOnce() throws {
      let server = try LoopbackUDPTestServer { _ in nil }
      defer { server.close() }
      let completions = CompletionCounter()
      let transport = SNTPUDPTransport(host: "127.0.0.1", port: server.port, deadline: 5)
      let done = expectation(description: "exchange completed")
      var result: Result<Data, SNTPFailure>?

      let exchange = transport.start(request) {
        result = $0
        completions.increment()
        done.fulfill()
      }
      waitUntil { server.receivedRequestCount == 1 }
      exchange.cancel()
      wait(for: [done], timeout: 2)

      XCTAssertEqual(result, .failure(.cancelled))
      exchange.cancel()
      Thread.sleep(forTimeInterval: 0.1)
      XCTAssertEqual(completions.count, 1)
      assertConnectionCancelled(exchange)
    }

    // MARK: - Helpers

    private struct Outcome {
      let result: Result<Data, SNTPFailure>
      let elapsed: TimeInterval
      let exchange: SNTPUDPTransport.Exchange
    }

    private func exchange(
      port: UInt16,
      deadline: TimeInterval?,
      wait timeout: TimeInterval = 3,
      counter: CompletionCounter = CompletionCounter()
    ) -> Outcome {
      let transport =
        deadline.map { SNTPUDPTransport(host: "127.0.0.1", port: port, deadline: $0) }
        ?? SNTPUDPTransport(host: "127.0.0.1", port: port)
      let done = expectation(description: "exchange completed")
      var result: Result<Data, SNTPFailure>?
      var elapsed: TimeInterval = 0
      let start = Date()
      let exchange = transport.start(request) {
        elapsed = Date().timeIntervalSince(start)
        result = $0
        counter.increment()
        done.fulfill()
      }
      wait(for: [done], timeout: timeout)
      return Outcome(
        result: result ?? .failure(.connectionFailed), elapsed: elapsed, exchange: exchange)
    }

    private func assertConnectionCancelled(
      _ exchange: SNTPUDPTransport.Exchange,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      waitUntil { exchange.connection.state == .cancelled }
      XCTAssertEqual(exchange.connection.state, .cancelled, file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
      let deadline = Date().addingTimeInterval(timeout)
      while !condition(), Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
      }
    }
  }

  final class CompletionCounter {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return value
    }

    func increment() {
      lock.lock()
      value += 1
      lock.unlock()
    }
  }

  extension Result {
    var failure: Failure? {
      if case let .failure(failure) = self {
        return failure
      }
      return nil
    }
  }

#endif
