//
//  InAppReviewManager.swift
//  DiceGen
//
//  Created by Daniel Byon on 4/3/20.
//  Copyright © 2020 Daniel Byon. All rights reserved.
//

import Foundation
import StoreKit

struct InAppReviewManager {

    @UserDefault(key: "appLaunchCount", defaultValue: 0)
    private static var appLaunchCount: Int

    @UserDefault(key: "passphraseCopyCount", defaultValue: 0)
    private static var passphraseCopyCount: Int

    @UserDefault(key: "lastDateRequested", defaultValue: .distantPast)
    private static var lastDateRequested: Date

    private init() { }

    static func recordAppLaunch() {
        appLaunchCount += 1
        requestAppReviewIfNecessary()
    }

    static func recordPassphraseCopied() {
        passphraseCopyCount += 1
        requestAppReviewIfNecessary()
    }

    private static func requestAppReviewIfNecessary() {
        guard appLaunchCount > 2,
            passphraseCopyCount > 2,
            Date().timeIntervalSince(lastDateRequested) >= (30 * 86_400) else { return }
        lastDateRequested = Date()
        SKStoreReviewController.requestReview()
    }

}
