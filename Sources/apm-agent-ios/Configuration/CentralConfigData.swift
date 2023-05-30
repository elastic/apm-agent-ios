// Copyright © 2023 Elasticsearch BV
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

public struct CentralConfigData: Codable {

  public var recording: Bool = true
  public var sampleRate: Double? = nil

  enum CodingKeys: String, CodingKey {
    case recording
    case sampleRate
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)

    do {
      recording = (try values.decode(String.self, forKey: .recording) as NSString).boolValue
    } catch {
      recording = true
    }

    do {
      sampleRate = try values.decode(Double.self, forKey: .sampleRate)
    } catch {}
  }

  init() {}
}
