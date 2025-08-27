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

public class MockRequestService: RequestService {
  var responderQueue = [(RequestServiceCallback, ElasticApm.OpampRequest) -> ()]()

  private var callback: RequestServiceCallback!
  private var request: (any Supplier<OpampRequest>)!

  public func queueResponse(
    _ responder: @escaping (_ callback: RequestServiceCallback, _ request: ElasticApm.OpampRequest) -> ()
  ) {
    responderQueue.append(responder)

  }

  public func start(
    callback: any ElasticApm.RequestServiceCallback,
    request: any ElasticApm.Supplier<ElasticApm.OpampRequest>
  ) {
    self.callback = callback
    self.request = request
  }

  public func sendRequest() {
    let responder = responderQueue.removeFirst()
    responder(self.callback, self.request.get())
  }

  public func stop() {
    sendRequest()
  }

  
}
