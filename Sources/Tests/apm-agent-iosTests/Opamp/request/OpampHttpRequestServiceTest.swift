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
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(
          agentToServer: Opamp_Proto_AgentToServer()
        )
        }
      )

    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) }
      )
    // calling start twice makes no changes
    XCTAssertTrue(requestService.isRunning)
    XCTAssertFalse(requestService.isStopped)

    requestService.stop()

    XCTAssertTrue(requestService.isStopped)

    requestService
      .start(
        callback: MockRequestServiceCallback(),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) }
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
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) }
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
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) }
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
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) })

    cond.lock()
    while (isWaiting) {
      cond.wait()
    }
    cond.unlock()
    requestService.stop()
  }

  func testHttpFailureUpdatesRetryDelayHeader() {
    let cond = NSCondition()
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender(
sender: {
        let response = HTTPURLResponse(url: URL(string: "http://localhost")!,
                                       statusCode: 503,
                                       httpVersion: nil,
                                       headerFields: ["Retry-After": "3"]
                                               )!
  return .success((OpampResponse(serverToAgent:  Opamp_Proto_ServerToAgent()), response))

      }),
      requestDelay: 1.0,
      retryDelay: 1000.0
    )

    let start = Date()
    var isWaiting = true
    var iteration = 0
    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestFailed: {
            error,
            delay in
            XCTAssert((error as NSError).code == 503)
            iteration+=1
            if iteration == 1 {
              XCTAssertEqual(Date().timeIntervalSince1970 - start.timeIntervalSince1970, 1.0, accuracy: 0.5,
                             "reqeustDelay incorrect"
              )
            } else if (iteration == 2) {
              // second iteration should be on the retryDelay timescale
              XCTAssertEqual(
                Date().timeIntervalSince1970 - start.timeIntervalSince1970,
                4.0,
                accuracy: 0.5,
                "retryDelay with exponential backoff incorrect"
              )
              cond.lock()
              isWaiting = false
              cond.broadcast()
              cond.unlock()
            }
          }),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) })


    cond.lock()
    while (isWaiting) {
      cond.wait()
    }
    cond.unlock()
    requestService.stop()
  }

  func testRetryErrorResponse() {
    let cond = NSCondition()

    var serverToAgent = Opamp_Proto_ServerToAgent()
    serverToAgent.errorResponse = Opamp_Proto_ServerErrorResponse()
    serverToAgent.errorResponse.errorMessage = "error"

    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getSuccess(with: OpampResponse.init(serverToAgent: serverToAgent)),
      requestDelay: 5.0,
      retryDelay: 1.0
    )

    let start = Date()
    var isWaiting = true
    var iteration = 0
    requestService
      .start(
        callback: MockRequestServiceCallback(
         onRequestSuccess: {
           response
             in
           iteration+=1
           if iteration == 1 {
             XCTAssertEqual(Date().timeIntervalSince1970 - start.timeIntervalSince1970, 5.0, accuracy: 0.5,
              "reqeustDelay incorrect"
             )
           } else if (iteration == 2) {
             // second iteration should be on the retryDelay timescale
             XCTAssertEqual(
              Date().timeIntervalSince1970 - start.timeIntervalSince1970,
              6.0,
              accuracy: 0.5,
              "retryDelay with exponential backoff incorrect"
             )
             cond.lock()
             isWaiting = false
             cond.broadcast()
             cond.unlock()
           }
          }),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) })

    cond.lock()
    while (isWaiting) {
      cond.wait()
    }
    cond.unlock()
    requestService.stop()
  }

  func testHandleMessageRetryDelayUpdated() {
    let cond = NSCondition()

    var serverToAgent = Opamp_Proto_ServerToAgent()
    serverToAgent.errorResponse = Opamp_Proto_ServerErrorResponse()
    serverToAgent.errorResponse.errorMessage = "error"
    serverToAgent.errorResponse.type = .unavailable
    serverToAgent.errorResponse.retryInfo = Opamp_Proto_RetryInfo()
    serverToAgent.errorResponse.retryInfo.retryAfterNanoseconds = 1_000_000_000 // 1 seconds
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getSuccess(with: OpampResponse.init(serverToAgent: serverToAgent)),
      requestDelay: 1.0,
      retryDelay: 1000.0
    )

    let start = Date()
    var isWaiting = true
    var iteration = 0
    requestService
      .start(
        callback: MockRequestServiceCallback(
          onRequestSuccess: {
            response
            in
            iteration+=1
            if iteration == 1 {
              XCTAssertEqual(Date().timeIntervalSince1970 - start.timeIntervalSince1970, 1.0, accuracy: 0.5,
                             "reqeustDelay incorrect"
              )
            } else if (iteration == 2) {
              // second iteration should be on the retryDelay timescale
              XCTAssertEqual(
                Date().timeIntervalSince1970 - start.timeIntervalSince1970,
                2.0,
                accuracy: 0.5,
                "retryDelay with exponential backoff incorrect"
              )
              cond.lock()
              isWaiting = false
              cond.broadcast()
              cond.unlock()
            }
          }),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) })

    cond.lock()
    while (isWaiting && Date().timeIntervalSince1970 - start.timeIntervalSince1970 < 10.0) {
      cond.wait()
    }
    XCTAssertEqual(iteration, 2, "Timed Out: ReqeustService did not update retry delay from message.")
    cond.unlock()
    requestService.stop()

  }

  func testHandleNetworkError() {
    let cond = NSCondition()
    let retryDelay = 1.0
    let requestDelay = 3.0
    let requestService = OpampHttpRequestService(
      httpClient: MockOpampSender
        .getWith(
          error: NSError(
            domain: HTTPURLResponse
              .localizedString(forStatusCode: NSURLErrorTimedOut),
            code:NSURLErrorTimedOut
          )
        ),
      requestDelay: requestDelay,
      retryDelay: retryDelay
    )

    let start = Date()
    var isWaiting = true
    var iteration = 0
    requestService
      .start(
        callback: MockRequestServiceCallback(
          onConnectFailure: {
            error,
 timeInterval
            in
            iteration+=1
            if iteration == 1 {
              XCTAssertEqual(
                Date().timeIntervalSince1970 - start.timeIntervalSince1970,
                requestDelay,
                accuracy: 0.5,
                             "reqeustDelay incorrect"
              )
            } else if (iteration == 2) {
              // second iteration should be on the retryDelay timescale
              XCTAssertEqual(
                timeInterval,
                retryDelay,
                accuracy: 0.5,
              )

              XCTAssertEqual(
                Date().timeIntervalSince1970 - start.timeIntervalSince1970,
                requestDelay + retryDelay, accuracy: 0.5,
              )
              cond.lock()
              isWaiting = false
              cond.broadcast()
              cond.unlock()
            }
          }),
        request: AnonymousSupplier<OpampRequest> { return OpampRequest(agentToServer: Opamp_Proto_AgentToServer()) }
      )

    cond.lock()
    while (isWaiting && Date().timeIntervalSince1970 - start.timeIntervalSince1970 < 10.0) {
      cond.wait()
    }
    XCTAssertEqual(iteration, 2, "Timed Out: ReqeustService did not retry.")
    cond.unlock()
    requestService.stop()

  }
}
