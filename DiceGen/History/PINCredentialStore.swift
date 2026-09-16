//
//  PINCredentialStore.swift
//  DiceGen
//

import CryptoKit
import Foundation
import Security

/// The format and work factor used by the current DiceGen PIN verifier.
struct PINVerifierParameters: Codable, Equatable, Sendable {
    let version: Int
    let iterations: Int
    let saltByteCount: Int
    let verifierByteCount: Int

    static let v1 = PINVerifierParameters(
        version: 1,
        iterations: 600_000,
        saltByteCount: 16,
        verifierByteCount: 32
    )
}

/// The versioned, salted verifier record stored as the Keychain item value.
struct PINVerifierRecord: Codable, Equatable, Sendable {
    let version: Int
    let iterations: Int
    let salt: Data
    let verifier: Data
}

/// Errors raised while creating or reading the protected PIN credential.
enum PINCredentialStoreError: Error, Equatable {
    case invalidPIN
    case invalidParameters
    case randomGenerationFailed(OSStatus)
    case encodingFailed
    case invalidRecord
    case unsupportedVersion(Int)
    case keychain(OSStatus)
}

/// Validates the app-specific PIN policy without normalizing user input.
enum HistoryPINPolicy {
    static func isValid(_ pin: String) -> Bool {
        guard (4...12).contains(pin.count) else { return false }
        return pin.unicodeScalars.allSatisfy { (48...57).contains(Int($0.value)) }
    }
}

/// Performs the approved PBKDF2-HMAC-SHA256 derivation off the main actor.
enum PBKDF2SHA256 {
    static func derive(
        password: Data,
        salt: Data,
        iterations: Int,
        outputByteCount: Int
    ) throws -> Data {
        guard iterations > 0, (1...SHA256.Digest.byteCount).contains(outputByteCount) else {
            throw PINCredentialStoreError.invalidParameters
        }

        let key = SymmetricKey(data: password)
        var blockInput = salt
        blockInput.append(contentsOf: [0, 0, 0, 1])

        var previous = Data(HMAC<SHA256>.authenticationCode(for: blockInput, using: key))
        var result = previous
        if iterations > 1 {
            for _ in 1..<iterations {
                previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: key))
                for index in result.indices {
                    result[index] ^= previous[index]
                }
            }
        }
        return Data(result.prefix(outputByteCount))
    }
}

/// Asynchronous boundary for the device-local PIN verifier.
protocol PINCredentialStoring: Sendable {
    func hasCredential() async throws -> Bool
    func setPIN(_ pin: String) async throws
    func verifyPIN(_ pin: String) async throws -> Bool
    func deleteCredential() async throws
}

/// Stores only a versioned PBKDF2 verifier in a non-synchronizing Keychain item.
actor KeychainPINCredentialStore: PINCredentialStoring {
    private let service: String
    private let account: String
    private let parameters: PINVerifierParameters

    init(
        service: String = "\(Bundle.main.bundleIdentifier ?? "DiceGen").history",
        account: String = "history-pin",
        parameters: PINVerifierParameters = .v1
    ) {
        self.service = service
        self.account = account
        self.parameters = parameters
    }

    func hasCredential() async throws -> Bool {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw PINCredentialStoreError.keychain(status)
        }
    }

    func setPIN(_ pin: String) async throws {
        guard HistoryPINPolicy.isValid(pin) else {
            throw PINCredentialStoreError.invalidPIN
        }
        guard parameters.version == PINVerifierParameters.v1.version,
              parameters.iterations > 0,
              parameters.saltByteCount == PINVerifierParameters.v1.saltByteCount,
              parameters.verifierByteCount == PINVerifierParameters.v1.verifierByteCount else {
            throw PINCredentialStoreError.invalidParameters
        }

        var salt = Data(repeating: 0, count: parameters.saltByteCount)
        let randomStatus = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw PINCredentialStoreError.randomGenerationFailed(randomStatus)
        }

        let verifier = try PBKDF2SHA256.derive(
            password: Data(pin.utf8),
            salt: salt,
            iterations: parameters.iterations,
            outputByteCount: parameters.verifierByteCount
        )
        let record = PINVerifierRecord(
            version: parameters.version,
            iterations: parameters.iterations,
            salt: salt,
            verifier: verifier
        )
        let recordData: Data
        do {
            recordData = try JSONEncoder().encode(record)
        } catch {
            throw PINCredentialStoreError.encodingFailed
        }

        var updateAttributes: [String: Any] = [
            kSecValueData as String: recordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        var status = SecItemUpdate(baseQuery() as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            updateAttributes[kSecClass as String] = kSecClassGenericPassword
            updateAttributes[kSecAttrService as String] = service
            updateAttributes[kSecAttrAccount as String] = account
            status = SecItemAdd(updateAttributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw PINCredentialStoreError.keychain(status)
        }
    }

    func verifyPIN(_ pin: String) async throws -> Bool {
        guard HistoryPINPolicy.isValid(pin) else { return false }

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecItemNotFound:
            return false
        case errSecSuccess:
            break
        default:
            throw PINCredentialStoreError.keychain(status)
        }

        guard let recordData = result as? Data else {
            throw PINCredentialStoreError.invalidRecord
        }
        let record: PINVerifierRecord
        do {
            record = try JSONDecoder().decode(PINVerifierRecord.self, from: recordData)
        } catch {
            throw PINCredentialStoreError.invalidRecord
        }
        guard record.version == PINVerifierParameters.v1.version else {
            throw PINCredentialStoreError.unsupportedVersion(record.version)
        }
        guard record.iterations > 0,
              record.salt.count == PINVerifierParameters.v1.saltByteCount,
              record.verifier.count == PINVerifierParameters.v1.verifierByteCount else {
            throw PINCredentialStoreError.invalidRecord
        }

        let candidate = try PBKDF2SHA256.derive(
            password: Data(pin.utf8),
            salt: record.salt,
            iterations: record.iterations,
            outputByteCount: record.verifier.count
        )
        return constantTimeEqual(candidate, record.verifier)
    }

    func deleteCredential() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PINCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { result, pair in
            result | (pair.0 ^ pair.1)
        } == 0
    }
}
