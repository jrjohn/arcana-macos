//
//  CoverageTests.swift
//  ArcanaSyncTests — exercises the CRDT value types, metadata, and resolver strategies not
//  hit by the core-law tests.
//

import Testing
import Foundation
@testable import ArcanaSync

// A concrete syncable entity for the protocol's default-method coverage.
private final class Doc: SyncableEntity {
    let syncId: String
    var vectorClockJson: String?
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var modifiedByNodeId: String?
    var hasConflict: Bool = false
    var conflictingVersionJson: String?
    init(syncId: String) { self.syncId = syncId }
}

@Suite("SyncableEntity & metadata")
struct SyncableEntityCoverageTests {

    @Test("vector clock get / set / increment stamp metadata")
    func clockLifecycle() {
        let doc = Doc(syncId: "d1")
        #expect(doc.vectorClock().relation(to: VectorClock()) == .equal)   // empty
        doc.setVectorClock(VectorClock(["a": 2]))
        #expect(doc.vectorClock().value(for: "a") == 2)
        doc.incrementClock("a", now: Date(timeIntervalSince1970: 100))
        #expect(doc.vectorClock().value(for: "a") == 3)
        #expect(doc.modifiedByNodeId == "a")
        #expect(doc.modifiedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("sync metadata and conflict record construct")
    func metadata() {
        let meta = SyncMetadata(entityType: "Customer", entityId: "1", vectorClockJson: "{}",
                                modifiedAt: Date(timeIntervalSince1970: 0), modifiedByNodeId: "a",
                                operation: .update)
        #expect(meta.operation == .update)
        #expect(!meta.isSynced)
        let record = SyncConflictRecord(entityType: "Customer", entityId: "1",
                                        localVersionJson: "{}", remoteVersionJson: "{}",
                                        localClockJson: "{}", remoteClockJson: "{}")
        #expect(record.id == 0)
        #expect(!record.isResolved)
    }
}

@Suite("SyncValue & LWWMap")
struct SyncValueCoverageTests {

    @Test("SyncValue encodes and decodes every case")
    func syncValueCodable() throws {
        let values: [SyncValue] = [.string("s"), .int(7), .double(1.5), .bool(true), .null]
        let data = try JSONEncoder().encode(values)
        let restored = try JSONDecoder().decode([SyncValue].self, from: data)
        #expect(restored == values)
    }

    @Test("LWWMap set / get / overwrite by newer timestamp")
    func lwwMap() {
        let t0 = Date(timeIntervalSince1970: 1)
        let t1 = Date(timeIntervalSince1970: 2)
        var map = LWWMap()
        map.set("k", .int(1), timestamp: t0, nodeId: "a")
        map.set("k", .int(2), timestamp: t1, nodeId: "a")   // newer wins
        #expect(map.get("k") == .int(2))
        #expect(map.get("missing") == nil)
        #expect(map.fields.count == 1)
    }
}

// A resolvable value snapshot with a real field-level merge.
private struct Doc2: SyncResolvable, Equatable {
    let id: String
    let title: String
    let body: String
    var entityId: String { id }
    func fieldLevelMerged(with other: Doc2, preferLocal: Bool) -> Doc2 {
        Doc2(id: id, title: preferLocal ? title : other.title, body: other.body)
    }
}

@Suite("ConflictResolver strategies")
struct ResolverCoverageTests {

    private let concurrentA = VectorClock(["a": 1])
    private let concurrentB = VectorClock(["b": 1])

    @Test("causally-before remote and equal clocks short-circuit")
    func causalBranches() {
        let resolver = ConflictResolver(nodeId: "a")
        let local = Doc2(id: "1", title: "L", body: "l")
        let remote = Doc2(id: "1", title: "R", body: "r")
        let before = resolver.resolve(local: local, remote: remote,
            localClock: VectorClock(["a": 1]), remoteClock: VectorClock(["a": 2]),
            localTimestamp: Date(timeIntervalSince1970: 1), remoteTimestamp: Date(timeIntervalSince1970: 2))
        #expect(before.result == remote)                 // remote newer
        let equal = resolver.resolve(local: local, remote: remote,
            localClock: VectorClock(["a": 1]), remoteClock: VectorClock(["a": 1]),
            localTimestamp: Date(timeIntervalSince1970: 1), remoteTimestamp: Date(timeIntervalSince1970: 1))
        #expect(equal.result == local)                   // identical
        #expect(!equal.hadConflict)
    }

    @Test("firstWriterWins and fieldLevelMerge strategies")
    func strategies() {
        let fww = ConflictResolver(nodeId: "a")
        fww.configure(Doc2.self, strategy: .firstWriterWins)
        let a = Doc2(id: "1", title: "old", body: "old")
        let b = Doc2(id: "1", title: "new", body: "new")
        let firstResult = fww.resolve(local: a, remote: b,
            localClock: concurrentA, remoteClock: concurrentB,
            localTimestamp: Date(timeIntervalSince1970: 1), remoteTimestamp: Date(timeIntervalSince1970: 5))
        #expect(firstResult.result == a)                 // earlier wins

        let field = ConflictResolver(nodeId: "a")
        field.configure(Doc2.self, strategy: .fieldLevelMerge)
        let merged = field.resolve(local: a, remote: b,
            localClock: concurrentA, remoteClock: concurrentB,
            localTimestamp: Date(timeIntervalSince1970: 5), remoteTimestamp: Date(timeIntervalSince1970: 1))
        #expect(merged.result.title == "old")            // local preferred on title
        #expect(merged.result.body == "new")             // body always from other
    }

    @Test("keepBoth falls back to LWW for the result")
    func keepBoth() {
        let resolver = ConflictResolver(nodeId: "a")
        resolver.configure(Doc2.self, strategy: .keepBoth)
        let a = Doc2(id: "1", title: "L", body: "l")
        let b = Doc2(id: "1", title: "R", body: "r")
        let result = resolver.resolve(local: a, remote: b,
            localClock: concurrentA, remoteClock: concurrentB,
            localTimestamp: Date(timeIntervalSince1970: 9), remoteTimestamp: Date(timeIntervalSince1970: 1))
        #expect(result.hadConflict)
        #expect(result.result == a)                      // newer local by timestamp
    }
}

@Suite("VectorClock & SyncService types")
struct SyncMiscCoverageTests {

    @Test("vector clock description and ordering operators")
    func vectorClockMisc() {
        let clock = VectorClock(["a": 1, "b": 2])
        #expect(clock.description.contains("a:1"))
        #expect(VectorClock(["a": 1]) < VectorClock(["a": 2]))
        #expect(clock.value(for: "z") == 0)
    }

    @Test("sync service event structs and enums")
    func syncServiceTypes() {
        let change = SyncStateChange(oldState: .idle, newState: .syncing, message: "go")
        #expect(change.newState == .syncing)
        let done = SyncCompleted(success: true, itemsSynced: 3, itemsFailed: 0, duration: .seconds(1))
        #expect(done.itemsSynced == 3)
        #expect(SyncOperationType.create.rawValue == "create")
        #expect(SyncState.offline == .offline)
    }
}
