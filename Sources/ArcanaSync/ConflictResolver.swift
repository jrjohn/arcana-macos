//
//  ConflictResolver.swift
//  ArcanaSync — Swift port of Arcana.Sync.Crdt.ConflictResolver (arcana-windows).
//
//  The C# version reflected over public properties to read the entity id and to do a
//  field-level merge. Swift can't set arbitrary properties by reflection, so those two
//  reflection hooks become an explicit protocol (`SyncResolvable`): the type states its
//  own id and (optionally) how to merge itself field-by-field. Everything else — the
//  causal short-circuits, the strategy registry, and the merged-clock bump — is faithful.
//

import Foundation

/// How to resolve a concurrent conflict between two versions of an entity.
public enum ConflictResolutionStrategy: String, Sendable {
    case lastWriterWins
    case firstWriterWins
    case fieldLevelMerge
    case keepBoth
    case custom
}

/// A type that can take part in conflict resolution: it exposes a stable id and,
/// optionally, a field-level merge. Value snapshots (not live persistence models) are
/// passed here, so conformers are `Sendable`.
public protocol SyncResolvable: Sendable {
    /// Stable identity, used for deterministic tie-breaking.
    var entityId: String { get }

    /// Field-by-field merge. `preferLocal` says which side wins per-field ties (by the
    /// overall timestamp comparison). The default keeps the whole preferred side (LWW).
    func fieldLevelMerged(with other: Self, preferLocal: Bool) -> Self
}

public extension SyncResolvable {
    func fieldLevelMerged(with other: Self, preferLocal: Bool) -> Self {
        preferLocal ? self : other
    }
}

/// A detected conflict between a local and a remote version.
public struct SyncConflict<Entity: SyncResolvable>: Sendable {
    public let entityId: String
    public let localVersion: Entity
    public let remoteVersion: Entity
    public let localClock: VectorClock
    public let remoteClock: VectorClock
    public let relation: CausalRelation
    public let detectedAt: Date

    public init(
        entityId: String,
        localVersion: Entity,
        remoteVersion: Entity,
        localClock: VectorClock,
        remoteClock: VectorClock,
        relation: CausalRelation,
        detectedAt: Date = Date()
    ) {
        self.entityId = entityId
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.localClock = localClock
        self.remoteClock = remoteClock
        self.relation = relation
        self.detectedAt = detectedAt
    }
}

/// The outcome of resolving a conflict.
public struct ConflictResolutionResult<Entity: SyncResolvable>: Sendable {
    public let result: Entity
    public let mergedClock: VectorClock
    public let hadConflict: Bool
    public let resolution: String
    public let localVersion: Entity?
    public let remoteVersion: Entity?

    public init(
        result: Entity,
        mergedClock: VectorClock,
        hadConflict: Bool,
        resolution: String,
        localVersion: Entity? = nil,
        remoteVersion: Entity? = nil
    ) {
        self.result = result
        self.mergedClock = mergedClock
        self.hadConflict = hadConflict
        self.resolution = resolution
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
    }
}

/// Resolves conflicts for sync operations. Holds a per-type strategy registry (guarded by
/// a lock so the resolver is safely shared across the sync actor and its callers).
public final class ConflictResolver: @unchecked Sendable {

    private let nodeId: String
    private let defaultStrategy: ConflictResolutionStrategy
    private let lock = NSLock()
    private var strategies: [ObjectIdentifier: ConflictResolutionStrategy] = [:]
    private var customResolvers: [ObjectIdentifier: any Sendable] = [:]

    public init(nodeId: String, defaultStrategy: ConflictResolutionStrategy = .lastWriterWins) {
        self.nodeId = nodeId
        self.defaultStrategy = defaultStrategy
    }

    /// Configures the strategy for a specific entity type.
    public func configure<Entity: SyncResolvable>(
        _ type: Entity.Type, strategy: ConflictResolutionStrategy
    ) {
        lock.lock(); defer { lock.unlock() }
        strategies[ObjectIdentifier(type)] = strategy
    }

    /// Configures a custom resolver closure for a specific entity type.
    public func configureCustom<Entity: SyncResolvable>(
        _ type: Entity.Type,
        _ resolver: @escaping @Sendable (SyncConflict<Entity>) -> Entity
    ) {
        lock.lock(); defer { lock.unlock() }
        strategies[ObjectIdentifier(type)] = .custom
        customResolvers[ObjectIdentifier(type)] = resolver
    }

    private func strategy<Entity: SyncResolvable>(for type: Entity.Type) -> ConflictResolutionStrategy {
        lock.lock(); defer { lock.unlock() }
        return strategies[ObjectIdentifier(type)] ?? defaultStrategy
    }

    private func customResolver<Entity: SyncResolvable>(
        for type: Entity.Type
    ) -> (@Sendable (SyncConflict<Entity>) -> Entity)? {
        lock.lock(); defer { lock.unlock() }
        return customResolvers[ObjectIdentifier(type)] as? @Sendable (SyncConflict<Entity>) -> Entity
    }

    /// Resolves a conflict between local and remote versions. Causally ordered versions
    /// short-circuit without a conflict; only genuinely concurrent versions invoke a strategy.
    public func resolve<Entity: SyncResolvable>(
        local: Entity,
        remote: Entity,
        localClock: VectorClock,
        remoteClock: VectorClock,
        localTimestamp: Date,
        remoteTimestamp: Date
    ) -> ConflictResolutionResult<Entity> {
        let relation = localClock.relation(to: remoteClock)

        switch relation {
        case .happenedAfter:
            return ConflictResolutionResult(
                result: local, mergedClock: localClock, hadConflict: false,
                resolution: "Local version is newer")
        case .happenedBefore:
            return ConflictResolutionResult(
                result: remote, mergedClock: remoteClock, hadConflict: false,
                resolution: "Remote version is newer")
        case .equal:
            return ConflictResolutionResult(
                result: local, mergedClock: localClock, hadConflict: false,
                resolution: "Versions are identical")
        case .concurrent:
            break
        }

        let strategy = strategy(for: Entity.self)
        let mergedClock = localClock.merged(with: remoteClock).incremented(nodeId)

        let resolved: Entity
        switch strategy {
        case .lastWriterWins, .keepBoth:
            resolved = lastWriterWins(local, remote, localTimestamp, remoteTimestamp)
        case .firstWriterWins:
            resolved = firstWriterWins(local, remote, localTimestamp, remoteTimestamp)
        case .fieldLevelMerge:
            resolved = local.fieldLevelMerged(with: remote, preferLocal: localTimestamp >= remoteTimestamp)
        case .custom:
            if let resolver = customResolver(for: Entity.self) {
                let conflict = SyncConflict(
                    entityId: local.entityId,
                    localVersion: local, remoteVersion: remote,
                    localClock: localClock, remoteClock: remoteClock,
                    relation: relation)
                resolved = resolver(conflict)
            } else {
                resolved = lastWriterWins(local, remote, localTimestamp, remoteTimestamp)
            }
        }

        return ConflictResolutionResult(
            result: resolved, mergedClock: mergedClock, hadConflict: true,
            resolution: "Resolved using \(strategy.rawValue)",
            localVersion: local, remoteVersion: remote)
    }

    // MARK: - Strategies

    private func lastWriterWins<Entity: SyncResolvable>(
        _ local: Entity, _ remote: Entity, _ localTimestamp: Date, _ remoteTimestamp: Date
    ) -> Entity {
        if remoteTimestamp > localTimestamp { return remote }
        if localTimestamp > remoteTimestamp { return local }
        return local.entityId > remote.entityId ? local : remote
    }

    private func firstWriterWins<Entity: SyncResolvable>(
        _ local: Entity, _ remote: Entity, _ localTimestamp: Date, _ remoteTimestamp: Date
    ) -> Entity {
        if remoteTimestamp < localTimestamp { return remote }
        if localTimestamp < remoteTimestamp { return local }
        return local.entityId < remote.entityId ? local : remote
    }
}
