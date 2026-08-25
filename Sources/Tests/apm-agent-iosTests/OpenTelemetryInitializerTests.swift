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

final class OpenTelemetryInitializerTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testCreatesSeparateDirectoryForEachSignal() throws {
    let paths = try OpenTelemetryInitializer.PersistenceSignal.allCases.map { signal in
      try XCTUnwrap(
        OpenTelemetryInitializer.createPersistenceFolder(
          for: signal, baseDirectory: temporaryDirectory))
    }

    XCTAssertEqual(Set(paths).count, 3)
    XCTAssertEqual(
      Set(paths.map(\.lastPathComponent)),
      Set(["logs", "traces", "metrics"]))

    for path in paths {
      var isDirectory: ObjCBool = false
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: path.path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue)
    }
  }

  func testRemovesLegacyFilesAndPreservesNestedDirectories() throws {
    let legacyFile = temporaryDirectory.appendingPathComponent("807190670176")
    let nestedDirectory = temporaryDirectory.appendingPathComponent(
      "existing-signal", isDirectory: true)
    let nestedFile = nestedDirectory.appendingPathComponent("batch")
    try Data("legacy".utf8).write(to: legacyFile)
    try FileManager.default.createDirectory(
      at: nestedDirectory, withIntermediateDirectories: true)
    try Data("nested".utf8).write(to: nestedFile)

    XCTAssertNotNil(
      OpenTelemetryInitializer.createPersistenceFolder(
        for: .logs, baseDirectory: temporaryDirectory))

    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyFile.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
  }

  func testCleanupFailureDoesNotDisableIsolatedStorage() throws {
    let logsDirectory = temporaryDirectory.appendingPathComponent(
      "logs", isDirectory: true)
    let legacyFile = temporaryDirectory.appendingPathComponent("807190670176")
    try FileManager.default.createDirectory(
      at: logsDirectory, withIntermediateDirectories: true)
    try Data("legacy".utf8).write(to: legacyFile)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: temporaryDirectory.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
    }

    let result = OpenTelemetryInitializer.createPersistenceFolder(
      for: .logs, baseDirectory: temporaryDirectory)

    XCTAssertEqual(result, logsDirectory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path))
  }
}
