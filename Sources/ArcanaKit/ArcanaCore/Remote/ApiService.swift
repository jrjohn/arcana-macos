//
//  ApiService.swift
//  arcana-ios
//
//  Created by John on 2025/11/15.
//

import Foundation
import Alamofire

/// API Service for RESTful operations using Alamofire
/// Connects to reqres.in API for user management
actor ApiService {
    
    // MARK: - Properties

    private let baseURL: String
    private let session: Session
    private let config: AppConfiguration

    // MARK: - Initialization

    init(baseURL: String? = nil, config: AppConfiguration = .shared) {
        self.config = config
        self.baseURL = baseURL ?? config.apiBaseURL

        // Configure session with interceptors and retry policy
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.apiTimeout
        configuration.timeoutIntervalForResource = config.apiTimeout

        let interceptor = ApiInterceptor(config: config)

        // Create network logger
        let loggerConfig = NetworkLoggerConfiguration(from: config)
        let logger = NetworkLogger(configuration: loggerConfig)

        self.session = Session(
            configuration: configuration,
            interceptor: interceptor,
            eventMonitors: [logger]
        )
    }
    
    // MARK: - Request Parameters

    // Typed, `Sendable` request parameters. Under Swift 6 strict concurrency the actor
    // can't hand a `[String: Any]` dictionary to Alamofire (its `Any` values aren't
    // `Sendable`), so each request body/query is an `Encodable & Sendable` struct fed to
    // the `Encodable`-based `request(_:parameters:encoder:)` overload.

    private struct UsersQuery: Encodable, Sendable {
        let page: Int
        let perPage: Int
        enum CodingKeys: String, CodingKey { case page; case perPage = "per_page" }
    }

    private struct UserPayload: Encodable, Sendable {
        let email: String
        let firstName: String
        let lastName: String
        enum CodingKeys: String, CodingKey {
            case email; case firstName = "first_name"; case lastName = "last_name"
        }
    }

    private struct UserPatchPayload: Encodable, Sendable {
        let email: String?
        let firstName: String?
        let lastName: String?
        enum CodingKeys: String, CodingKey {
            case email; case firstName = "first_name"; case lastName = "last_name"
        }
    }

    // MARK: - Users API

    /// Get users list with pagination
    /// GET /api/users?page={page}
    func getUsers(page: Int = 1, perPage: Int? = nil) async throws -> UsersListResponse {
        let endpoint = "\(baseURL)\(config.usersEndpoint)"
        let query = UsersQuery(page: page, perPage: perPage ?? config.defaultPageSize)

        return try await session.request(
            endpoint,
            method: .get,
            parameters: query
        )
        .validate()
        .serializingDecodable(UsersListResponse.self)
        .value
    }
    
    /// Get single user by ID
    /// GET /api/users/{id}
    func getUser(id: String) async throws -> SingleUserResponse {
        let endpoint = "\(baseURL)/users/\(id)"
        
        return try await session.request(
            endpoint,
            method: .get
        )
        .validate()
        .serializingDecodable(SingleUserResponse.self)
        .value
    }
    
    /// Create new user
    /// POST /api/users
    func createUser(email: String, firstName: String, lastName: String) async throws -> CreateUserResponse {
        let endpoint = "\(baseURL)/users"
        let payload = UserPayload(email: email, firstName: firstName, lastName: lastName)

        return try await session.request(
            endpoint,
            method: .post,
            parameters: payload,
            encoder: JSONParameterEncoder.default
        )
        .validate()
        .serializingDecodable(CreateUserResponse.self)
        .value
    }
    
    /// Update user (PUT - full update)
    /// PUT /api/users/{id}
    func updateUser(id: String, email: String, firstName: String, lastName: String) async throws -> UpdateUserResponse {
        let endpoint = "\(baseURL)/users/\(id)"
        let payload = UserPayload(email: email, firstName: firstName, lastName: lastName)

        return try await session.request(
            endpoint,
            method: .put,
            parameters: payload,
            encoder: JSONParameterEncoder.default
        )
        .validate()
        .serializingDecodable(UpdateUserResponse.self)
        .value
    }
    
    /// Update user (PATCH - partial update)
    /// PATCH /api/users/{id}
    func patchUser(id: String, email: String?, firstName: String?, lastName: String?) async throws -> UpdateUserResponse {
        let endpoint = "\(baseURL)/users/\(id)"
        // Optionals left `nil` are omitted by the synthesized encoder (encodeIfPresent),
        // preserving the original partial-update semantics.
        let payload = UserPatchPayload(email: email, firstName: firstName, lastName: lastName)

        return try await session.request(
            endpoint,
            method: .patch,
            parameters: payload,
            encoder: JSONParameterEncoder.default
        )
        .validate()
        .serializingDecodable(UpdateUserResponse.self)
        .value
    }
    
    /// Delete user
    /// DELETE /api/users/{id}
    func deleteUser(id: String) async throws {
        let endpoint = "\(baseURL)/users/\(id)"

        let response = await session.request(
            endpoint,
            method: .delete
        )
        .validate()
        .serializingData()
        .response

        // reqres.in returns 204 No Content on successful delete
        guard response.response?.statusCode == 204 else {
            throw ApiError.unexpectedStatusCode(response.response?.statusCode ?? 0)
        }
    }
}

// MARK: - API Interceptor

/// Request/Response interceptor for logging and error handling
private final class ApiInterceptor: RequestInterceptor, @unchecked Sendable {

    private let apiKey = "reqres-free-v1"
    private let config: AppConfiguration

    init(config: AppConfiguration = .shared) {
        self.config = config
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest

        // Add common headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add API key header as required by reqres.in
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        completion(.success(urlRequest))
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        let maxRetries = config.apiMaxRetries

        guard request.retryCount < maxRetries else {
            completion(.doNotRetry)
            return
        }

        // Retry on network errors
        if let afError = error.asAFError, afError.isSessionTaskError {
            completion(.retryWithDelay(1.0))
        } else {
            completion(.doNotRetry)
        }
    }
}

// MARK: - API Response Models

/// Response for users list
nonisolated struct UsersListResponse: Codable, Sendable {
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int
    let data: [ReqresUser]
    let support: Support?
    
    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case total
        case totalPages = "total_pages"
        case data
        case support
    }
}

/// Response for single user
nonisolated struct SingleUserResponse: Codable, Sendable {
    let data: ReqresUser
    let support: Support?
}

/// Response for create user
nonisolated struct CreateUserResponse: Codable, Sendable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "createdAt"
    }
}

/// Response for update user
nonisolated struct UpdateUserResponse: Codable, Sendable {
    let email: String?
    let firstName: String?
    let lastName: String?
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case updatedAt = "updatedAt"
    }
}

/// User model from reqres.in API
nonisolated struct ReqresUser: Codable, Sendable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    let avatar: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case avatar
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

/// Support information from API
nonisolated struct Support: Codable, Sendable {
    let url: String
    let text: String
}

// MARK: - API Error

enum ApiError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case unexpectedStatusCode(Int)
    case invalidResponse
    case userNotFound
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        case .userNotFound:
            return "User not found"
        }
    }
}

// MARK: - Conversion Extensions

extension ReqresUser {
    /// Convert reqres.in user to app User model
    func toUser() -> User {
        User(
            id: String(id),
            email: email,
            firstName: firstName,
            lastName: lastName,
            avatar: avatar
        )
    }
}

extension User {
    /// Convert app User to reqres.in user ID
    var reqresId: String {
        id
    }
}
