//
//  UserDefault.swift
//  DiceGen
//
//  Created by Daniel Byon on 3/30/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation

@propertyWrapper
public struct UserDefault<T> {

    public let key: String
    public let defaultValue: T

    public var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
 
    public init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

}
