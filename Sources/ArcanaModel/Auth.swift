//
//  Security.swift
//  ArcanaModel — auth primitives: PBKDF2 password hashing (CommonCrypto, keeping the C#
//  `version:iterations:salt:hash` format), HMAC-signed local tokens (CryptoKit), Keychain
//  storage for the signing key, and the observable current-user session.
//

import Foundation
import CommonCrypto
import CryptoKit
import Security

// MARK: - Password hashing (PBKDF2-SHA256, OWASP iterations)

public struct PasswordHasher: Sendable {
    public static let version = 1
    public static let iterations = 100_000
    private static let saltLength = 16
    private static let hashLength = 32

    public init() {}

    /// Hashes a password → `version:iterations:base64(salt):base64(hash)`.
    public func hash(_ password: String) -> String {
        var salt = [UInt8](repeating: 0, count: Self.saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let derived = Self.pbkdf2(Array(password.utf8), salt: salt, iterations: Self.iterations, length: Self.hashLength)
        return "\(Self.version):\(Self.iterations):\(Data(salt).base64EncodedString()):\(Data(derived).base64EncodedString())"
    }

    /// Verifies a password against a stored hash (constant-time compare).
    public func verify(_ password: String, hash: String) -> Bool {
        let parts = hash.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, let iterations = Int(parts[1]),
              let salt = Data(base64Encoded: parts[2]),
              let expected = Data(base64Encoded: parts[3]) else { return false }
        let derived = Self.pbkdf2(Array(password.utf8), salt: [UInt8](salt), iterations: iterations, length: expected.count)
        return Self.constantTimeEquals(Data(derived), expected)
    }

    /// Whether the stored hash should be re-computed (bad format, older version, fewer iterations).
    public func needsRehash(_ hash: String) -> Bool {
        let parts = hash.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, let version = Int(parts[0]), let iterations = Int(parts[1]) else { return true }
        return version < Self.version || iterations < Self.iterations
    }

    private static func pbkdf2(_ password: [UInt8], salt: [UInt8], iterations: Int, length: Int) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: length)
        derived.withUnsafeMutableBufferPointer { dPtr in
            password.withUnsafeBufferPointer { pPtr in
                salt.withUnsafeBufferPointer { sPtr in
                    _ = pPtr.baseAddress!.withMemoryRebound(to: CChar.self, capacity: password.count) { pw in
                        CCKeyDerivationPBKDF(
                            CCPBKDFAlgorithm(kCCPBKDF2),
                            pw, password.count,
                            sPtr.baseAddress, salt.count,
                            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            UInt32(iterations),
                            dPtr.baseAddress, length)
                    }
                }
            }
        }
        return derived
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

// MARK: - Local HMAC token service

public struct TokenValidation: Sendable, Equatable {
    public let isValid: Bool
    public let userId: Int?
    public let username: String?
    public let failureReason: String?
    public let isExpired: Bool

    public init(isValid: Bool, userId: Int? = nil, username: String? = nil,
                failureReason: String? = nil, isExpired: Bool = false) {
        self.isValid = isValid
        self.userId = userId
        self.username = username
        self.failureReason = failureReason
        self.isExpired = isExpired
    }
}

/// Locally-signed (not server-issued) access tokens: `base64(payload).base64(HMAC-SHA256)`.
public struct TokenService: Sendable {
    private let key: SymmetricKey
    public let accessLifetime: TimeInterval

    public init(key: SymmetricKey, accessLifetime: TimeInterval = 3600) {
        self.key = key
        self.accessLifetime = accessLifetime
    }

    public func generateAccessToken(userId: Int, username: String, now: Date = Date()) -> (token: String, expiresAt: Date) {
        let expires = now.addingTimeInterval(accessLifetime)
        let payload = "\(userId)|\(username)|\(Int(expires.timeIntervalSince1970))|\(Int(now.timeIntervalSince1970))"
        let payloadB64 = Data(payload.utf8).base64EncodedString()
        return ("\(payloadB64).\(sign(payloadB64))", expires)
    }

    public func validate(_ token: String, now: Date = Date()) -> TokenValidation {
        let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return TokenValidation(isValid: false, failureReason: "malformed") }
        guard constantTimeEquals(parts[1], sign(parts[0])) else {
            return TokenValidation(isValid: false, failureReason: "bad signature")
        }
        guard let data = Data(base64Encoded: parts[0]), let payload = String(data: data, encoding: .utf8) else {
            return TokenValidation(isValid: false, failureReason: "bad payload")
        }
        let fields = payload.split(separator: "|").map(String.init)
        guard fields.count == 4, let userId = Int(fields[0]), let expiry = Int(fields[2]) else {
            return TokenValidation(isValid: false, failureReason: "bad payload")
        }
        if Date(timeIntervalSince1970: Double(expiry)) < now {
            return TokenValidation(isValid: false, userId: userId, username: fields[1], failureReason: "expired", isExpired: true)
        }
        return TokenValidation(isValid: true, userId: userId, username: fields[1])
    }

    public static func generateRefreshToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func sign(_ message: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for the token signing key (macOS `kSecClassGenericPassword`).
public enum Keychain {
    public static let service = "boo.arcana.macos"

    public static func read(_ account: String, service: String = service) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    public static func write(_ data: Data, account: String, service: String = service) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// The token signing key, created on first use and persisted to the Keychain.
    public static func signingKey() -> SymmetricKey {
        if let data = read("token-signing-key") { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        write(data, account: "token-signing-key")
        return key
    }
}

// MARK: - Current user session

/// The authenticated user with pre-flattened roles + permissions (built at login).
public struct AuthenticatedUser: Sendable, Equatable {
    public let id: Int
    public let username: String
    public let displayName: String
    public let email: String?
    public let roles: [String]
    public let permissions: Set<String>

    public init(id: Int, username: String, displayName: String, email: String? = nil,
                roles: [String] = [], permissions: Set<String> = []) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.roles = roles
        self.permissions = permissions
    }
}

/// App-wide session the UI binds to for permission gating.
@MainActor
@Observable
public final class CurrentUserService {
    public private(set) var currentUser: AuthenticatedUser?

    public init() {}

    public var isAuthenticated: Bool { currentUser != nil }
    public var userId: Int? { currentUser?.id }
    public var username: String? { currentUser?.username }

    public func setCurrentUser(_ user: AuthenticatedUser) { currentUser = user }
    public func clearCurrentUser() { currentUser = nil }

    public func hasPermission(_ permission: String) -> Bool {
        currentUser?.permissions.contains(permission) ?? false
    }
    public func hasAnyPermission(_ permissions: [String]) -> Bool {
        guard let current = currentUser else { return false }
        return permissions.contains { current.permissions.contains($0) }
    }
    public func isInRole(_ role: String) -> Bool {
        currentUser?.roles.contains { $0.caseInsensitiveCompare(role) == .orderedSame } ?? false
    }
}
