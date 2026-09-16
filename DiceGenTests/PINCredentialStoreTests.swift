//
//  PINCredentialStoreTests.swift
//  DiceGenTests
//

import Foundation
import Security
import XCTest
@testable import DiceGen

@MainActor
final class PINCredentialStoreTests: XCTestCase {
    func testPINPolicyAcceptsOnlyASCII4To12DigitValues() {
        XCTAssertFalse(HistoryPINPolicy.isValid(String(repeating: "7", count: 3)))
        XCTAssertTrue(HistoryPINPolicy.isValid(String(repeating: "7", count: 4)))
        XCTAssertTrue(HistoryPINPolicy.isValid(String(repeating: "7", count: 12)))
        XCTAssertFalse(HistoryPINPolicy.isValid(String(repeating: "7", count: 13)))
        XCTAssertFalse(HistoryPINPolicy.isValid("12a4"))
        XCTAssertFalse(HistoryPINPolicy.isValid("１２３４"))
    }

    func testProductionVerifierParametersUseApprovedVersionOneValues() {
        XCTAssertEqual(PINVerifierParameters.v1.version, 1)
        XCTAssertEqual(PINVerifierParameters.v1.iterations, 600_000)
        XCTAssertEqual(PINVerifierParameters.v1.saltByteCount, 16)
        XCTAssertEqual(PINVerifierParameters.v1.verifierByteCount, 32)
    }

    func testPBKDF2SHA256MatchesStandardOneIterationVector() throws {
        let password = Data([0x70, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64])
        let salt = Data([0x73, 0x61, 0x6c, 0x74])
        let expected = Data([
            0x12, 0x0f, 0xb6, 0xcf, 0xfc, 0xf8, 0xb3, 0x2c,
            0x43, 0xe7, 0x22, 0x52, 0x56, 0xc4, 0xf8, 0x37,
            0xa8, 0x65, 0x48, 0xc9, 0x2c, 0xcc, 0x35, 0x48,
            0x08, 0x05, 0x98, 0x7c, 0xb7, 0x0b, 0xe1, 0x7b
        ])

        XCTAssertEqual(
            try PBKDF2SHA256.derive(password: password, salt: salt, iterations: 1, outputByteCount: 32),
            expected
        )
    }

    func testPBKDF2RejectsUnsupportedIterationAndOutputValues() {
        XCTAssertThrowsError(
            try PBKDF2SHA256.derive(password: Data(), salt: Data(), iterations: 0, outputByteCount: 32)
        )
        XCTAssertThrowsError(
            try PBKDF2SHA256.derive(password: Data(), salt: Data(), iterations: 1, outputByteCount: 0)
        )
        XCTAssertThrowsError(
            try PBKDF2SHA256.derive(password: Data(), salt: Data(), iterations: 1, outputByteCount: 33)
        )
    }

    func testKeychainStorePersistsVerifierWithoutPlaintextPIN() async throws {
        let service = "DiceGenTests.\(UUID().uuidString)"
        let account = "history-pin"
        let parameters = PINVerifierParameters(version: 1, iterations: 2, saltByteCount: 16, verifierByteCount: 32)
        let store = KeychainPINCredentialStore(service: service, account: account, parameters: parameters)
        let pin = String(repeating: "7", count: 4)

        let initiallyHasCredential = try await store.hasCredential()
        XCTAssertFalse(initiallyHasCredential)
        try await store.setPIN(pin)
        let hasCredentialAfterSet = try await store.hasCredential()
        let acceptsCorrectPIN = try await store.verifyPIN(pin)
        let acceptsIncorrectPIN = try await store.verifyPIN(String(repeating: "8", count: 4))
        XCTAssertTrue(hasCredentialAfterSet)
        XCTAssertTrue(acceptsCorrectPIN)
        XCTAssertFalse(acceptsIncorrectPIN)

        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let recordData = try XCTUnwrap(result as? Data)
        XCTAssertNil(recordData.range(of: Data(pin.utf8)))

        try await store.deleteCredential()
        let hasCredentialAfterDelete = try await store.hasCredential()
        XCTAssertFalse(hasCredentialAfterDelete)
        try await store.deleteCredential()
    }

    func testKeychainStoreRejectsInvalidPINWithoutCreatingCredential() async throws {
        let service = "DiceGenTests.\(UUID().uuidString)"
        let store = KeychainPINCredentialStore(service: service, account: "history-pin")

        do {
            try await store.setPIN(String(repeating: "7", count: 3))
            XCTFail("An invalid PIN must not be persisted")
        } catch let error as PINCredentialStoreError {
            XCTAssertEqual(error, .invalidPIN)
        }
        let hasCredentialAfterRejectedPIN = try await store.hasCredential()
        XCTAssertFalse(hasCredentialAfterRejectedPIN)
    }
}
