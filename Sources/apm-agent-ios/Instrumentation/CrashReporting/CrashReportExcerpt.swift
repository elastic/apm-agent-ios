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

#if !os(watchOS)
  import Foundation

  enum CrashReportExcerpt {
    static let maxCharacterCount = 7_500

    static func compose(_ report: String, budget: Int = maxCharacterCount) -> String {
      guard !report.isEmpty, budget > 0 else {
        return ""
      }

      let normalized = report.replacingOccurrences(of: "\r\n", with: "\n")
      guard let parsed = ParsedReport(normalized) else {
        return String(normalized.prefix(budget))
      }

      guard let frameLimit = largestFrameLimit(for: parsed, budget: budget) else {
        return String(parsed.render(frameLimit: 1).prefix(budget))
      }

      var secondaryThreads = [FrameSection]()
      var excerpt = parsed.render(frameLimit: frameLimit)
      for thread in parsed.secondaryThreads {
        let candidate = parsed.render(frameLimit: frameLimit, secondaryThreads: secondaryThreads + [thread])
        guard candidate.count <= budget else {
          break
        }
        secondaryThreads.append(thread)
        excerpt = candidate
      }

      return excerpt
    }

    /// Returns the largest frame limit whose excerpt fits the budget, or `nil` when even one frame does not fit.
    /// The excerpt grows with the limit, so a binary search keeps the number of renders logarithmic.
    private static func largestFrameLimit(for report: ParsedReport, budget: Int) -> Int? {
      let fullFrameLimit = report.shortenableSections.map(\.frames.count).max() ?? 0
      guard report.render(frameLimit: fullFrameLimit).count > budget else {
        return fullFrameLimit
      }

      var fittingLimit: Int?
      var lowerLimit = 1
      var upperLimit = fullFrameLimit - 1
      while lowerLimit <= upperLimit {
        let limit = (lowerLimit + upperLimit) / 2
        if report.render(frameLimit: limit).count <= budget {
          fittingLimit = limit
          lowerLimit = limit + 1
        } else {
          upperLimit = limit - 1
        }
      }
      return fittingLimit
    }
  }

  private extension CrashReportExcerpt {
    struct ParsedReport {
      let header: [String]
      let applicationInformation: [String]?
      let lastExceptionBacktrace: FrameSection?
      let crashedThread: FrameSection
      let secondaryThreads: [FrameSection]
      let images: [ImageLine]?

      /// The sections shortened by the frame limit: the last exception backtrace and the crashed thread.
      var shortenableSections: [FrameSection] {
        [lastExceptionBacktrace, crashedThread].compactMap { $0 }
      }

      init?(_ report: String) {
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let markers = lines.enumerated().compactMap { index, line -> Marker? in
          if line == "Application Specific Information:" {
            return Marker(index: index, kind: .applicationInformation)
          }
          if line == "Last Exception Backtrace:" {
            return Marker(index: index, kind: .lastExceptionBacktrace)
          }
          if let isCrashed = FrameSection.threadHeader(line) {
            return Marker(index: index, kind: .thread(isCrashed: isCrashed))
          }
          if line.hasPrefix("Thread "), line.contains(" crashed with "), line.hasSuffix(" Thread State:") {
            return Marker(index: index, kind: .registerState)
          }
          if line == "Binary Images:" {
            return Marker(index: index, kind: .binaryImages)
          }
          return nil
        }

        guard let firstMarker = markers.first else {
          return nil
        }

        header = Self.trimmed(Array(lines[..<firstMarker.index]))
        var applicationInformation: [String]?
        var lastExceptionBacktrace: FrameSection?
        var threads = [(isCrashed: Bool, section: FrameSection)]()
        var images: [ImageLine]?

        for (position, marker) in markers.enumerated() {
          let end = position + 1 < markers.count ? markers[position + 1].index : lines.count
          let section = Self.trimmed(Array(lines[marker.index ..< end]))

          switch marker.kind {
          case .applicationInformation:
            applicationInformation = section.map(Self.truncatingApplicationReason)
          case .lastExceptionBacktrace:
            lastExceptionBacktrace = FrameSection(lines: section)
          case let .thread(isCrashed):
            threads.append((isCrashed, FrameSection(lines: section)))
          case .registerState:
            break
          case .binaryImages:
            images = section.dropFirst().compactMap(ImageLine.init(line:))
          }
        }

        guard !threads.isEmpty else {
          return nil
        }

        let crashedIndex = threads.firstIndex(where: \.isCrashed) ?? threads.startIndex
        crashedThread = threads[crashedIndex].section
        secondaryThreads = threads.indices.filter { $0 != crashedIndex }.map { threads[$0].section }
        self.applicationInformation = applicationInformation
        self.lastExceptionBacktrace = lastExceptionBacktrace
        self.images = images
      }

      func render(frameLimit: Int, secondaryThreads: [FrameSection] = []) -> String {
        let frameSections = shortenableSections.map { $0.limited(toFrames: frameLimit) } + secondaryThreads
        var sections = [header, applicationInformation].compactMap { $0 } + frameSections.map(\.lines)

        if let images {
          let references = Set(frameSections.flatMap(\.frames).compactMap(\.baseAddress))
          sections.append(["Binary Images:"] + images.filter { references.contains($0.startAddress) }.map(\.line))
        }

        return sections
          .filter { !$0.isEmpty }
          .map { $0.joined(separator: "\n") }
          .joined(separator: "\n\n") + "\n"
      }

      private static func trimmed(_ lines: [String]) -> [String] {
        var result = lines
        while result.first?.isEmpty == true {
          result.removeFirst()
        }
        while result.last?.isEmpty == true {
          result.removeLast()
        }
        return result
      }

      private static func truncatingApplicationReason(_ line: String) -> String {
        let marker = "reason: '"
        guard let markerRange = line.range(of: marker) else {
          return line
        }
        let reasonStart = markerRange.upperBound
        guard let reasonEnd = line[reasonStart...].lastIndex(of: "'") else {
          return line
        }
        let reason = line[reasonStart ..< reasonEnd]
        guard reason.count > 1_000 else {
          return line
        }
        return String(line[..<reasonStart])
          + String(reason.prefix(1_000))
          + " [truncated]"
          + String(line[reasonEnd...])
      }
    }

    struct Marker {
      enum Kind {
        case applicationInformation
        case lastExceptionBacktrace
        case thread(isCrashed: Bool)
        case registerState
        case binaryImages
      }

      let index: Int
      let kind: Kind
    }

    /// A section headed by one line and followed by frame lines: a thread or the last exception backtrace.
    struct FrameSection {
      static let tailFrameCount = 10
      static let minimumHeadFrameCount = 20

      let lines: [String]

      var frames: [Frame] {
        lines.dropFirst().compactMap(Frame.init(line:))
      }

      /// Returns whether a `Thread N Crashed:` or `Thread N:` line marks a crashed thread, or `nil` for any other line.
      static func threadHeader(_ line: String) -> Bool? {
        guard line.hasPrefix("Thread ") else {
          return nil
        }

        let suffix: String
        let isCrashed: Bool
        if line.hasSuffix(" Crashed:") {
          suffix = " Crashed:"
          isCrashed = true
        } else if line.hasSuffix(":") {
          suffix = ":"
          isCrashed = false
        } else {
          return nil
        }

        let numberStart = line.index(line.startIndex, offsetBy: "Thread ".count)
        let numberEnd = line.index(line.endIndex, offsetBy: -suffix.count)
        guard numberStart < numberEnd, Int(line[numberStart ..< numberEnd]) != nil else {
          return nil
        }
        return isCrashed
      }

      /// Keeps at most `limit` frames. The tail grows to `tailFrameCount` frames only once the head has
      /// `minimumHeadFrameCount` frames, and one marker line replaces the omitted middle.
      func limited(toFrames limit: Int) -> FrameSection {
        let frames = self.frames
        guard frames.count > limit else {
          return self
        }

        let tailCount = min(Self.tailFrameCount, max(0, limit - Self.minimumHeadFrameCount))
        let headCount = limit - tailCount
        return FrameSection(
          lines: [lines[0]]
            + frames.prefix(headCount).map(\.line)
            + ["... \(frames.count - limit) frames omitted"]
            + frames.suffix(tailCount).map(\.line)
        )
      }
    }

    struct Frame {
      let line: String
      let baseAddress: UInt64?

      init?(line: String) {
        let addresses = hexadecimalValues(in: line)
        guard addresses.count >= 2,
              let frameNumber = line.split(whereSeparator: \.isWhitespace).first,
              Int(frameNumber) != nil else {
          return nil
        }

        self.line = line
        baseAddress = addresses[1] == 0 ? nil : addresses[1]
      }
    }

    struct ImageLine {
      let startAddress: UInt64
      let line: String

      init?(line: String) {
        guard let startAddress = hexadecimalValues(in: line).first else {
          return nil
        }
        self.startAddress = startAddress
        self.line = line
      }
    }

    static func hexadecimalValues(in line: String) -> [UInt64] {
      var values = [UInt64]()
      var index = line.startIndex

      while index < line.endIndex {
        guard line[index] == "0" else {
          index = line.index(after: index)
          continue
        }
        let xIndex = line.index(after: index)
        guard xIndex < line.endIndex, line[xIndex] == "x" else {
          index = xIndex
          continue
        }

        var end = line.index(after: xIndex)
        while end < line.endIndex, line[end].isHexDigit {
          end = line.index(after: end)
        }
        let digits = line[line.index(after: xIndex) ..< end]
        if let value = UInt64(digits, radix: 16) {
          values.append(value)
        }
        index = end
      }

      return values
    }
  }
#endif
