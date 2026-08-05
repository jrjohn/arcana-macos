//
//  VectorClock.swift
//  ArcanaSync — Swift port of Arcana.Sync.Crdt.VectorClock (arcana-windows).
//
//  A vector clock tracks causality across nodes in a distributed system. It is an
//  immutable value type here (the C# version returned fresh instances from Increment /
//  Merge, so a `struct` is the faithful — and Sendable — Swift shape).
//

import Foundation

/// Causal relationship between two vector clocks.
public enum CausalRelation: Sendable, Equatable {
    /// Causally related — this clock happened after the other.
    case happenedAfter
    /// Causally related — this clock happened before the other.
    case happenedBefore
    /// The events happened concurrently (no causal ordering).
    case concurrent
    /// The clocks are identical.
    case equal
}

/// Vector clock for tracking causality in distributed systems.
public struct VectorClock: Sendable, Comparable, Codable, CustomStringConvertible {

    /// The per-node logical counters. Absent nodes are treated as `0`.
    public private(set) var clock: [String: Int64]

    public init() {
        clock = [:]
    }

    public init(_ clock: [String: Int64]) {
        self.clock = clock
    }

    /// The counter value for a node (`0` if the node has never been seen).
    public func value(for nodeId: String) -> Int64 {
        clock[nodeId] ?? 0
    }

    /// Returns a new clock with `nodeId` incremented by one.
    public func incremented(_ nodeId: String) -> VectorClock {
        var next = clock
        next[nodeId] = value(for: nodeId) + 1
        return VectorClock(next)
    }

    /// Merges with another clock, taking the component-wise maximum.
    public func merged(with other: VectorClock) -> VectorClock {
        var next = clock
        for (node, value) in other.clock {
            if let existing = next[node] {
                next[node] = Swift.max(existing, value)
            } else {
                next[node] = value
            }
        }
        return VectorClock(next)
    }

    /// Determines the causal relationship to another clock.
    public func relation(to other: VectorClock) -> CausalRelation {
        var thisGreater = false
        var otherGreater = false

        for node in Set(clock.keys).union(other.clock.keys) {
            let a = value(for: node)
            let b = other.value(for: node)
            if a > b { thisGreater = true }
            if b > a { otherGreater = true }
        }

        if thisGreater && otherGreater { return .concurrent }
        if thisGreater { return .happenedAfter }
        if otherGreater { return .happenedBefore }
        return .equal
    }

    // MARK: - Comparable / Equatable
    //
    // Equality and ordering follow causality (matching the C# IEquatable/IComparable):
    // `==` means the clocks are causally equal, `<` means this happened before the other.
    // Note this is a partial order — `concurrent` clocks are neither `<`, `>`, nor `==`.

    public static func == (lhs: VectorClock, rhs: VectorClock) -> Bool {
        lhs.relation(to: rhs) == .equal
    }

    public static func < (lhs: VectorClock, rhs: VectorClock) -> Bool {
        lhs.relation(to: rhs) == .happenedBefore
    }

    // MARK: - Codable / serialization
    //
    // Encodes as the bare `{node: counter}` object, matching the C#
    // `JsonSerializer.Serialize(Dictionary<string,long>)` wire form.

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        clock = try container.decode([String: Int64].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(clock)
    }

    /// Serializes the clock to a JSON string (`{"node":counter,...}`).
    public func serialized() -> String {
        guard let data = try? JSONEncoder().encode(clock),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Deserializes a clock from a JSON string, returning an empty clock on failure.
    public static func deserialize(_ json: String) -> VectorClock {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return VectorClock()
        }
        return VectorClock(dict)
    }

    public var description: String {
        let body = clock
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ", ")
        return "VectorClock(\(body))"
    }
}
