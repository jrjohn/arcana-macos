//
//  CoreMenuPlugin.swift
//  ArcanaShell — the shell's own chrome plugin, ported from the Windows CoreMenuPlugin.
//  It contributes the top-level main-menu roots (File / Business / Reports / Help) that
//  feature plugins hang their items under via `parentId`.
//

import ArcanaPluginContracts
import ArcanaPlugins

public final class CoreMenuPlugin: ArcanaPluginBase {

    public override var metadata: PluginMetadata {
        PluginMetadata(
            id: "arcana.core.menu",
            name: "Core Menu",
            version: "1.0.0",
            description: "Provides the application's top-level menu structure",
            author: "Arcana",
            type: .menu)
    }

    public override func registerContributions(_ context: PluginContext) {
        registerMenuItems(
            MenuItemDefinition(id: "menu.file", title: "File", location: .mainMenu, icon: "doc", order: 0),
            MenuItemDefinition(id: "menu.business", title: "Business", location: .mainMenu, icon: "briefcase", order: 10),
            MenuItemDefinition(id: "menu.reports", title: "Reports", location: .mainMenu, icon: "chart.bar", order: 20),
            MenuItemDefinition(id: "menu.help", title: "Help", location: .mainMenu, icon: "questionmark.circle", order: 90))
    }
}
