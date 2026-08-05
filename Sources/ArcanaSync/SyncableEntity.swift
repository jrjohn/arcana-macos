//
//  SyncableEntity.swift
//  ArcanaSync — Swift port of Arcana.Sync.Crdt.SyncableEntity / SyncMetadata /
//  SyncConflictRecord (arcana-windows).
//

import Foundation

/// An entity that participates in CRDT-based synchronization. Conforming types are
/// typically reference-type persistence models (e.g. SwiftData `@Model` classes), which
/// is why this is a class-bound protocol with settable sync metadata.
public protocol SyncableEntity: AnyObject {
    /// Stable identity used for sync.
    var syncId: String { get }
    /// The serialized vector clock for this entity (`nil`/empty ⇒ a fresh clock).
    var vectorClockJson: String? { get set }
    /// When the entity was last modified.
    var modifiedAt: Date { get set }
    /// The node that last modified the entity.
    var modifiedByNodeId: String? { get set }
    /// Whether the entity has an unresolved conflict.
    var hasConflict: Bool { get set }
    /// The conflicting version, serialized as JSON, if any.
    var conflictingVersionJson: String? { get set }
}

public extension SyncableEntity {
    /// The entity's vector clock (empty if unset).
    func vectorClock() -> VectorClock {
        guard let json = vectorClockJson, !json.isEmpty else { return VectorClock() }
        return VectorClock.deserialize(json)
    }

    /// Stores a vector clock onto the entity.
    func setVectorClock(_ clock: VectorClock) {
        vectorClockJson = clock.serialized()
    }

    /// Increments the entity's clock for `nodeId` and stamps the modification metadata.
    func incrementClock(_ nodeId: String, now: Date = Date()) {
        setVectorClock(vectorClock().incremented(nodeId))
        modifiedByNodeId = nodeId
        modifiedAt = now
    }
}

/// Sync operation kind for an entity change.
public enum SyncOperationType: String, Sendable, Codable {
    case create
    case update
    case delete
}

/// Metadata tracking an entity's synchronization state.
public struct SyncMetadata: Sendable, Codable, Equatable {
    public let entityType: String
    public let entityId: String
    public let vectorClockJson: String
    public let modifiedAt: Date
    public let modifiedByNodeId: String
    public let operation: SyncOperationType
    public var isSynced: Bool
    public var syncedAt: Date?
    public var retryCount: Int
    public var lastError: String?

    public init(
        entityType: String,
        entityId: String,
        vectorClockJson: String,
        modifiedAt: Date,
        modifiedByNodeId: String,
        operation: SyncOperationType,
        isSynced: Bool = false,
        syncedAt: Date? = nil,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.vectorClockJson = vectorClockJson
        self.modifiedAt = modifiedAt
        self.modifiedByNodeId = modifiedByNodeId
        self.operation = operation
        self.isSynced = isSynced
        self.syncedAt = syncedAt
        self.retryCount = retryCount
        self.lastError = lastError
    }
}

/// A recorded conflict awaiting manual resolution.
public struct SyncConflictRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: Int
    public let entityType: String
    public let entityId: String
    public let localVersionJson: String
    public let remoteVersionJson: String
    public let localClockJson: String
    public let remoteClockJson: String
    public let detectedAt: Date
    public var isResolved: Bool
    public var resolvedAt: Date?
    public var resolvedByNodeId: String?
    public var resolutionStrategy: String?

    public init(
        id: Int = 0,
        entityType: String,
        entityId: String,
        localVersionJson: String,
        remoteVersionJson: String,
        localClockJson: String,
        remoteClockJson: String,
        detectedAt: Date = Date(),
        isResolved: Bool = false,
        resolvedAt: Date? = nil,
        resolvedByNodeId: String? = nil,
        resolutionStrategy: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.localVersionJson = localVersionJson
        self.remoteVersionJson = remoteVersionJson
        self.localClockJson = localClockJson
        self.remoteClockJson = remoteClockJson
        self.detectedAt = detectedAt
        self.isResolved = isResolved
        self.resolvedAt = resolvedAt
        self.resolvedByNodeId = resolvedByNodeId
        self.resolutionStrategy = resolutionStrategy
    }
}
