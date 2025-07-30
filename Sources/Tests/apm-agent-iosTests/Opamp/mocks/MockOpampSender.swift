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


class MockOpampSender: OpampSender {
  func send(
    opampRequest: ElasticApm.OpampRequest,
    completion: @escaping (
      Result<(ElasticApm.OpampResponse, URLResponse), any Error>
    ) -> Void
  ) {
    completion(sender())
  }


  let sender: () -> Result<(OpampResponse, URLResponse), Error>

  init(sender: @escaping () -> Result<(OpampResponse, URLResponse), Error>) {
    self.sender = sender
  }

  static func getWith(error: Error) -> MockOpampSender {
    return MockOpampSender {
        .failure(error)
    }
  }

  static func getWith(statusCode: Int) -> MockOpampSender {
    return MockOpampSender {
        .success(
          (
            OpampResponse(serverToAgent: Opamp_Proto_ServerToAgent()),
            HTTPURLResponse(
              url: OpampHttpRequestService.defaultURL,
              statusCode: statusCode,
              httpVersion: nil,
              headerFields: nil
            )!
          )
        )
    }
  }

  class func getSuccess(with response: OpampResponse) -> MockOpampSender {
    return MockOpampSender {
      .success(
        (
          response,
          HTTPURLResponse(
            url:OpampHttpRequestService.defaultURL ,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
      )
    }
  }
}
