//
//  ActivityStack.swift
//
//
//  Created by Alexander Wert on 7/13/22.
//

import Foundation
import os.activity

struct ActivityStack {

    private var items: [AnyObject] = []

    func peek() -> AnyObject {
        guard let topElement = items.first else { fatalError("This stack is empty.") }
        return topElement
    }

    mutating func pop() -> AnyObject {
        return items.removeFirst()
    }

    mutating func push(_ element: AnyObject) {
        items.insert(element, at: 0)
    }

    mutating func remove(_ element: AnyObject) {
        items.removeAll(where: {$0 === element})
    }
}
