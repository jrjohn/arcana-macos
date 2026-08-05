//
//  SyncEngineTests.swift
//  ArcanaShellTests — the CRDT sync wiring: a sync pass drains the pending queue and advances
//  each entity's vector clock for this node.
//

import Testing
import SwiftData
@testable import ArcanaShell
@testable import ArcanaModel
@testable import ArcanaSync

@Suite("SyncEngine", .serialized)
@MainActor
struct SyncEngineTests {
    static let container: ModelContainer = {
        try! ModelContainer(for: Schema(ArcanaSchema.models),
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    private var context: ModelContext { Self.container.mainContext }

    @Test("sync drains the pending queue and advances the node's vector clock")
    func syncDrains() {
        let customer = Customer(code: "SYNC1", name: "Pending Co")   // new rows are isPendingSync == true
        context.insert(customer)
        try? context.save()

        let engine = SyncEngine(nodeId: "node-test")
        #expect(engine.pendingCount(context: context) >= 1)

        engine.syncNow(context: context)

        #expect(customer.isPendingSync == false)
        #expect(customer.modifiedByNodeId == "node-test")
        let clock = VectorClock.deserialize(customer.vectorClockJson ?? "{}")
        #expect(clock.value(for: "node-test") == 1)
        #expect(engine.lastSyncTime != nil)
    }

    @Test("conflict demo logs a resolution")
    func conflictDemo() {
        let engine = SyncEngine(nodeId: "node-a")
        engine.demonstrateConflict()
        #expect(!engine.log.isEmpty)
    }
}
