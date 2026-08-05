//
//  FeatureViews.swift
//  ArcanaShell — placeholder content views resolved through the ViewFactoryRegistry.
//  P5 replaces the module placeholders with real Customer / Order / Product feature views.
//

import SwiftUI
import ArcanaPlugins

/// Shown when a tab's view id has no registered factory.
struct MissingViewPlaceholder: View {
    let viewId: String
    var body: some View {
        ContentUnavailableView(
            "View not available",
            systemImage: "questionmark.square.dashed",
            description: Text("No view is registered for “\(viewId)”."))
    }
}

/// The Home landing view.
struct HomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to Arcana")
                .font(.largeTitle.bold())
            Text("A local-first, plugin-everything workspace.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A simple titled placeholder standing in for a feature module's list page.
struct SimpleListPlaceholder: View {
    let title: String
    let systemImage: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text("Module content arrives in P5.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Lists the registered plugins and their live state (a small management surface).
struct PluginManagerView: View {
    let manager: PluginManager
    var body: some View {
        List(manager.allPlugins(), id: \.metadata.id) { plugin in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.metadata.name).font(.headline)
                    Text(plugin.metadata.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(plugin.state == .active ? "Active" : "\(plugin.state.rawValue)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(plugin.state == .active ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.vertical, 2)
        }
    }
}
