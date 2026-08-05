//
//  SyncService.swift
//  ArcanaSync — Swift port of Arcana.Sync.SyncService (arcana-windows).
//
//  The C# interface exposed progress via C# `event`s; the idiomatic Swift equivalent is an
//  `AsyncStream`, so `StateChanged` / `SyncCompleted` become `stateChanges` / `syncCompletions`
//  streams. `Result<Void, Error>` stands in for Arcana.Core.Common.Result.
//

import Foundation

/// The background sync engine's current state.
public enum SyncState: Sendable, Equatable {
    case idle
    case syncing
    case error
    case offline
}

/// Emitted when the sync state transitions.
public struct SyncStateChange: Sendable, Equatable {
    public let oldState: SyncState
    public let newState: SyncState
    public let message: String?

    public init(oldState: SyncState, newState: SyncState, message: String? = nil) {
        self.oldState = oldState
        self.newState = newState
        self.message = message
    }
}

/// Emitted when a sync pass finishes.
public struct SyncCompleted: Sendable, Equatable {
    public let success: Bool
    public let itemsSynced: Int
    public let itemsFailed: Int
    public let duration: Duration
    public let errorMessage: String?

    public init(
        success: Bool,
        itemsSynced: Int,
        itemsFailed: Int,
        duration: Duration,
        errorMessage: String? = nil
    ) {
        self.success = success
        self.itemsSynced = itemsSynced
        self.itemsFailed = itemsFailed
        self.duration = duration
        self.errorMessage = errorMessage
    }
}

/// Background synchronization service. Implementations run the CRDT sync loop; state and
/// completion are observed through the two `AsyncStream`s.
public protocol SyncService: Sendable {
    /// The current sync state.
    var state: SyncState { get async }

    /// When the last successful sync completed, if any.
    var lastSyncTime: Date? { get async }

    /// The number of items still pending sync.
    var pendingCount: Int { get async }

    /// A stream of state transitions.
    var stateChanges: AsyncStream<SyncStateChange> { get }

    /// A stream of completed sync passes.
    var syncCompletions: AsyncStream<SyncCompleted> { get }

    /// Starts the background sync loop.
    func start() async throws

    /// Stops the background sync loop.
    func stop() async throws

    /// Forces an immediate sync pass.
    @discardableResult
    func syncNow() async -> Result<Void, Error>

    /// Queues an entity change for the next sync pass.
    func queueForSync<Entity: SyncResolvable>(_ entity: Entity, operation: SyncOperationType) async
}
