//
//  File.swift
//  
//
//  Created by Bryce Buchanan on 12/18/23.
//

import Foundation
import NetworkStatus

class NetworkStatusManager {
  static private var networkStatusKey = "co.elastic.network.status"
  public private(set) var lastStatus: String? {
    get {
      UserDefaults.standard.object(forKey: Self.networkStatusKey) as? String
    }
    set(value) {
      UserDefaults.standard.setValue(value, forKey: Self.networkStatusKey)
    }
  }

  private static var instance: NetworkStatus?

  private static func shared() -> NetworkStatus? {
    guard let existingInstance = instance else {
      do {
        Self.instance = try NetworkStatus()
        return Self.instance
      } catch {
        return nil
      }
    }
    return existingInstance
  }

  func status() -> String {
    guard let currentInstance = Self.shared() else {
      return "unavailable"
    }

    let status = currentInstance.status().0
    if status != lastStatus {
      lastStatus = status
    }
    return status
  }
}
