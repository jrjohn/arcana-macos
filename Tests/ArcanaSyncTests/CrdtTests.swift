//
//  CrdtTests.swift
//  ArcanaSyncTests — the CRDT laws, ported from the behavior the Windows Arcana.Sync
//  relied on. Pure and deterministic: no clock, no I/O.
//

import Testing
import Foundation
@testable import ArcanaSync

@Suite("VectorClock causality")
struct VectorClockTests {

    @Test("empty clocks are equal")
    func emptyEqual() {
        #expect(VectorClock().relation(to: VectorClock()) == .equal)
    }

    @Test("increment makes a clock happen-after its predecessor")
    func incrementOrders() {
        let base = VectorClock()
        let next = base.incremented("A")
        #expect(next.relation(to: base) == .happenedAfter)
        #expect(base.relation(to: next) == .happenedBefore)
        #expect(next.value(for: "A") == 1)
    }

    @Test("independent increments on different nodes are concurrent")
    func concurrentBranches() {
        let root = VectorClock().incremented("A")   // {A:1}
        let left = root.incremented("A")             // {A:2}
        let right = root.incremented("B")            // {A:1, B:1}
        #expect(left.relation(to: right) == .concurrent)
        #expect(right.relation(to: left) == .concurrent)
    }

    @Test("merge takes the component-wise maximum")
    func mergeMax() {
        let left = VectorClock(["A": 3, "B": 1])
        let right = VectorClock(["A": 1, "B": 5, "C": 2])
        let merged = left.merged(with: right)
        #expect(merged.value(for: "A") == 3)
        #expect(merged.value(for: "B") == 5)
        #expect(merged.value(for: "C") == 2)
        // The merge dominates both inputs.
        #expect(merged.relation(to: left) == .happenedAfter)
        #expect(merged.relation(to: right) == .happenedAfter)
    }

    @Test("serialize / deserialize round-trips")
    func codableRoundTrip() {
        let clock = VectorClock(["node-1": 7, "node-2": 42])
        let restored = VectorClock.deserialize(clock.serialized())
        #expect(restored.relation(to: clock) == .equal)
        #expect(restored.value(for: "node-2") == 42)
    }
}

@Suite("LWWRegister & LWWMap")
struct LWWTests {

    @Test("a newer write wins; an older write is rejected")
    func newerWins() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        var reg = LWWRegister(value: "old", timestamp: t0, nodeId: "A")
        #expect(reg.update("new", timestamp: t1, nodeId: "B") == true)
        #expect(reg.value == "new")
        #expect(reg.update("stale", timestamp: t0, nodeId: "Z") == false)
        #expect(reg.value == "new")
    }

    @Test("equal timestamps break the tie on node id")
    func tieBreakOnNode() {
        let t = Date(timeIntervalSince1970: 5000)
        var reg = LWWRegister(value: "a", timestamp: t, nodeId: "A")
        // Higher node id wins on a tie.
        #expect(reg.update("b", timestamp: t, nodeId: "B") == true)
        #expect(reg.value == "b")
        // Lower node id loses on a tie.
        #expect(reg.update("a", timestamp: t, nodeId: "A") == false)
    }

    @Test("register merge is commutative")
    func mergeCommutes() {
        let early = LWWRegister(value: 1, timestamp: Date(timeIntervalSince1970: 10), nodeId: "A")
        let late = LWWRegister(value: 2, timestamp: Date(timeIntervalSince1970: 20), nodeId: "B")
        #expect(early.merged(with: late).value == 2)
        #expect(late.merged(with: early).value == 2)
    }

    @Test("map merges disjoint field edits without loss")
    func mapFieldLevelMerge() {
        let t = Date(timeIntervalSince1970: 100)
        var local = LWWMap()
        local.set("name", .string("Ann"), timestamp: t, nodeId: "A")
        var remote = LWWMap()
        remote.set("email", .string("ann@x.io"), timestamp: t, nodeId: "B")

        let merged = local.merged(with: remote)
        #expect(merged.get("name") == .string("Ann"))
        #expect(merged.get("email") == .string("ann@x.io"))
    }

    @Test("map merge resolves a contested field by LWW")
    func mapContestedField() {
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 200)
        var local = LWWMap()
        local.set("status", .string("draft"), timestamp: t0, nodeId: "A")
        var remote = LWWMap()
        remote.set("status", .string("published"), timestamp: t1, nodeId: "B")
        #expect(local.merged(with: remote).get("status") == .string("published"))
    }
}

@Suite("MVRegister")
struct MVRegisterTests {

    @Test("a dominating write replaces an earlier one")
    func dominationCollapses() throws {
        var reg = MVRegister(value: "v1", clock: VectorClock().incremented("A"))
        reg.set("v2", clock: VectorClock(["A": 2]))
        #expect(reg.hasConflict == false)
        #expect(try reg.singleValue() == "v2")
    }

    @Test("concurrent writes are both preserved")
    func concurrentPreserved() {
        let root = VectorClock().incremented("A")       // {A:1}
        var reg = MVRegister(value: "base", clock: root)
        reg.set("fromA", clock: root.incremented("A"))  // {A:2}
        reg.set("fromB", clock: root.incremented("B"))  // {A:1,B:1} — concurrent with {A:2}
        #expect(reg.hasConflict == true)
        #expect(reg.values.count == 2)
        #expect(throws: MVRegisterError.self) { try reg.singleValue() }
    }

    @Test("resolve collapses to the chosen value")
    func resolveCollapses() throws {
        let root = VectorClock().incremented("A")
        var reg = MVRegister(value: "fromA", clock: root.incremented("A"))
        reg.set("fromB", clock: root.incremented("B"))
        #expect(reg.hasConflict == true)

        let merged = root.incremented("A").merged(with: root.incremented("B")).incremented("A")
        reg.resolve("resolved", mergedClock: merged)
        #expect(reg.hasConflict == false)
        #expect(try reg.singleValue() == "resolved")
    }

    @Test("merge keeps only causally-maximal values")
    func mergeKeepsMaximal() {
        let root = VectorClock().incremented("A")           // {A:1}
        let a = MVRegister(value: "old", clock: root)
        var b = MVRegister(value: "new", clock: root.incremented("A"))  // {A:2} dominates {A:1}
        b.set("concurrent", clock: root.incremented("B"))               // {A:1,B:1}
        let merged = a.merged(with: b)
        // {A:1} is dominated by {A:2} and dropped; {A:2} and {A:1,B:1} survive.
        #expect(merged.values.count == 2)
    }
}

// A tiny value snapshot used to exercise ConflictResolver.
private struct DocSnapshot: SyncResolvable, Equatable {
    let id: String
    let title: String
    var entityId: String { id }
}

@Suite("ConflictResolver")
struct ConflictResolverTests {

    private let localClock = VectorClock(["A": 2])
    private let remoteClock = VectorClock(["A": 1])   // happened-before localClock

    @Test("causally-newer local short-circuits with no conflict")
    func causalLocalWins() {
        let resolver = ConflictResolver(nodeId: "A")
        let local = DocSnapshot(id: "1", title: "local")
        let remote = DocSnapshot(id: "1", title: "remote")
        let result = resolver.resolve(
            local: local, remote: remote,
            localClock: localClock, remoteClock: remoteClock,
            localTimestamp: Date(timeIntervalSince1970: 1),
            remoteTimestamp: Date(timeIntervalSince1970: 2))
        #expect(result.hadConflict == false)
        #expect(result.result == local)
    }

    @Test("concurrent clocks resolve by last-writer-wins on timestamp")
    func concurrentLWW() {
        let resolver = ConflictResolver(nodeId: "A")
        let local = DocSnapshot(id: "1", title: "local")
        let remote = DocSnapshot(id: "1", title: "remote")
        let result = resolver.resolve(
            local: local, remote: remote,
            localClock: VectorClock(["A": 1]),   // concurrent...
            remoteClock: VectorClock(["B": 1]),  // ...with this
            localTimestamp: Date(timeIntervalSince1970: 10),
            remoteTimestamp: Date(timeIntervalSince1970: 20))
        #expect(result.hadConflict == true)
        #expect(result.result == remote)                     // remote is newer
        // merged({A:1},{B:1}) = {A:1,B:1}, then bumped by resolver node A ⇒ A:2, B:1
        #expect(result.mergedClock.value(for: "A") == 2)
        #expect(result.mergedClock.value(for: "B") == 1)
    }

    @Test("a custom resolver is invoked for concurrent conflicts")
    func customResolver() {
        let resolver = ConflictResolver(nodeId: "A")
        resolver.configureCustom(DocSnapshot.self) { conflict in
            DocSnapshot(id: conflict.entityId, title: "\(conflict.localVersion.title)+\(conflict.remoteVersion.title)")
        }
        let result = resolver.resolve(
            local: DocSnapshot(id: "1", title: "L"),
            remote: DocSnapshot(id: "1", title: "R"),
            localClock: VectorClock(["A": 1]),
            remoteClock: VectorClock(["B": 1]),
            localTimestamp: Date(timeIntervalSince1970: 10),
            remoteTimestamp: Date(timeIntervalSince1970: 10))
        #expect(result.hadConflict == true)
        #expect(result.result.title == "L+R")
    }
}
