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

/// Reasons why one SNTP attempt produced no clock offset.
enum SNTPFailure: Error, Equatable {
  case timeout
  case connectionFailed
  case cancelled
  case replyTooShort
  case originateTimeMismatch
  case serverUnsynchronized
  case invalidVersion
  case invalidMode
  case invalidTransmitTime
}

/// An SNTPv4 packet (RFC 4330). Timestamps are nanoseconds since the NTP epoch, 1900-01-01.
struct SNTPPacket: Equatable {
  static let size = 48
  static let version: UInt8 = 4
  static let clientMode: UInt8 = 3
  static let serverMode: UInt8 = 4

  private static let nanosPerSecond: Int64 = 1_000_000_000
  private static let ntpToUnixEpochNanos: Int64 = 2_208_988_800 * nanosPerSecond

  let leapIndicator: UInt8
  let version: UInt8
  let mode: UInt8
  let stratum: UInt8
  let originateTime: Int64
  let receiveTime: Int64
  let transmitTime: Int64

  static func ntpTime(unixNanos: Int64) -> Int64 {
    unixNanos + ntpToUnixEpochNanos
  }

  static func unixNanos(ntpTime: Int64) -> Int64 {
    ntpTime - ntpToUnixEpochNanos
  }

  /// The defaults describe a client request.
  init(
    leapIndicator: UInt8 = 0,
    version: UInt8 = SNTPPacket.version,
    mode: UInt8 = SNTPPacket.clientMode,
    stratum: UInt8 = 0,
    originateTime: Int64 = 0,
    receiveTime: Int64 = 0,
    transmitTime: Int64 = 0
  ) {
    self.leapIndicator = leapIndicator
    self.version = version
    self.mode = mode
    self.stratum = stratum
    self.originateTime = originateTime
    self.receiveTime = receiveTime
    self.transmitTime = transmitTime
  }

  /// Parses the fixed 48-byte header; returns `nil` for shorter input.
  init?(parsing data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= Self.size else {
      return nil
    }
    leapIndicator = (bytes[0] >> 6) & 0b11
    version = (bytes[0] >> 3) & 0b111
    mode = bytes[0] & 0b111
    stratum = bytes[1]
    originateTime = Self.readTimestamp(bytes, at: 24)
    receiveTime = Self.readTimestamp(bytes, at: 32)
    transmitTime = Self.readTimestamp(bytes, at: 40)
  }

  func encoded() -> Data {
    var bytes = [UInt8](repeating: 0, count: Self.size)
    bytes[0] = (leapIndicator & 0b11) << 6 | (version & 0b111) << 3 | (mode & 0b111)
    bytes[1] = stratum
    Self.writeTimestamp(originateTime, into: &bytes, at: 24)
    Self.writeTimestamp(receiveTime, into: &bytes, at: 32)
    Self.writeTimestamp(transmitTime, into: &bytes, at: 40)
    return Data(bytes)
  }

  /// Validates a server reply to `request` and returns the clock offset in nanoseconds,
  /// `((t2 - t1) + (t3 - t4)) / 2`, where `receiveTime` is t4.
  static func offset(
    request: SNTPPacket,
    reply data: Data,
    receiveTime t4: Int64
  ) -> Result<Int64, SNTPFailure> {
    guard let reply = SNTPPacket(parsing: data) else {
      return .failure(.replyTooShort)
    }
    let t1 = request.transmitTime
    if reply.originateTime / nanosPerSecond != t1 / nanosPerSecond {
      return .failure(.originateTimeMismatch)
    }
    // Stratum 0 is a kiss-o'-death reply; strata above 15 are unsynchronized or reserved.
    if reply.leapIndicator == 3 || reply.stratum == 0 || reply.stratum > 15 {
      return .failure(.serverUnsynchronized)
    }
    if reply.version != version {
      return .failure(.invalidVersion)
    }
    if reply.mode != serverMode {
      return .failure(.invalidMode)
    }
    if reply.transmitTime == 0 {
      return .failure(.invalidTransmitTime)
    }
    let t2 = reply.receiveTime
    let t3 = reply.transmitTime
    return .success(((t2 - t1) + (t3 - t4)) / 2)
  }

  // An NTP timestamp is 32 bits of seconds and 32 bits of 2^-32 second fractions.
  private static func readTimestamp(_ bytes: [UInt8], at offset: Int) -> Int64 {
    let seconds = readUInt32(bytes, at: offset)
    let fraction = readUInt32(bytes, at: offset + 4)
    let nanos = (UInt64(fraction) * UInt64(nanosPerSecond)) >> 32
    return Int64(seconds) * nanosPerSecond + Int64(nanos)
  }

  private static func writeTimestamp(_ time: Int64, into bytes: inout [UInt8], at offset: Int) {
    let clamped = max(time, 0)
    let seconds = UInt32(truncatingIfNeeded: clamped / nanosPerSecond)
    let nanos = UInt64(clamped % nanosPerSecond)
    let fraction = UInt32(truncatingIfNeeded: (nanos << 32) / UInt64(nanosPerSecond))
    writeUInt32(seconds, into: &bytes, at: offset)
    writeUInt32(fraction, into: &bytes, at: offset + 4)
  }

  private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
  }

  private static func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    for index in 0..<4 {
      bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (24 - 8 * index))
    }
  }
}
