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
import XCTest

@testable import ElasticApm

final class SNTPPacketTests: XCTestCase {
  private let seconds: Int64 = 3_900_000_000

  func testClientRequestEncodesVersionModeAndTransmitTime() {
    let transmitTime = seconds * nanosPerSecond + nanosPerSecond / 2

    let bytes = [UInt8](SNTPPacket(transmitTime: transmitTime).encoded())

    var expected = [UInt8](repeating: 0, count: 48)
    expected[0] = 0x23  // leap indicator 0, version 4, mode 3 (client)
    expected[40...47] = [0xE8, 0x75, 0x47, 0x00, 0x80, 0x00, 0x00, 0x00]
    XCTAssertEqual(bytes, expected)
  }

  func testParsesServerReplyHeaderAndTimestamps() throws {
    var bytes = [UInt8](repeating: 0, count: 48)
    bytes[0] = 0x24  // leap indicator 0, version 4, mode 4 (server)
    bytes[1] = 2
    bytes[24...31] = [0xE8, 0x75, 0x47, 0x00, 0x80, 0x00, 0x00, 0x00]
    bytes[32...39] = [0xE8, 0x75, 0x47, 0x7B, 0x40, 0x00, 0x00, 0x00]
    bytes[40...47] = [0xE8, 0x75, 0x47, 0x7B, 0xC0, 0x00, 0x00, 0x00]

    let packet = try XCTUnwrap(SNTPPacket(parsing: Data(bytes)))

    XCTAssertEqual(
      packet,
      SNTPPacket(
        leapIndicator: 0,
        version: 4,
        mode: 4,
        stratum: 2,
        originateTime: seconds * nanosPerSecond + 500_000_000,
        receiveTime: (seconds + 123) * nanosPerSecond + 250_000_000,
        transmitTime: (seconds + 123) * nanosPerSecond + 750_000_000))
  }

  func testEncodingRoundTripsWithinOneNanosecond() throws {
    let packet = SNTPPacket(
      leapIndicator: 1, version: 4, mode: 4, stratum: 3,
      originateTime: seconds * nanosPerSecond + 123_456_789,
      receiveTime: seconds * nanosPerSecond + 987_654_321,
      transmitTime: (seconds + 1) * nanosPerSecond + 1)

    let parsed = try XCTUnwrap(SNTPPacket(parsing: packet.encoded()))

    XCTAssertEqual(parsed.leapIndicator, 1)
    XCTAssertEqual(parsed.stratum, 3)
    XCTAssertEqual(Double(parsed.originateTime), Double(packet.originateTime), accuracy: 1)
    XCTAssertEqual(Double(parsed.receiveTime), Double(packet.receiveTime), accuracy: 1)
    XCTAssertEqual(Double(parsed.transmitTime), Double(packet.transmitTime), accuracy: 1)
  }

  func testOffsetAveragesBothLegsOfTheExchange() {
    let t1 = seconds * nanosPerSecond
    let request = SNTPPacket(transmitTime: t1)
    let reply = SNTPPacket(
      version: 4, mode: 4, stratum: 1,
      originateTime: t1,
      receiveTime: t1 + 30_200_000_000,
      transmitTime: t1 + 30_300_000_000
    ).encoded()

    let offset = SNTPPacket.offset(request: request, reply: reply, receiveTime: t1 + 400_000_000)

    // ((t2 - t1) + (t3 - t4)) / 2 = (30.2 s + 29.9 s) / 2; the wire format keeps
    // 2^-32 s fractions, so allow nanosecond rounding.
    XCTAssertEqual(Double(try offset.get()), 30_050_000_000, accuracy: 2)
  }

  func testRejectsEachInvalidReplyClass() {
    let request = SNTPPacket(transmitTime: seconds * nanosPerSecond)
    let requestData = request.encoded()

    for (expected, reply) in rejectedSNTPReplies(to: requestData) {
      let result = SNTPPacket.offset(
        request: request, reply: reply, receiveTime: request.transmitTime)
      XCTAssertEqual(result, .failure(expected))
    }
  }
}
