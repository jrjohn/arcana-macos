//
//  SyncEngine.swift
//  ArcanaShell — wires the ArcanaSync CRDT engine onto the app's real SwiftData data.
//
//  There is no remote peer yet, so a "sync" is a LOCAL-NODE pass: every pending entity has
//  its vector clock advanced for this device's node id, its node stamp written, and its
//  pending flag cleared. The conflict demo shows the `ConflictResolver` picking a winner
//  between two concurrent versions. When a remote transport is added, the same clocks +
//  resolver drive real multi-node merges.
//

import Foundation
import SwiftData
import ArcanaModel
import ArcanaSync

@MainActor
@Observable
public final class SyncEngine {
    public let nodeId: String
    public private(set) var state: SyncState = .idle
    public private(set) var lastSyncTime: Date?
    public private(set) var log: [String] = []

    private let resolver: ConflictResolver

    public init(nodeId: String? = nil) {
        let node = nodeId ?? SyncEngine.deviceNodeId()
        self.nodeId = node
        self.resolver = ConflictResolver(nodeId: node)
    }

    static func deviceNodeId() -> String {
        let key = "arcana.nodeId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = "node-\(UUID().uuidString.prefix(6))"
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    public func pendingCount(context: ModelContext) -> Int {
        let c = (try? context.fetchCount(FetchDescriptor<Customer>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? 0
        let p = (try? context.fetchCount(FetchDescriptor<Product>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? 0
        let o = (try? context.fetchCount(FetchDescriptor<Order>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? 0
        return c + p + o
    }

    /// A local-node sync pass: advance each pending entity's vector clock, stamp the node,
    /// and clear its pending flag.
    public func syncNow(context: ModelContext) {
        state = .syncing
        var synced = 0

        let customers = (try? context.fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? []
        for customer in customers {
            customer.vectorClockJson = advanced(customer.vectorClockJson)
            customer.modifiedByNodeId = nodeId
            customer.isPendingSync = false
            synced += 1
        }
        let products = (try? context.fetch(FetchDescriptor<Product>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? []
        for product in products {
            product.vectorClockJson = advanced(product.vectorClockJson)
            product.modifiedByNodeId = nodeId
            product.isPendingSync = false
            synced += 1
        }
        let orders = (try? context.fetch(FetchDescriptor<Order>(predicate: #Predicate { $0.isPendingSync && !$0.isSoftDeleted }))) ?? []
        for order in orders {
            order.vectorClockJson = advanced(order.vectorClockJson)
            order.modifiedByNodeId = nodeId
            order.isPendingSync = false
            synced += 1
        }

        try? context.save()
        lastSyncTime = Date()
        state = .idle
        prepend(synced == 0 ? "Nothing to sync." : "Synced \(synced) change(s) — clocks advanced for \(nodeId).")
    }

    /// Demonstrates conflict resolution: two concurrent edits of the same record, resolved by
    /// last-writer-wins through `ConflictResolver`.
    public func demonstrateConflict() {
        struct Snapshot: SyncResolvable, Equatable {
            let id: String
            let value: String
            var entityId: String { id }
        }
        let local = Snapshot(id: "REC-1", value: "local edit")
        let remote = Snapshot(id: "REC-1", value: "remote edit")
        let result = resolver.resolve(
            local: local, remote: remote,
            localClock: VectorClock([nodeId: 1]),      // concurrent...
            remoteClock: VectorClock(["node-remote": 1]),  // ...with a remote node
            localTimestamp: Date(),
            remoteTimestamp: Date().addingTimeInterval(-60))  // local is newer
        prepend("Conflict on REC-1 → kept “\(result.result.value)” (merged clock \(result.mergedClock)).")
    }

    // MARK: - Internals

    private func advanced(_ json: String?) -> String {
        VectorClock.deserialize(json ?? "{}").incremented(nodeId).serialized()
    }

    private func prepend(_ message: String) {
        log.insert(message, at: 0)
        if log.count > 50 { log.removeLast() }
    }
}
