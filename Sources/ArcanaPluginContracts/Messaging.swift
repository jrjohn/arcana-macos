//
//  Messaging.swift
//  ArcanaPluginContracts — inter-plugin messaging: MessageBus (typed pub/sub +
//  request/response), EventAggregator (synchronous app events), SharedStateStore.
//  Ported from IMessageBus / IEventAggregator / ISharedStateStore.
//
//  As in the C# original, subscriptions are held strongly (no weak refs) and unsubscribe is
//  explicit via the returned `Disposable`; handler errors are swallowed so one bad
//  subscriber can't break the dispatch loop. Topics are the message *type*, not a string.
//

import Foundation

/// Typed publish/subscribe bus with an optional single-handler request/response channel.
public protocol MessageBus: Sendable {
    /// Publishes a message to every subscriber of its type.
    func publish<Message: Sendable>(_ message: Message) async

    /// Subscribes a synchronous handler for a message type.
    @discardableResult
    func subscribe<Message: Sendable>(
        _ type: Message.Type, _ handler: @escaping @Sendable (Message) -> Void
    ) -> any Disposable

    /// Subscribes an asynchronous handler for a message type.
    @discardableResult
    func subscribe<Message: Sendable>(
        _ type: Message.Type, _ handler: @escaping @Sendable (Message) async -> Void
    ) -> any Disposable

    /// Sends a request and awaits the registered handler's response (or `nil` on timeout /
    /// no handler).
    func request<Request: Sendable, Response: Sendable>(
        _ request: Request, responseType: Response.Type, timeout: Duration?
    ) async -> Response?

    /// Registers the single handler for a request/response pair.
    @discardableResult
    func registerHandler<Request: Sendable, Response: Sendable>(
        _ requestType: Request.Type, responseType: Response.Type,
        _ handler: @escaping @Sendable (Request) async -> Response
    ) -> any Disposable
}

/// A cross-cutting application event.
public protocol ApplicationEvent: Sendable {
    var timestamp: Date { get }
    var sourcePluginId: String? { get }
}

/// Synchronous, app-wide event aggregator keyed by event type.
public protocol EventAggregator: Sendable {
    func publish<Event: ApplicationEvent>(_ event: Event)
    @discardableResult
    func subscribe<Event: ApplicationEvent>(
        _ type: Event.Type, _ handler: @escaping @Sendable (Event) -> Void
    ) -> any Disposable
}

/// Cross-plugin key/value store with change notification.
public protocol SharedStateStore: Sendable {
    func get<Value: Sendable>(_ key: String, as type: Value.Type) -> Value?
    func set<Value: Sendable>(_ key: String, _ value: Value)
    @discardableResult
    func remove(_ key: String) -> Bool
    func containsKey(_ key: String) -> Bool
    @discardableResult
    func onChange<Value: Sendable>(
        _ key: String, as type: Value.Type, _ handler: @escaping @Sendable (Value?) -> Void
    ) -> any Disposable
}
