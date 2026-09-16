//
//  HistoryAuthenticator.swift
//  DiceGen
//

import LocalAuthentication

/// The outcomes the history feature can observe from system authentication.
enum HistoryAuthenticationResult: Equatable, Sendable {
    case success
    case cancelled
    case unavailable
    case failed
}

/// Abstracts LocalAuthentication so history flows can be tested without system UI.
protocol HistoryAuthenticating: Sendable {
    func authenticate(reason: String) async -> HistoryAuthenticationResult
}

/// The small portion of `LAContext` needed by the history authentication boundary.
protocol LocalAuthenticationEvaluating: Sendable {
    func canEvaluate(_ policy: LAPolicy) async -> Bool
    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool
}

/// Maps explicit device-owner authentication into stable history-domain outcomes.
struct LocalHistoryAuthenticator: HistoryAuthenticating {
    private let evaluator: any LocalAuthenticationEvaluating

    init(evaluator: any LocalAuthenticationEvaluating = LAContextEvaluator()) {
        self.evaluator = evaluator
    }

    func authenticate(reason: String) async -> HistoryAuthenticationResult {
        let policy = LAPolicy.deviceOwnerAuthentication
        guard await evaluator.canEvaluate(policy) else {
            return .unavailable
        }

        do {
            return try await evaluator.evaluate(policy, reason: reason) ? .success : .failed
        } catch let error as NSError where error.domain == LAError.errorDomain {
            switch LAError.Code(rawValue: error.code) {
            case .userCancel, .userFallback, .systemCancel:
                return .cancelled
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// Bridges a fresh `LAContext` to the injected evaluator protocol for each request.
struct LAContextEvaluator: LocalAuthenticationEvaluating {
    func canEvaluate(_ policy: LAPolicy) async -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(policy, error: &error)
    }

    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool {
        let context = LAContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
