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

public class OpampClientImplTests: XCTestCase {

  class NoopCallback : OpampClientCallback {
    public func onConnect(client: ElasticApm.OpampClientImpl) {

    }

    public func onConnectFailed(
      client: ElasticApm.OpampClientImpl,
      error: any Error,
      retryAfter: TimeInterval
    ) {

    }

    public func onErrorResponse(
      client: ElasticApm.OpampClientImpl,
      error: any Error,
      retryAfter: TimeInterval
    ) {

    }

    public func onMessage(
      client: ElasticApm.OpampClientImpl,
      message: ElasticApm.OpampMessage
    ) {

    }

  }

  public typealias Client = OpampClientImpl

  func testBasicClientToServerInteraction() {


    // initial call to server
    let requestService = MockRequestService()
    requestService.queueResponse {
 callback,
 request in
      XCTAssertEqual(request.agentToServer.sequenceNum, 1)
      XCTAssertEqual(
        request.agentToServer.capabilities,
        UInt64(
          Opamp_Proto_AgentCapabilities.reportsStatus.rawValue
          | Opamp_Proto_AgentCapabilities.acceptsRemoteConfig.rawValue
          | Opamp_Proto_AgentCapabilities.reportsEffectiveConfig.rawValue
          | Opamp_Proto_AgentCapabilities.reportsRemoteConfig.rawValue
        )
      )
      XCTAssertEqual(
        request.agentToServer.remoteConfigStatus.status,
        Opamp_Proto_RemoteConfigStatuses.unset
      )
      XCTAssertTrue(request.agentToServer.hasRemoteConfigStatus)
      XCTAssertTrue(request.agentToServer.hasEffectiveConfig)
      XCTAssertTrue(request.agentToServer.hasAgentDescription)
      XCTAssertNotNil(request.agentToServer.instanceUid)

      XCTAssertFalse(request.agentToServer.hasAgentDisconnect)

      let config_json = """
        {
          "recording" : true,
          "sampleRate": 0.9
        }
        """
      var agentConfigFile = Opamp_Proto_AgentConfigFile()
      agentConfigFile.body = config_json.data(using: .utf8)!
      var response = Opamp_Proto_ServerToAgent()
      response.instanceUid = request.agentToServer.instanceUid
      response.remoteConfig.config.configMap = [ "elastic" : agentConfigFile]
      response.remoteConfig.configHash =  response.remoteConfig.config.configMap.description
        .data(using: .utf8)!
      callback.onRequestSuccess(response: OpampResponse(serverToAgent: response))
    }

    // second call to service, report with updated configuration
    requestService.queueResponse { callback, request in
      XCTAssertEqual(request.agentToServer.sequenceNum, 2)
      XCTAssertTrue(request.agentToServer.effectiveConfig.hasConfigMap)
      XCTAssertTrue(request.agentToServer.hasRemoteConfigStatus)
      XCTAssertTrue(request.agentToServer.hasEffectiveConfig)
      XCTAssertFalse(request.agentToServer.hasAgentDescription)
      XCTAssertNotNil(request.agentToServer.instanceUid)


      var response = Opamp_Proto_ServerToAgent()
      response.instanceUid = request.agentToServer.instanceUid
      callback.onRequestSuccess(response: OpampResponse(serverToAgent: response))

    }

    //third report to service with no changes to configs, reduced payload
    requestService.queueResponse { callback, request in
      XCTAssertEqual(request.agentToServer.sequenceNum, 3)

      XCTAssertFalse(request.agentToServer.effectiveConfig.hasConfigMap)
      XCTAssertFalse(request.agentToServer.hasRemoteConfigStatus)
      XCTAssertFalse(request.agentToServer.hasEffectiveConfig)
      XCTAssertFalse(request.agentToServer.hasAgentDescription)

      var response = Opamp_Proto_ServerToAgent()
      response.instanceUid = request.agentToServer.instanceUid
      callback.onRequestSuccess(response: OpampResponse(serverToAgent: response))
    }


    let cond = NSCondition()

    // final call, disconnected
    requestService.queueResponse { callback, request in
//      cond.lock()
      XCTAssertEqual(request.agentToServer.sequenceNum, 4)

      XCTAssertFalse(request.agentToServer.effectiveConfig.hasConfigMap)
      XCTAssertFalse(request.agentToServer.hasRemoteConfigStatus)
      XCTAssertFalse(request.agentToServer.hasEffectiveConfig)
      XCTAssertFalse(request.agentToServer.hasAgentDescription)
      XCTAssertTrue(request.agentToServer.hasAgentDisconnect)
      var response = Opamp_Proto_ServerToAgent()
      response.instanceUid = request.agentToServer.instanceUid
      callback.onRequestSuccess(response: OpampResponse(serverToAgent: response))
    }


    let client = OpampClient.builder()
      .setServiceName("testService")
      .enableRemoteConfig()
      .enableEffectiveConfigReporting()
      .build(
      requestService: requestService
    )

    client.start(NoopCallback()) // first request
    requestService.sendRequest() // second request
    requestService.sendRequest() // third request
    client.stop() // disconnect request
  }
}
