//
//  Messaging.swift
//  ArcanaPlugins — MessageBus / EventAggregator / SharedStateStore implementations.
//  Topics are keyed by type via `ObjectIdentifier`; subscriptions are held strongly and
//  removed only through the returned `Disposable` (faithful to the C# behavior).
//

import Foundation
import ArcanaPluginContracts

/// In-memory typed message bus with a single-handler request/response channel.
public final class MessageBusImpl: MessageBus, @unchecked Sendable {

    private struct PairKey: Hashable {
        let request: ObjectIdentifier
        let response: ObjectIdentifier
    }

    private let lock = NSLock()
    private var subscribers: [ObjectIdentifier: [UUID: @Sendable (Any) async -> Void]] = [:]
    private var requestHandlers: [PairKey: @Sendable (Any) async -> Any] = [:]

    public init() {}

    public func publish<Message: Sendable>(_ message: Message) async {
        // Snapshot handlers in a synchronous helper — the lock must not be held across `await`.
        for handler in handlers(for: ObjectIdentifier(Message.self)) {
            await handler(message)
        }
    }

    private func handlers(for key: ObjectIdentifier) -> [@Sendable (Any) async -> Void] {
        lock.lock(); defer { lock.unlock() }
        return subscribers[key]?.values.map { $0 } ?? []
    }

    @discardableResult
    public func subscribe<Message: Sendable>(
        _ type: Message.Type, _ handler: @escaping @Sendable (Message) -> Void
    ) -> any Disposable {
        addSubscriber(type) { value in
            if let message = value as? Message { handler(message) }
        }
    }

    @discardableResult
    public func subscribe<Message: Sendable>(
        _ type: Message.Type, _ handler: @escaping @Sendable (Message) async -> Void
    ) -> any Disposable {
        addSubscriber(type) { value in
            if let message = value as? Message { await handler(message) }
        }
    }

    private func addSubscriber<Message>(
        _ type: Message.Type, _ wrapped: @escaping @Sendable (Any) async -> Void
    ) -> any Disposable {
        let key = ObjectIdentifier(Message.self)
        let id = UUID()
        lock.lock(); subscribers[key, default: [:]][id] = wrapped; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.subscribers[key]?[id] = nil; self.lock.unlock()
        }
    }

    public func request<Request: Sendable, Response: Sendable>(
        _ request: Request, responseType: Response.Type, timeout: Duration?
    ) async -> Response? {
        let key = PairKey(request: ObjectIdentifier(Request.self), response: ObjectIdentifier(Response.self))
        guard let handler = requestHandler(for: key) else { return nil }

        guard let timeout else {
            return await handler(request) as? Response
        }

        return await withTaskGroup(of: Response?.self) { group in
            group.addTask { await handler(request) as? Response }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @discardableResult
    public func registerHandler<Request: Sendable, Response: Sendable>(
        _ requestType: Request.Type, responseType: Response.Type,
        _ handler: @escaping @Sendable (Request) async -> Response
    ) -> any Disposable {
        let key = PairKey(request: ObjectIdentifier(Request.self), response: ObjectIdentifier(Response.self))
        let wrapped: @Sendable (Any) async -> Any = { value in
            await handler(value as! Request)
        }
        lock.lock(); requestHandlers[key] = wrapped; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.requestHandlers[key] = nil; self.lock.unlock()
        }
    }

    private func requestHandler(for key: PairKey) -> (@Sendable (Any) async -> Any)? {
        lock.lock(); defer { lock.unlock() }
        return requestHandlers[key]
    }
}

/// In-memory synchronous event aggregator, keyed by event type.
public final class EventAggregatorImpl: EventAggregator, @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [ObjectIdentifier: [UUID: @Sendable (Any) -> Void]] = [:]

    public init() {}

    public func publish<Event: ApplicationEvent>(_ event: Event) {
        let key = ObjectIdentifier(Event.self)
        lock.lock(); let handlers = subscribers[key]?.values.map { $0 } ?? []; lock.unlock()
        for handler in handlers { handler(event) }
    }

    @discardableResult
    public func subscribe<Event: ApplicationEvent>(
        _ type: Event.Type, _ handler: @escaping @Sendable (Event) -> Void
    ) -> any Disposable {
        let key = ObjectIdentifier(Event.self)
        let id = UUID()
        let wrapped: @Sendable (Any) -> Void = { value in
            if let event = value as? Event { handler(event) }
        }
        lock.lock(); subscribers[key, default: [:]][id] = wrapped; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.subscribers[key]?[id] = nil; self.lock.unlock()
        }
    }
}

/// In-memory cross-plugin key/value store with change notification.
public final class SharedStateStoreImpl: SharedStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: any Sendable] = [:]
    private var observers: [String: [UUID: @Sendable (Any?) -> Void]] = [:]

    public init() {}

    public func get<Value: Sendable>(_ key: String, as type: Value.Type) -> Value? {
        lock.lock(); defer { lock.unlock() }
        return storage[key] as? Value
    }

    public func set<Value: Sendable>(_ key: String, _ value: Value) {
        lock.lock()
        storage[key] = value
        let handlers = observers[key]?.values.map { $0 } ?? []
        lock.unlock()
        for handler in handlers { handler(value) }
    }

    @discardableResult
    public func remove(_ key: String) -> Bool {
        lock.lock()
        let existed = storage.removeValue(forKey: key) != nil
        let handlers = observers[key]?.values.map { $0 } ?? []
        lock.unlock()
        for handler in handlers { handler(nil) }
        return existed
    }

    public func containsKey(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[key] != nil
    }

    @discardableResult
    public func onChange<Value: Sendable>(
        _ key: String, as type: Value.Type, _ handler: @escaping @Sendable (Value?) -> Void
    ) -> any Disposable {
        let id = UUID()
        let wrapped: @Sendable (Any?) -> Void = { value in
            handler(value as? Value)
        }
        lock.lock(); observers[key, default: [:]][id] = wrapped; lock.unlock()
        return CallbackDisposable { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.observers[key]?[id] = nil; self.lock.unlock()
        }
    }
}
