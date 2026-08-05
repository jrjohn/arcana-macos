//
//  MVRegister.swift
//  ArcanaSync — Swift port of Arcana.Sync.Crdt.MVRegister (arcana-windows).
//

import Foundation

/// Error thrown when a single value is requested from a register that holds concurrent values.
public enum MVRegisterError: Error, Sendable {
    case multipleConcurrentValues
}

/// Multi-Value Register CRDT. Instead of picking a winner, it preserves every concurrent
/// value (each tagged with the vector clock at which it was written) and leaves the choice
/// to the caller via `resolve`.
public struct MVRegister<Value: Sendable & Equatable>: Sendable {

    /// A concurrent value and the clock under which it was written.
    public struct Entry: Sendable, Equatable {
        public let value: Value
        public let clock: VectorClock
        public init(value: Value, clock: VectorClock) {
            self.value = value
            self.clock = clock
        }
    }

    public private(set) var values: [Entry]

    public init() {
        values = []
    }

    public init(value: Value, clock: VectorClock) {
        values = [Entry(value: value, clock: clock)]
    }

    /// Whether more than one concurrent value is present.
    public var hasConflict: Bool { values.count > 1 }

    /// The single value if there is no conflict; throws if multiple concurrent values exist.
    public func singleValue() throws -> Value {
        guard values.count == 1 else { throw MVRegisterError.multipleConcurrentValues }
        return values[0].value
    }

    /// Adds a value at the given clock, dropping any values it causally dominates and
    /// ignoring it if it is itself dominated by an existing value.
    public mutating func set(_ value: Value, clock: VectorClock) {
        values.removeAll { $0.clock.relation(to: clock) == .happenedBefore }

        let dominated = values.contains { $0.clock.relation(to: clock) == .happenedAfter }
        if !dominated {
            values.append(Entry(value: value, clock: clock))
        }
    }

    /// Merges with another register, keeping only the causally maximal (non-dominated)
    /// values and de-duplicating by clock.
    public func merged(with other: MVRegister<Value>) -> MVRegister<Value> {
        let all = values + other.values
        var result = MVRegister<Value>()

        for (index, entry) in all.enumerated() {
            let dominated = all.enumerated().contains { otherIndex, candidate in
                otherIndex != index
                    && candidate.clock.relation(to: entry.clock) == .happenedAfter
            }
            guard !dominated else { continue }

            if !result.values.contains(where: { $0.clock == entry.clock }) {
                result.values.append(entry)
            }
        }
        return result
    }

    /// Collapses all concurrent values into a single resolved value at the merged clock.
    public mutating func resolve(_ resolvedValue: Value, mergedClock: VectorClock) {
        values = [Entry(value: resolvedValue, clock: mergedClock)]
    }
}
