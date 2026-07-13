//
//  InAppReviewManager.swift
//  DiceGen
//

import Foundation

@MainActor
final class InAppReviewRequester {
    private enum Key {
        static let appLaunchCount = "appLaunchCount"
        static let passphraseCopyCount = "passphraseCopyCount"
        static let lastDateRequested = "lastDateRequested"
    }

    private let defaults: UserDefaults
    private let currentDate: () -> Date

    init(defaults: UserDefaults = .standard, currentDate: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.currentDate = currentDate
    }

    func recordAppLaunch(requestReview: () -> Void) {
        let launchCount = defaults.integer(forKey: Key.appLaunchCount) + 1
        defaults.set(launchCount, forKey: Key.appLaunchCount)

        let copyCount = defaults.integer(forKey: Key.passphraseCopyCount)
        let lastDateRequested = defaults.object(forKey: Key.lastDateRequested) as? Date ?? .distantPast
        let now = currentDate()
        guard launchCount > 2,
              copyCount > 2,
              now.timeIntervalSince(lastDateRequested) >= 30 * 86_400 else { return }

        defaults.set(now, forKey: Key.lastDateRequested)
        requestReview()
    }

    func recordPassphraseCopied() {
        let copyCount = defaults.integer(forKey: Key.passphraseCopyCount) + 1
        defaults.set(copyCount, forKey: Key.passphraseCopyCount)
    }
}
