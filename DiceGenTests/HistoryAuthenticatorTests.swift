//
//  HistoryAuthenticatorTests.swift
//  DiceGenTests
//

import Foundation
import LocalAuthentication
import XCTest
@testable import DiceGen

@MainActor
final class HistoryAuthenticatorTests: XCTestCase {
    func testSuccessfulAuthenticationUsesDeviceOwnerPolicyAndReason() async {
        let evaluator = EvaluatorSpy(canEvaluateResult: true, outcome: .success)
        let authenticator = LocalHistoryAuthenticator(evaluator: evaluator)

        let result = await authenticator.authenticate(reason: "Unlock private history")
        let snapshot = await evaluator.snapshot()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(snapshot.policies, [.deviceOwnerAuthentication, .deviceOwnerAuthentication])
        XCTAssertEqual(snapshot.reasons, ["Unlock private history"])
    }

    func testUnavailableDeviceDoesNotAttemptEvaluation() async {
        let evaluator = EvaluatorSpy(canEvaluateResult: false, outcome: .success)
        let authenticator = LocalHistoryAuthenticator(evaluator: evaluator)

        let result = await authenticator.authenticate(reason: "Unlock private history")
        let snapshot = await evaluator.snapshot()

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(snapshot.policies, [.deviceOwnerAuthentication])
        XCTAssertTrue(snapshot.reasons.isEmpty)
    }

    func testSuccessfulEvaluationMapsToSuccess() async {
        let evaluator = EvaluatorSpy(canEvaluateResult: true, outcome: .success)
        let authenticator = LocalHistoryAuthenticator(evaluator: evaluator)

        let result = await authenticator.authenticate(reason: "Reason")
        XCTAssertEqual(result, .success)
    }

    func testFalseEvaluationAndGenericFailureMapToFailed() async {
        let falseEvaluator = EvaluatorSpy(canEvaluateResult: true, outcome: .returnsFalse)
        let falseAuthenticator = LocalHistoryAuthenticator(evaluator: falseEvaluator)
        let falseResult = await falseAuthenticator.authenticate(reason: "Reason")
        XCTAssertEqual(falseResult, .failed)

        let genericEvaluator = EvaluatorSpy(canEvaluateResult: true, outcome: .throwsGeneric)
        let genericAuthenticator = LocalHistoryAuthenticator(evaluator: genericEvaluator)
        let genericResult = await genericAuthenticator.authenticate(reason: "Reason")
        XCTAssertEqual(genericResult, .failed)
    }

    func testUserAndSystemCancellationFailuresMapToCancelled() async {
        let cancellationCodes = [
            LAError.Code.userCancel.rawValue,
            LAError.Code.userFallback.rawValue,
            LAError.Code.systemCancel.rawValue
        ]

        for code in cancellationCodes {
            let evaluator = EvaluatorSpy(canEvaluateResult: true, outcome: .throwsLAError(code))
            let authenticator = LocalHistoryAuthenticator(evaluator: evaluator)

            let result = await authenticator.authenticate(reason: "Reason")
            XCTAssertEqual(result, .cancelled)
        }
    }
}

private actor EvaluatorSpy: LocalAuthenticationEvaluating {
    enum Outcome: Sendable {
        case success
        case returnsFalse
        case throwsLAError(Int)
        case throwsGeneric
    }

    private let canEvaluateResult: Bool
    private let outcome: Outcome
    private var policies: [LAPolicy] = []
    private var reasons: [String] = []

    init(canEvaluateResult: Bool, outcome: Outcome) {
        self.canEvaluateResult = canEvaluateResult
        self.outcome = outcome
    }

    func canEvaluate(_ policy: LAPolicy) async -> Bool {
        policies.append(policy)
        return canEvaluateResult
    }

    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool {
        policies.append(policy)
        reasons.append(reason)
        switch outcome {
        case .success:
            return true
        case .returnsFalse:
            return false
        case let .throwsLAError(code):
            throw NSError(domain: LAError.errorDomain, code: code)
        case .throwsGeneric:
            throw SpyError.generic
        }
    }

    func snapshot() -> (policies: [LAPolicy], reasons: [String]) {
        (policies, reasons)
    }
}

private enum SpyError: Error, Sendable {
    case generic
}
