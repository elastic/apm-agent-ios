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

#if !os(watchOS) // Crash reporting is not supported on watchOS.
  import PersistenceExporter
  import XCTest
  @testable import ElasticApm

  /// The NSException fixture is synthesized from the captured fatalError report.
  final class CrashReportExcerptTests: XCTestCase {
    func testFixtureResourcesResolve() {
      XCTAssertNotNil(fixtureURL("plcrash-ios-simulator-fatalerror"))
      XCTAssertNotNil(fixtureURL("plcrash-ios-simulator-nsexception"))
    }

    func testFatalErrorFixtureProducesPrioritizedExcerptWithinBudget() throws {
      let report = try fixture("plcrash-ios-simulator-fatalerror")
      let excerpt = CrashReportExcerpt.compose(report)

      XCTAssertLessThanOrEqual(excerpt.count, CrashReportExcerpt.maxCharacterCount)
      XCTAssertTrue(excerpt.hasPrefix(header(in: report)))
      XCTAssertEqual(thread(number: 0, in: excerpt), thread(number: 0, in: report))
      XCTAssertFalse(excerpt.contains(" Thread State:"))
      assertImageReferencesAreComplete(in: excerpt)
      assertSecondaryThreadsArePrefixAndNextDoesNotFit(report: report, excerpt: excerpt)
    }

    func testNSExceptionFixtureCapsReasonAndKeepsExceptionSections() throws {
      let report = try fixture("plcrash-ios-simulator-nsexception")
      let excerpt = CrashReportExcerpt.compose(report)

      XCTAssertLessThanOrEqual(excerpt.count, CrashReportExcerpt.maxCharacterCount)
      XCTAssertTrue(excerpt.contains("Application Specific Information:"))
      XCTAssertTrue(excerpt.contains("Last Exception Backtrace:"))
      XCTAssertTrue(excerpt.contains(String(repeating: "R", count: 1_000) + " [truncated]"))
      XCTAssertFalse(excerpt.contains(String(repeating: "R", count: 1_001)))
      XCTAssertFalse(excerpt.contains(" Thread State:"))
      assertImageReferencesAreComplete(in: excerpt)
    }

    func testMultilineReasonIsCapped() throws {
      let fixture = try fixture("plcrash-ios-simulator-nsexception")
      let reason = String(repeating: "R", count: 5_000)
      let multilineReason = Array(repeating: String(repeating: "R", count: 100), count: 50).joined(separator: "\n")
      let report = fixture.replacingOccurrences(of: reason, with: multilineReason)

      let excerpt = CrashReportExcerpt.compose(report)
      let information = section(startingWith: "Application Specific Information:", in: excerpt)

      XCTAssertTrue(information.hasSuffix(" [truncated]'"))
      XCTAssertLessThanOrEqual(information.filter { $0 == "R" }.count, 1_000)
      XCTAssertTrue(excerpt.contains("Thread 0 Crashed:"))
    }

    func testLongCrashedThreadKeepsHeadAndTenTailFrames() {
      // 512 is the per-thread frame cap of the crash reporter.
      for frameCount in [200, 512] {
        let report = syntheticReport(frameCount: frameCount)
        let excerpt = CrashReportExcerpt.compose(report)
        let lines = thread(number: 0, in: excerpt).split(separator: "\n").map(String.init)

        XCTAssertLessThanOrEqual(excerpt.count, CrashReportExcerpt.maxCharacterCount)
        let tailCount = assertShortened(section: thread(number: 0, in: excerpt), originalFrameCount: frameCount)
        XCTAssertEqual(tailCount, 10)
        XCTAssertTrue(lines.last?.hasPrefix("\(frameCount - 1) ") == true)
        assertImageReferencesAreComplete(in: excerpt)
      }
    }

    func testLongLastExceptionBacktraceIsShortenedAndCrashedThreadKept() throws {
      let fixture = try fixture("plcrash-ios-simulator-nsexception")
      let report = replacingFrames(of: "Last Exception Backtrace:", in: fixture, frameCount: 100)
      let excerpt = CrashReportExcerpt.compose(report)

      XCTAssertLessThanOrEqual(excerpt.count, CrashReportExcerpt.maxCharacterCount)
      assertShortened(section: section(startingWith: "Last Exception Backtrace:", in: excerpt), originalFrameCount: 100)
      XCTAssertTrue(excerpt.contains("Thread 0 Crashed:"))
      XCTAssertTrue(excerpt.contains(String(repeating: "R", count: 1_000) + " [truncated]"))
      XCTAssertFalse(excerpt.contains(String(repeating: "R", count: 1_001)))
      assertImageReferencesAreComplete(in: excerpt)
    }

    func testOverBudgetFallbackCutsParsedExcerpt() throws {
      let report = try fixture("plcrash-ios-simulator-nsexception")
      let unbounded = CrashReportExcerpt.compose(report, budget: .max)
      let truncatedReason = try XCTUnwrap(unbounded.range(of: " [truncated]"))
      // Too small for one frame per section, large enough to reach past the capped reason.
      let budget = unbounded.distance(from: unbounded.startIndex, to: truncatedReason.upperBound) + 20

      let excerpt = CrashReportExcerpt.compose(report, budget: budget)

      XCTAssertLessThanOrEqual(excerpt.count, budget)
      XCTAssertTrue(excerpt.contains(" [truncated]"))
      XCTAssertFalse(excerpt.contains(String(repeating: "R", count: 1_001)))
      XCTAssertFalse(excerpt.contains("Thread 0 Crashed:"))
    }

    func testFirstThreadIsFallbackWhenNoThreadIsMarkedCrashed() {
      let report = """
      Incident Identifier: fallback
      Exception Type: SIGABRT

      Thread 8:
      0   Demo                                0x0000000100000010 0x100000000 + 16

      Thread 9:
      0   Demo                                0x0000000100000020 0x100000000 + 32

      Binary Images:
             0x100000000 -        0x100000fff +Demo arm64 <UUID> /Demo
      """

      let excerpt = CrashReportExcerpt.compose(report, budget: 500)

      XCTAssertTrue(excerpt.contains("Thread 8:"))
      XCTAssertLessThanOrEqual(excerpt.count, 500)
    }

    func testReportWithoutThreadsReturnsNonEmptyPrefix() {
      let report = String(repeating: "Header line\n", count: 100)

      let excerpt = CrashReportExcerpt.compose(report, budget: 80)

      XCTAssertFalse(excerpt.isEmpty)
      XCTAssertEqual(excerpt.count, 80)
      XCTAssertEqual(excerpt, String(report.prefix(80)))
    }

    func testCompositionIsDeterministic() throws {
      let report = try fixture("plcrash-ios-simulator-fatalerror")

      XCTAssertEqual(
        CrashReportExcerpt.compose(report),
        CrashReportExcerpt.compose(report)
      )
    }

    func testBudgetStaysFarBelowPersistenceObjectLimit() throws {
      let preset = PersistencePerformancePreset.default
      let maxObjectSize = Mirror(reflecting: preset).children
        .first(where: { $0.label == "maxObjectSize" })?.value as? UInt64

      XCTAssertNotNil(maxObjectSize)
      XCTAssertLessThan(
        UInt64(CrashReportExcerpt.maxCharacterCount * 4),
        try XCTUnwrap(maxObjectSize)
      )
    }

    private func fixtureURL(_ name: String) -> URL? {
      Bundle.module.url(
        forResource: name,
        withExtension: "txt",
        subdirectory: "Fixtures"
      )
    }

    private func fixture(_ name: String) throws -> String {
      let url = try XCTUnwrap(fixtureURL(name))
      return try String(contentsOf: url, encoding: .utf8)
    }

    private func header(in report: String) -> String {
      report.components(separatedBy: "\nThread ").first ?? report
    }

    private func thread(number: Int, in report: String) -> String {
      let crashedMarker = "Thread \(number) Crashed:"
      let marker = report.contains(crashedMarker) ? crashedMarker : "Thread \(number):"
      return section(startingWith: marker, in: report)
    }

    /// Returns the section that starts with the marker line and ends before the next blank line.
    private func section(startingWith marker: String, in report: String) -> String {
      guard let start = report.range(of: "\(marker)\n") else {
        return ""
      }
      let remainder = report[start.lowerBound...]
      let end = remainder.range(of: "\n\n")?.lowerBound ?? remainder.endIndex
      return String(remainder[..<end])
    }

    /// Asserts a head of at least 20 frames, a tail of at most 10 that is full before the head grows past 20,
    /// and one marker accounting for the omitted frames. Returns the tail frame count.
    @discardableResult
    private func assertShortened(section: String,
                                 originalFrameCount: Int,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) -> Int? {
      let lines = section.split(separator: "\n").map(String.init)
      guard let markerIndex = lines.firstIndex(where: { $0.hasPrefix("... ") }) else {
        XCTFail("Expected an omitted-frames marker", file: file, line: line)
        return nil
      }
      let marker = lines[markerIndex].split(separator: " ")
      guard marker.count >= 2, let omitted = Int(marker[1]) else {
        XCTFail("Expected the marker to contain an omitted frame count", file: file, line: line)
        return nil
      }
      let headCount = markerIndex - 1
      let tailCount = lines.count - markerIndex - 1
      XCTAssertGreaterThanOrEqual(headCount, 20, file: file, line: line)
      XCTAssertLessThanOrEqual(tailCount, 10, file: file, line: line)
      XCTAssertTrue(headCount == 20 || tailCount == 10, file: file, line: line)
      XCTAssertEqual(headCount + omitted + tailCount, originalFrameCount, file: file, line: line)
      return tailCount
    }

    /// Replaces the frames of the section that starts with the marker by `frameCount` renumbered copies of them.
    private func replacingFrames(of marker: String, in report: String, frameCount: Int) -> String {
      let original = section(startingWith: marker, in: report)
      let frames = original.split(separator: "\n").dropFirst().map(String.init)
      let replacement = (0 ..< frameCount).map { index in
        String(format: "%-4ld", index) + frames[index % frames.count].dropFirst(4)
      }
      var result = report
      if let range = result.range(of: original) {
        result.replaceSubrange(range, with: ([marker] + replacement).joined(separator: "\n"))
      }
      return result
    }

    private func assertImageReferencesAreComplete(in report: String) {
      let lines = report.split(separator: "\n").map(String.init)
      let binaryIndex = lines.firstIndex(of: "Binary Images:") ?? lines.endIndex
      let frameBases = Set(lines[..<binaryIndex].compactMap { hexadecimalValues(in: $0).dropFirst().first }
        .filter { $0 != 0 })
      let imageStarts = Set(lines.dropFirst(binaryIndex + 1).compactMap { hexadecimalValues(in: $0).first })

      XCTAssertEqual(imageStarts, frameBases)
    }

    private func assertSecondaryThreadsArePrefixAndNextDoesNotFit(report: String,
                                                                  excerpt: String) {
      let reportThreads = threadNumbers(in: report).filter { $0 != 0 }
      let excerptThreads = threadNumbers(in: excerpt).filter { $0 != 0 }
      XCTAssertEqual(excerptThreads, Array(reportThreads.prefix(excerptThreads.count)))

      guard excerptThreads.count < reportThreads.count else {
        return
      }

      let nextNumber = reportThreads[excerptThreads.count]
      let nextThread = thread(number: nextNumber, in: report)
      let existingImages = imageLines(in: excerpt)
      let existingStarts = Set(existingImages.compactMap { hexadecimalValues(in: $0).first })
      let nextBases = Set(nextThread.split(separator: "\n").compactMap {
        hexadecimalValues(in: String($0)).dropFirst().first
      }.filter { $0 != 0 })
      let newImages = imageLines(in: report).filter {
        guard let start = hexadecimalValues(in: $0).first else {
          return false
        }
        return nextBases.contains(start) && !existingStarts.contains(start)
      }
      let candidateCount = excerpt.count
        + 2 + nextThread.count
        + newImages.reduce(0) { $0 + 1 + $1.count }

      XCTAssertGreaterThan(candidateCount, CrashReportExcerpt.maxCharacterCount)
    }

    private func threadNumbers(in report: String) -> [Int] {
      report.split(separator: "\n").compactMap { line in
        guard line.hasPrefix("Thread "), !line.contains(" Thread State:") else {
          return nil
        }
        return Int(line.dropFirst("Thread ".count).prefix(while: \.isNumber))
      }
    }

    private func imageLines(in report: String) -> [String] {
      guard let marker = report.range(of: "Binary Images:\n") else {
        return []
      }
      return report[marker.upperBound...].split(separator: "\n").map(String.init)
    }

    private func hexadecimalValues(in line: String) -> [UInt64] {
      line.split(whereSeparator: \.isWhitespace).compactMap { token in
        guard token.hasPrefix("0x") else {
          return nil
        }
        return UInt64(token.dropFirst(2), radix: 16)
      }
    }

    private func syntheticReport(frameCount: Int) -> String {
      let frames = (0 ..< frameCount).map { index in
        let address = String(format: "0x%016llx", 0x1_0000_0000 + UInt64(index * 16))
        return "\(index)   Demo                                \(address) 0x100000000 + \(index * 16)"
      }.joined(separator: "\n")

      return """
      Incident Identifier: synthetic
      Process: Demo
      Exception Type: SIGTRAP
      Exception Codes: TRAP_BRKPT at 0x100000000
      Crashed Thread:  0

      Thread 0 Crashed:
      \(frames)

      Thread 0 crashed with ARM-64 Thread State:
      x0: 0x0000000000000000

      Binary Images:
             0x100000000 -        0x100000fff +Demo arm64 <UUID> /Demo
      """
    }
  }
#else
  import XCTest

  final class CrashReportExcerptTests: XCTestCase {
    func testUnsupportedPlatformReportsSkip() throws {
      throw XCTSkip("Crash reporting is not supported on watchOS.")
    }
  }
#endif
