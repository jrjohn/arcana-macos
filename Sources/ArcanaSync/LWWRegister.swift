//
//  LWWRegister.swift
//  ArcanaSync — Swift port of Arcana.Sync.Crdt.LWWRegister / LWWMap (arcana-windows).
//

import Foundation

/// Last-Writer-Wins register CRDT. The most recent write wins; ties break on node id
/// for a deterministic, commutative merge.
public struct LWWRegister<Value: Sendable & Equatable>: Sendable, Equatable {

    public private(set) var value: Value?
    public private(set) var timestamp: Date
    public private(set) var nodeId: String

    public init(value: Value?, timestamp: Date, nodeId: String) {
        self.value = value
        self.timestamp = timestamp
        self.nodeId = nodeId
    }

    /// Whether `(timestamp, nodeId)` strictly dominates the current write.
    private func isNewer(timestamp: Date, nodeId: String) -> Bool {
        timestamp > self.timestamp
            || (timestamp == self.timestamp && nodeId > self.nodeId)
    }

    /// Updates in place if the incoming write is more recent. Returns whether it applied.
    @discardableResult
    public mutating func update(_ newValue: Value?, timestamp: Date, nodeId: String) -> Bool {
        guard isNewer(timestamp: timestamp, nodeId: nodeId) else { return false }
        value = newValue
        self.timestamp = timestamp
        self.nodeId = nodeId
        return true
    }

    /// Merges with another register, keeping the most recent value.
    public func merged(with other: LWWRegister<Value>) -> LWWRegister<Value> {
        if other.dominates(self) {
            return LWWRegister(value: other.value, timestamp: other.timestamp, nodeId: other.nodeId)
        }
        return LWWRegister(value: value, timestamp: timestamp, nodeId: nodeId)
    }

    /// Whether self should win over `base` (more recent, ties broken on node id).
    private func dominates(_ base: LWWRegister<Value>) -> Bool {
        timestamp > base.timestamp
            || (timestamp == base.timestamp && nodeId > base.nodeId)
    }
}

/// A JSON-representable field value — the Swift stand-in for the C# `object?` that
/// `LWWMap` stored. Being a closed enum keeps the map `Sendable` and `Codable`.
public enum SyncValue: Sendable, Equatable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported SyncValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Last-Writer-Wins map for field-level conflict resolution: each field carries its own
/// timestamp, so two concurrent edits to *different* fields both survive a merge.
public struct LWWMap: Sendable, Equatable {

    public private(set) var fields: [String: LWWRegister<SyncValue>]

    public init() {
        fields = [:]
    }

    /// Sets (or updates, if newer) a field's value.
    public mutating func set(_ field: String, _ value: SyncValue, timestamp: Date, nodeId: String) {
        if var existing = fields[field] {
            existing.update(value, timestamp: timestamp, nodeId: nodeId)
            fields[field] = existing
        } else {
            fields[field] = LWWRegister(value: value, timestamp: timestamp, nodeId: nodeId)
        }
    }

    /// Gets a field's current value, if present.
    public func get(_ field: String) -> SyncValue? {
        fields[field]?.value
    }

    /// Merges with another map, resolving each field independently by LWW.
    public func merged(with other: LWWMap) -> LWWMap {
        var result = LWWMap()
        for key in Set(fields.keys).union(other.fields.keys) {
            switch (fields[key], other.fields[key]) {
            case let (mine?, theirs?):
                result.fields[key] = mine.merged(with: theirs)
            case let (mine?, nil):
                result.fields[key] = mine
            case let (nil, theirs?):
                result.fields[key] = theirs
            case (nil, nil):
                break
            }
        }
        return result
    }
}
