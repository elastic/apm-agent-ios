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

public class OpampHttpRequestServiceTest : XCTestCase {

  func testRequestServiceStates() {

    let cond = NSCondition()

    var counter = 0

    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(statusCode: 500),
      requestDelay: 50000.0,
      retryDelay: 1.0
    )

    XCTAssertFalse(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService.stop()
    // stopping before started makes no changes
    XCTAssertFalse(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)


    requestService
      .start(
        callback: MockRequestServiceCallback(onRequestFailed: { error, delay in
          cond.lock()
          counter += 1
          cond.broadcast()
          cond.unlock()
        }),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )

    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )
    // calling start twice makes no changes
    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService.stop()

    XCTAssertTrue(requestService.isStopped)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )

    XCTAssertTrue(requestService.isStopped)

    requestService.sendRequest() // noop?

    let start = Date()
    cond.lock()
    while (counter < 1 && Date().timeIntervalSince1970 - start.timeIntervalSince1970 < 10.0) {
      cond.wait(until: Date(timeIntervalSinceNow: 1.0))
    }
    XCTAssertEqual(counter, 0, "requestService sendRequest executed")
    cond.unlock()

  }

  func testReqeustServiceSendsOnDemand() {
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(statusCode: 500),
      requestDelay: 10000.0,
      retryDelay: 1.0
    )

    let cond = NSCondition()
    var counter = 0
    var start = Date()
    requestService
      .start(
        callback: MockRequestServiceCallback(onRequestFailed: { error, delay in
          cond.lock()
          counter += 1
          let date = Date()
          if (counter == 1) {

            XCTAssertLessThan(date.timeIntervalSince1970 - start.timeIntervalSince1970, 10, "callback executed much sooner than reqeustDelay")
            start = date
          } else if counter == 2 {
            XCTAssertEqual(date.timeIntervalSince1970 - start.timeIntervalSince1970, 1.0, accuracy: 1.0, "Retry delay is only about 1 second")
          }
          cond.broadcast()
          cond.unlock()
        }),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )
      requestService.sendRequest()

    cond.lock()
    while (counter < 2 && Date().timeIntervalSince1970 - start.timeIntervalSince1970 < 20.0) {
      cond.wait(until: Date(timeIntervalSinceNow: 1.0))
    }
    XCTAssertEqual(counter, 2, "condtional timed out")
    cond.unlock()
    requestService.stop()
  }

  func testHttpFailedRequest() {
    let cond = NSCondition()
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(statusCode: 500),
      requestDelay: 5.0,
      retryDelay: 1.0
    )


    let start = Date()
    var isWaiting = true
    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestFailed: {
            error,
            delay in
            let end = Date()
            XCTAssert((error as NSError).code == 500)
            XCTAssertEqual(
              end.timeIntervalSince1970 - start.timeIntervalSince1970,
              5.0,
              accuracy: 1.0
            )
            cond.lock()
            isWaiting = false
            cond.broadcast()
            cond.unlock()
          }),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )

    cond.lock()
    while (isWaiting) {
      cond.wait()
    }
    cond.unlock()
    requestService.stop()
  }


  func testHttpFailedConnect() {
    let cond = NSCondition()
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(
          error: NSError(
            domain: HTTPURLResponse
              .localizedString(forStatusCode:NSURLErrorTimedOut),
            code:NSURLErrorTimedOut
          )
        ),
      requestDelay: 5.0,
      retryDelay: 1.0
    )

    let start = Date()
    var isWaiting = true
    requestService
      .start(
        callback: MockRequestServiceCallback(
          onConnectFailure: {
            error,
            delay in
            let end = Date()
            XCTAssert((error as NSError).code == NSURLErrorTimedOut)
            XCTAssertEqual(
              end.timeIntervalSince1970 - start.timeIntervalSince1970,
              5.0,
              accuracy: 1.0
            )
            cond.lock()
            isWaiting = false
            cond.broadcast()
            cond.unlock()
          }),
        request: OpampRequest(agentToServer: Opamp_Proto_AgentToServer())
      )

    cond.lock()
    while (isWaiting) {
      cond.wait()
    }
    cond.unlock()
    requestService.stop()
  }
}
