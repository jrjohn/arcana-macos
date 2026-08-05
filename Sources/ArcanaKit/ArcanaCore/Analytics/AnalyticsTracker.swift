//
//  AnalyticsTracker.swift
//  arcana-ios
//
//  Created by John on 2025/11/15.
//

import Foundation

/// Protocol for analytics tracking
protocol AnalyticsTracker: AnyObject, Sendable {
    /// Track an event with optional parameters.
    /// Values are `any Sendable` so the params can be captured into the tracker's
    /// `@MainActor` persistence task under Swift 6 strict concurrency (Int/String/Bool
    /// literals already conform, so call sites are unchanged).
    func trackEvent(_ event: AnalyticsEvent, params: [String: any Sendable])

    /// Track a screen view
    func trackScreen(_ screen: String, params: [String: any Sendable])

    /// Track an error
    func trackError(_ error: Error, context: [String: any Sendable])

    /// Track an AppError with error codes
    func trackAppError(_ appError: AppError, context: [String: any Sendable])
    
    /// Get current session ID
    var sessionId: String { get }
}

// MARK: - Default Implementations
extension AnalyticsTracker {
    func trackEvent(_ event: AnalyticsEvent) {
        trackEvent(event, params: [:])
    }
    
    func trackScreen(_ screen: String) {
        trackScreen(screen, params: [:])
    }
    
    func trackError(_ error: Error) {
        trackError(error, context: [:])
    }
    
    func trackAppError(_ appError: AppError) {
        trackAppError(appError, context: [:])
    }
}
