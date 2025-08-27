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
@testable import ElasticApm

class MockRequestServiceCallback: RequestServiceCallback {

  let onConnectionFailureCallback: ((Error, TimeInterval) -> Void)?

  let onRequestSuccessCallback: ((OpampResponse) -> Void)?

  let onRequestFailedCallback: ((Error, TimeInterval) -> Void)?

  init (
    onConnectFailure: ((Error, TimeInterval) -> Void)? = nil,
    onRequestSuccess: ((OpampResponse) -> Void)? = nil,
    onRequestFailed: ((Error, TimeInterval) -> Void)? = nil
  ) {
    self.onRequestFailedCallback = onRequestFailed
    self.onConnectionFailureCallback = onConnectFailure
    self.onRequestSuccessCallback = onRequestSuccess
  }

  func onConnectionSuccess() {
    // noop; only for socket
  }

  func onConnectionFailure(error: Error, retryAfter: TimeInterval)
  {
    self.onConnectionFailureCallback?(error, retryAfter)
  }

  func onRequestSuccess(response: OpampResponse)
  {
    self.onRequestSuccessCallback?(response)
  }

  func onRequestFailed(error: Error, retryAfter: TimeInterval)
  {
    self.onRequestFailedCallback?(error, retryAfter)
  }
}
