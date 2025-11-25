//
//  Constants.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/5/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import UIKit

struct DiceGenConstants {

    static let tintColor = UIColor(red: 252.0 / 255.0, green: 33.0 / 255.0, blue: 37.0 / 255.0, alpha: 1.0)

    static var appName: String? { Bundle.main.infoDictionary?["CFBundleName"] as? String }

    static var appVersion: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    static var buildVersion: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

}
