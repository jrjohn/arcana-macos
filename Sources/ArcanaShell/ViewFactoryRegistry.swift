//
//  ViewFactoryRegistry.swift
//  ArcanaShell — the compiled-in replacement for the Windows XAML type resolver.
//
//  On Windows a contributed view was a `Type` the XAML parser instantiated (via
//  AssemblyLoadContext + Activator.CreateInstance). macOS plugins are static Swift modules,
//  so instead each registers a SwiftUI view factory keyed by view id, and the shell resolves
//  a view id to a concrete view through this registry.
//

import SwiftUI

@MainActor
public final class ViewFactoryRegistry {
    private var factories: [String: () -> AnyView] = [:]

    public init() {}

    /// Registers a SwiftUI view factory for a view id.
    public func register(_ viewId: String, _ factory: @escaping () -> AnyView) {
        factories[viewId] = factory
    }

    /// Resolves a view id to a view instance (nil if none registered).
    public func make(_ viewId: String) -> AnyView? {
        factories[viewId]?()
    }

    public func hasView(_ viewId: String) -> Bool {
        factories[viewId] != nil
    }

    public var registeredIds: [String] {
        Array(factories.keys)
    }
}
