//
//  Support.swift
//  ArcanaPlugins — shared helpers for the runtime service implementations.
//

import Foundation
import ArcanaPluginContracts

/// A `Disposable` that runs a closure exactly once on `dispose()`.
public final class CallbackDisposable: Disposable, @unchecked Sendable {
    private let lock = NSLock()
    private var onDispose: (@Sendable () -> Void)?

    public init(_ onDispose: @escaping @Sendable () -> Void) {
        self.onDispose = onDispose
    }

    public func dispose() {
        lock.lock()
        let callback = onDispose
        onDispose = nil
        lock.unlock()
        callback?()
    }
}
