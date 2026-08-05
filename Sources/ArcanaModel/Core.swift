//
//  Foundation.swift
//  ArcanaModel — the shared vocabulary every service speaks: typed errors, and paging.
//  Ported from Arcana.Core.Common (Result/AppError/PagedResult).
//

import Foundation

/// Numbered error-code ranges (matching the C# ErrorCode taxonomy).
public enum ErrorCode: Int, Sendable, Codable {
    case unknown = 0
    case network = 1000
    case validation = 2000
    case server = 3000
    case auth = 4000
    case forbidden = 4030
    case data = 5000
    case database = 6000
    case plugin = 7000
    case file = 8000
}

/// A typed application error.
public struct AppError: Error, Sendable, Equatable {
    public let code: ErrorCode
    public let message: String
    public let validationErrors: [String]

    public init(code: ErrorCode, message: String, validationErrors: [String] = []) {
        self.code = code
        self.message = message
        self.validationErrors = validationErrors
    }

    public static func network(_ message: String) -> AppError { AppError(code: .network, message: message) }
    public static func validation(_ message: String, _ errors: [String] = []) -> AppError {
        AppError(code: .validation, message: message, validationErrors: errors)
    }
    public static func auth(_ message: String) -> AppError { AppError(code: .auth, message: message) }
    public static func forbidden(_ message: String) -> AppError { AppError(code: .forbidden, message: message) }
    public static func data(_ message: String) -> AppError { AppError(code: .data, message: message) }
    public static func notFound(_ message: String) -> AppError { AppError(code: .data, message: message) }
}

/// The result of a domain operation. (Swift's `Result` with our `AppError` as the failure.)
public typealias AppResult<Success> = Result<Success, AppError>

/// A page request.
public struct PageRequest: Sendable, Equatable {
    public var page: Int
    public var pageSize: Int
    public var sortBy: String?
    public var descending: Bool

    public init(page: Int = 1, pageSize: Int = 10, sortBy: String? = nil, descending: Bool = false) {
        self.page = max(1, page)
        self.pageSize = max(1, pageSize)
        self.sortBy = sortBy
        self.descending = descending
    }

    /// Number of items to skip for this page.
    public var skip: Int { (page - 1) * pageSize }
}

/// A page of results. (No `Sendable` bound — items may be main-actor SwiftData `@Model`s.)
public struct PagedResult<Item> {
    public let items: [Item]
    public let page: Int
    public let pageSize: Int
    public let totalCount: Int

    public init(items: [Item], page: Int, pageSize: Int, totalCount: Int) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.totalCount = totalCount
    }

    public var totalPages: Int { pageSize == 0 ? 0 : Int((Double(totalCount) / Double(pageSize)).rounded(.up)) }
    public var hasPreviousPage: Bool { page > 1 }
    public var hasNextPage: Bool { page < totalPages }
}
