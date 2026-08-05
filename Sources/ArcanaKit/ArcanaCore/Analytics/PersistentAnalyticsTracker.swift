//
//  PersistentAnalyticsTracker.swift
//  arcana-ios
//
//  Created by John on 2025/11/15.
//

import Foundation
import SwiftData
import OSLog

/// Analytics tracker that persists events to SwiftData
final class PersistentAnalyticsTracker: AnalyticsTracker, @unchecked Sendable {
    
    private let modelContainer: ModelContainer
    private(set) var sessionId: String
    private let logger = Logger(subsystem: "com.example.arcana.ios", category: "Analytics")
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.sessionId = UUID().uuidString
        
        // Log session start
        logger.info("📊 Analytics session started: \(self.sessionId)")
    }
    
    @MainActor
    private var context: ModelContext {
        modelContainer.mainContext
    }
    
    // MARK: - AnalyticsTracker Implementation
    
    func trackEvent(_ event: AnalyticsEvent, params: [String: any Sendable] = [:]) {
        Task { @MainActor in
            let entity = AnalyticsEventEntity.from(
                event: event,
                sessionId: sessionId,
                params: params
            )
            
            context.insert(entity)
            
            do {
                try context.save()
                logger.debug("📊 Event tracked: \(event.rawValue) - \(params)")
            } catch {
                logger.error("❌ Failed to save analytics event: \(error.localizedDescription)")
            }
        }
    }
    
    func trackScreen(_ screen: String, params: [String: any Sendable] = [:]) {
        var screenParams = params
        screenParams["screen_name"] = screen
        
        // Determine which screen event to use
        let event: AnalyticsEvent
        switch screen.lowercased() {
        case let s where s.contains("home"):
            event = .screenHomeViewed
        case let s where s.contains("list"):
            event = .screenUserListViewed
        case let s where s.contains("detail"):
            event = .screenUserDetailViewed
        case let s where s.contains("form"):
            event = .screenUserFormViewed
        case let s where s.contains("analytics"):
            event = .screenAnalyticsViewed
        default:
            event = .screenHomeViewed
        }
        
        trackEvent(event, params: screenParams)
    }
    
    func trackError(_ error: Error, context: [String: any Sendable] = [:]) {
        let appError = AppError.from(error)
        trackAppError(appError, context: context)
    }

    func trackAppError(_ appError: AppError, context: [String: any Sendable] = [:]) {
        Task { @MainActor in
            let entity = AnalyticsEventEntity.fromError(
                error: appError,
                sessionId: sessionId,
                context: context
            )
            
            self.context.insert(entity)
            
            do {
                try self.context.save()
                logger.error("❌ Error tracked: [\(appError.errorCode.code)] \(appError.message)")
            } catch {
                logger.error("❌ Failed to save error event: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Query Methods
    
    //
    // The query helpers below touch the SwiftData `context` (a `@MainActor` property),
    // and `AnalyticsEventEntity` is a non-Sendable `@Model`, so under Swift 6 these must
    // stay on the main actor rather than hand results back through a continuation. They
    // are `@MainActor async` — callers `await` them from the main actor.
    //

    /// Get all analytics events
    @MainActor
    func getAllEvents() throws -> [AnalyticsEventEntity] {
        let descriptor = FetchDescriptor<AnalyticsEventEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Get events by category
    @MainActor
    func getEvents(category: String) throws -> [AnalyticsEventEntity] {
        let predicate = #Predicate<AnalyticsEventEntity> { event in
            event.category == category
        }
        let descriptor = FetchDescriptor<AnalyticsEventEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Get error events
    @MainActor
    func getErrorEvents() throws -> [AnalyticsEventEntity] {
        let predicate = #Predicate<AnalyticsEventEntity> { event in
            event.eventType == "ERROR"
        }
        let descriptor = FetchDescriptor<AnalyticsEventEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Get events count
    @MainActor
    func getEventsCount() throws -> Int {
        let descriptor = FetchDescriptor<AnalyticsEventEntity>()
        return try context.fetchCount(descriptor)
    }

    /// Clear all analytics events
    @MainActor
    func clearAllEvents() throws {
        do {
            try context.delete(model: AnalyticsEventEntity.self)
            try context.save()
            logger.info("📊 All analytics events cleared")
        } catch {
            logger.error("❌ Failed to clear analytics events: \(error.localizedDescription)")
            throw error
        }
    }

    /// Mark events as synced
    @MainActor
    func markEventsSynced(_ eventIds: [String]) throws {
        do {
            for eventId in eventIds {
                let predicate = #Predicate<AnalyticsEventEntity> { event in
                    event.id == eventId
                }
                let descriptor = FetchDescriptor<AnalyticsEventEntity>(predicate: predicate)

                if let event = try context.fetch(descriptor).first {
                    event.isSynced = true
                }
            }

            try context.save()
            logger.info("📊 Marked \(eventIds.count) events as synced")
        } catch {
            logger.error("❌ Failed to mark events as synced: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Session Management
    
    func startNewSession() {
        sessionId = UUID().uuidString
        logger.info("📊 New analytics session started: \(self.sessionId)")
        trackEvent(.sessionStarted)
    }
    
    func endSession() {
        trackEvent(.sessionEnded)
        logger.info("📊 Analytics session ended: \(self.sessionId)")
    }
}
