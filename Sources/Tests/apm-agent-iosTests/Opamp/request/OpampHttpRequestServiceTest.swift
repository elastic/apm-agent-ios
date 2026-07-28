//
//  Copyright © 2025  Elasticsearch BV
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
import XCTest
@testable import ElasticApm

public class OpampHttpRequestServiceTest: XCTestCase {

  private func emptyRequestSupplier() -> AnonymousSupplier<OpampRequest> {
    return AnonymousSupplier<OpampRequest> {
      return OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
    }
  }

  func testRequestServiceStates() {
    let timer = MockRequestTimer()
    let sender = MockOpampSender.getWith(statusCode: 500)
    let requestService = OpampHttpRequestService(
      httpClient: sender,
      requestDelay: 30.0,
      retryDelay: 1.0,
      timer: timer
    )

    XCTAssertFalse(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService.stop()
    // stopping before started makes no changes
    XCTAssertFalse(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)
    XCTAssertFalse(timer.isCancelled)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: emptyRequestSupplier()
      )

    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)
    XCTAssertTrue(timer.isActivated)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: emptyRequestSupplier()
      )
    // calling start twice makes no changes
    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService.stop()

    XCTAssertTrue(requestService.isStopped)
    XCTAssertTrue(timer.isCancelled)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: emptyRequestSupplier()
      )
    // starting after stop makes no changes
    XCTAssertTrue(requestService.isStopped)

    requestService.sendRequest()
    timer.fire()
    // the cancelled timer no longer fires, so no request is sent
    XCTAssertEqual(sender.sendCount, 0, "requestService sendRequest executed")
  }

  func testReqeustServiceSendsOnDemand() {
    let timer = MockRequestTimer()
    let requestFailed = expectation(description: "request failed callback")
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender.getWith(statusCode: 500),
      requestDelay: 30.0,
      retryDelay: 1.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(onRequestFailed: { _, _ in
          requestFailed.fulfill()
        }),
        request: emptyRequestSupplier()
      )

    // the initial schedule waits a full requestDelay
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 30.0, repeating: 30.0)
    )

    requestService.sendRequest()
    // sending on demand reschedules the timer to fire immediately
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 0, repeating: 30.0)
    )

    timer.fire()
    wait(for: [requestFailed], timeout: 10.0)
    requestService.stop()
  }

  func testHttpFailedRequest() {
    let timer = MockRequestTimer()
    let requestFailed = expectation(description: "request failed callback")
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender.getWith(statusCode: 500),
      requestDelay: 5.0,
      retryDelay: 1.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestFailed: { error, retryAfter in
            XCTAssertEqual((error as NSError).code, 500)
            XCTAssertEqual(retryAfter, 1.0)
            requestFailed.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    timer.fire()
    // a failed request enables retry mode on the retryDelay timescale
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 1.0, repeating: 1.0)
    )
    wait(for: [requestFailed], timeout: 10.0)
    requestService.stop()
  }

  func testHttpFailedConnect() {
    let timer = MockRequestTimer()
    let connectFailed = expectation(description: "connection failure callback")
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(
          error: NSError(
            domain: HTTPURLResponse
              .localizedString(forStatusCode: NSURLErrorTimedOut),
            code: NSURLErrorTimedOut
          )
        ),
      requestDelay: 5.0,
      retryDelay: 1.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onConnectFailure: { error, retryAfter in
            XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut)
            XCTAssertEqual(retryAfter, 1.0)
            connectFailed.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    timer.fire()
    // a network error enables retry mode with exponential backoff (1 skip)
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 1.0, repeating: 1.0)
    )
    wait(for: [connectFailed], timeout: 10.0)
    requestService.stop()
  }

  func testHttpFailureUpdatesRetryDelayHeader() {
    let timer = MockRequestTimer()
    let requestFailed = expectation(description: "request failed callback")
    requestFailed.expectedFulfillmentCount = 2
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender(
        sender: {
          let response = HTTPURLResponse(
            url: URL(string: "http://localhost")!,
            statusCode: 503,
            httpVersion: nil,
            headerFields: ["Retry-After": "3"]
          )!
          return .success((OpampResponse(serverToAgent: Opamp_Proto_ServerToAgent()), response))
        }),
      requestDelay: 1.0,
      retryDelay: 1000.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestFailed: { error, retryAfter in
            XCTAssertEqual((error as NSError).code, 503)
            // the Retry-After header takes precedence over the configured retryDelay
            XCTAssertEqual(retryAfter, 3.0)
            requestFailed.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    timer.fire()
    // retry mode uses the Retry-After header value
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 3.0, repeating: 3.0)
    )

    let schedulesAfterFirstFailure = timer.schedules.count
    timer.fire()
    // retry mode is already enabled, so the second failure does not reschedule
    XCTAssertEqual(timer.schedules.count, schedulesAfterFirstFailure)

    wait(for: [requestFailed], timeout: 10.0)
    requestService.stop()
  }

  func testRetryErrorResponse() {
    let timer = MockRequestTimer()
    let requestSucceeded = expectation(description: "request success callback")
    requestSucceeded.expectedFulfillmentCount = 2

    var serverToAgent = Opamp_Proto_ServerToAgent()
    serverToAgent.errorResponse = Opamp_Proto_ServerErrorResponse()
    serverToAgent.errorResponse.errorMessage = "error"

    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getSuccess(with: OpampResponse.init(serverToAgent: serverToAgent)),
      requestDelay: 5.0,
      retryDelay: 1.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestSuccess: { _ in
            requestSucceeded.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    timer.fire()
    // the server error response enables retry mode on the retryDelay timescale
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 1.0, repeating: 1.0)
    )

    timer.fire()
    // the successful HTTP response first restores the requestDelay schedule,
    // then the embedded error response re-enables retry mode
    XCTAssertEqual(
      timer.schedules.suffix(2),
      [
        MockRequestTimer.Schedule(delay: 5.0, repeating: 5.0),
        MockRequestTimer.Schedule(delay: 1.0, repeating: 1.0)
      ]
    )

    wait(for: [requestSucceeded], timeout: 10.0)
    requestService.stop()
  }

  func testHandleMessageRetryDelayUpdated() {
    let timer = MockRequestTimer()
    let requestSucceeded = expectation(description: "request success callback")

    var serverToAgent = Opamp_Proto_ServerToAgent()
    serverToAgent.errorResponse = Opamp_Proto_ServerErrorResponse()
    serverToAgent.errorResponse.errorMessage = "error"
    serverToAgent.errorResponse.type = .unavailable
    serverToAgent.errorResponse.retryInfo = Opamp_Proto_RetryInfo()
    serverToAgent.errorResponse.retryInfo.retryAfterNanoseconds = 1_000_000_000 // 1 second
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getSuccess(with: OpampResponse.init(serverToAgent: serverToAgent)),
      requestDelay: 1.0,
      retryDelay: 1000.0,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestSuccess: { _ in
            requestSucceeded.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    timer.fire()
    // the message's retry info takes precedence over the configured retryDelay
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: 1.0, repeating: 1.0)
    )
    wait(for: [requestSucceeded], timeout: 10.0)
    requestService.stop()
  }

  func testHandleNetworkError() {
    let timer = MockRequestTimer()
    let connectFailed = expectation(description: "connection failure callback")
    connectFailed.expectedFulfillmentCount = 2
    let retryDelay = 1.0
    let requestDelay = 3.0
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(
          error: NSError(
            domain: HTTPURLResponse
              .localizedString(forStatusCode: NSURLErrorTimedOut),
            code: NSURLErrorTimedOut
          )
        ),
      requestDelay: requestDelay,
      retryDelay: retryDelay,
      timer: timer
    )

    requestService
      .start(
        callback: MockRequestServiceCallback(
          onConnectFailure: { error, timeInterval in
            XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut)
            XCTAssertEqual(timeInterval, retryDelay)
            connectFailed.fulfill()
          }),
        request: emptyRequestSupplier()
      )

    // the initial schedule waits a full requestDelay
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: requestDelay, repeating: requestDelay)
    )

    timer.fire()
    // the first network error enables retry mode on the retryDelay timescale
    XCTAssertEqual(
      timer.lastSchedule,
      MockRequestTimer.Schedule(delay: retryDelay, repeating: retryDelay)
    )

    let schedulesAfterFirstFailure = timer.schedules.count
    timer.fire()
    // retry mode is already enabled, so further failures do not reschedule
    XCTAssertEqual(timer.schedules.count, schedulesAfterFirstFailure)

    wait(for: [connectFailed], timeout: 10.0)
    requestService.stop()
  }
}
