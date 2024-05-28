//
//  File.swift
//  
//
//  Created by Bryce Buchanan on 5/28/24.
//

import Foundation
import OpenTelemetryApi

public struct LogRecordData {
  public let attributes : [String: AttributeValue]
  public let body: AttributeValue?
  public let instrumentationScopeName : String
  public let instrumentationScopeVersion : String?
  public let timestamp : Date
  public let observedTimestamp :  Date?
  public let spanContext : SpanContext?
  public let severity : Severity?
}
