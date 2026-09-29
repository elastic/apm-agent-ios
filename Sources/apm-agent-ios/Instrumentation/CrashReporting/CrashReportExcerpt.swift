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

      let fixedSections = parsed.fixedSections
      let fixedReferences = frameReferences(in: fixedSections)
      var keptThreads = [parsed.crashedThread]
      var references = fixedReferences.union(parsed.crashedThread.frameReferences)

      var excerpt = render(
        fixedSections: fixedSections,
        threads: keptThreads,
        imageReferences: references,
        images: parsed.images,
        hasBinaryImagesSection: parsed.hasBinaryImagesSection
      )

      if excerpt.count > budget {
        guard let truncated = truncateCrashedThread(
          parsed.crashedThread,
          fixedSections: fixedSections,
          fixedReferences: fixedReferences,
          images: parsed.images,
          hasBinaryImagesSection: parsed.hasBinaryImagesSection,
          budget: budget
        ) else {
          return String(normalized.prefix(budget))
        }

        keptThreads = [truncated.thread]
        references = fixedReferences.union(truncated.thread.frameReferences)
        excerpt = render(
          fixedSections: fixedSections,
          threads: keptThreads,
          imageReferences: references,
          images: parsed.images,
          hasBinaryImagesSection: parsed.hasBinaryImagesSection
        )
      }

      for thread in parsed.secondaryThreads {
        let candidateThreads = keptThreads + [thread]
        let candidateReferences = references.union(thread.frameReferences)
        let candidate = render(
          fixedSections: fixedSections,
          threads: candidateThreads,
          imageReferences: candidateReferences,
          images: parsed.images,
          hasBinaryImagesSection: parsed.hasBinaryImagesSection
        )
        guard candidate.count <= budget else {
          break
        }
        keptThreads = candidateThreads
        references = candidateReferences
        excerpt = candidate
      }

      return String(excerpt.prefix(budget))
    }

    private static func truncateCrashedThread(_ thread: ThreadSection,
                                              fixedSections: [[String]],
                                              fixedReferences: Set<UInt64>,
                                              images: [ImageLine],
                                              hasBinaryImagesSection: Bool,
                                              budget: Int) -> (thread: ThreadSection, excerpt: String)? {
      let frames = thread.frames
      guard frames.count > 1 else {
        return nil
      }

      let preferredTailCount = min(10, frames.count - 1)
      let minimumHeadCount = min(20, frames.count - preferredTailCount - 1)

      for tailCount in stride(from: preferredTailCount, through: 0, by: -1) {
        let maximumHeadCount = frames.count - tailCount - 1
        guard maximumHeadCount > 0 else {
          continue
        }

        let lowestHeadCount = tailCount == preferredTailCount ? minimumHeadCount : 1
        guard maximumHeadCount >= lowestHeadCount else {
          continue
        }

        for headCount in stride(from: maximumHeadCount, through: lowestHeadCount, by: -1) {
          let omittedCount = frames.count - headCount - tailCount
          guard omittedCount > 0 else {
            continue
          }

          let shortened = thread.replacingFrames(
            headCount: headCount,
            tailCount: tailCount,
            omittedCount: omittedCount
          )
          let references = fixedReferences.union(shortened.frameReferences)
          let excerpt = render(
            fixedSections: fixedSections,
            threads: [shortened],
            imageReferences: references,
            images: images,
            hasBinaryImagesSection: hasBinaryImagesSection
          )
          if excerpt.count <= budget {
            return (shortened, excerpt)
          }
        }
      }

      return nil
    }

    private static func render(fixedSections: [[String]],
                               threads: [ThreadSection],
                               imageReferences: Set<UInt64>,
                               images: [ImageLine],
                               hasBinaryImagesSection: Bool) -> String {
      var sections = fixedSections
      sections.append(contentsOf: threads.map(\.lines))

      if hasBinaryImagesSection {
        let keptImages = images
          .filter { imageReferences.contains($0.startAddress) }
          .map(\.line)
        sections.append(["Binary Images:"] + keptImages)
      }

      return sections
        .filter { !$0.isEmpty }
        .map { $0.joined(separator: "\n") }
        .joined(separator: "\n\n") + "\n"
    }

    private static func frameReferences(in sections: [[String]]) -> Set<UInt64> {
      Set(sections.flatMap { section in
        section.compactMap(Frame.init(line:)).compactMap(\.baseAddress)
      })
    }
  }

  private extension CrashReportExcerpt {
    struct ParsedReport {
      let header: [String]
      let applicationInformation: [String]?
      let lastExceptionBacktrace: [String]?
      let crashedThread: ThreadSection
      let secondaryThreads: [ThreadSection]
      let images: [ImageLine]
      let hasBinaryImagesSection: Bool

      var fixedSections: [[String]] {
        [header, applicationInformation, lastExceptionBacktrace].compactMap { $0 }
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
          if let thread = ThreadSection.header(line) {
            return Marker(index: index, kind: .thread(thread))
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
        var lastExceptionBacktrace: [String]?
        var threads = [ThreadSection]()
        var images = [ImageLine]()
        var hasBinaryImagesSection = false

        for (position, marker) in markers.enumerated() {
          let end = position + 1 < markers.count ? markers[position + 1].index : lines.count
          var section = Self.trimmed(Array(lines[marker.index ..< end]))

          switch marker.kind {
          case .applicationInformation:
            section = section.map(Self.truncatingApplicationReason)
            applicationInformation = section
          case .lastExceptionBacktrace:
            lastExceptionBacktrace = section
          case let .thread(header):
            threads.append(ThreadSection(header: header, lines: section))
          case .registerState:
            break
          case .binaryImages:
            hasBinaryImagesSection = true
            images = section.dropFirst().compactMap(ImageLine.init(line:))
          }
        }

        guard !threads.isEmpty else {
          return nil
        }

        let crashedIndex = threads.firstIndex(where: \.isCrashed) ?? threads.startIndex
        crashedThread = threads[crashedIndex]
        secondaryThreads = threads.enumerated().compactMap { index, thread in
          index == crashedIndex ? nil : thread
        }
        self.applicationInformation = applicationInformation
        self.lastExceptionBacktrace = lastExceptionBacktrace
        self.images = images
        self.hasBinaryImagesSection = hasBinaryImagesSection
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
        case thread(ThreadSection.Header)
        case registerState
        case binaryImages
      }

      let index: Int
      let kind: Kind
    }

    struct ThreadSection {
      struct Header {
        let number: Int
        let isCrashed: Bool
      }

      let header: Header
      let lines: [String]

      var isCrashed: Bool {
        header.isCrashed
      }

      var frames: [Frame] {
        lines.dropFirst().compactMap(Frame.init(line:))
      }

      var frameReferences: Set<UInt64> {
        Set(frames.compactMap(\.baseAddress))
      }

      static func header(_ line: String) -> Header? {
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
        guard numberStart < numberEnd, let number = Int(line[numberStart ..< numberEnd]) else {
          return nil
        }
        return Header(number: number, isCrashed: isCrashed)
      }

      func replacingFrames(headCount: Int, tailCount: Int, omittedCount: Int) -> ThreadSection {
        let keptHead = frames.prefix(headCount).map(\.line)
        let keptTail = tailCount == 0 ? [] : frames.suffix(tailCount).map(\.line)
        let marker = "... \(omittedCount) frames omitted"
        return ThreadSection(
          header: header,
          lines: [lines[0]] + keptHead + [marker] + keptTail
        )
      }
    }

    struct Frame {
      let line: String
      let imageName: String
      let baseAddress: UInt64?

      init?(line: String) {
        let addresses = hexadecimalValues(in: line)
        guard addresses.count >= 2 else {
          return nil
        }

        self.line = line
        baseAddress = addresses[1] == 0 ? nil : addresses[1]

        let components = line.split(whereSeparator: \.isWhitespace)
        guard components.count >= 2, Int(components[0]) != nil else {
          return nil
        }
        imageName = String(components[1])
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
