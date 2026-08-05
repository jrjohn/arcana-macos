//
//  ShellView.swift
//  ArcanaShell — the SwiftUI shell chrome: NavigationSplitView sidebar + document tab strip
//  + content + status bar. Thin renderers over `ShellModel`.
//

import SwiftUI

public struct ShellView: View {
    @Bindable var shell: ShellModel
    var theme: ThemeStore

    public init(shell: ShellModel, theme: ThemeStore) {
        self.shell = shell
        self.theme = theme
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(shell: shell)
        } detail: {
            VStack(spacing: 0) {
                TabStripView(shell: shell)
                Divider()
                content
                Divider()
                StatusBarView(shell: shell)
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        if let id = shell.selectedTabId, let tab = shell.tabs.first(where: { $0.id == id }) {
            shell.content(forViewId: tab.viewId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HomeView()
        }
    }
}

struct SidebarView: View {
    @Bindable var shell: ShellModel

    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(shell.sidebarItems) { item in
                Label(item.title, systemImage: item.systemImage).tag(item.id)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Arcana")
        .frame(minWidth: 200)
    }

    private var sidebarSelection: Binding<String?> {
        Binding(
            get: { shell.sidebarSelection },
            set: { newValue in
                guard let id = newValue,
                      let item = shell.sidebarItems.first(where: { $0.id == id }) else { return }
                shell.sidebarSelection = id
                shell.selectSidebar(item)
            })
    }
}

struct TabStripView: View {
    @Bindable var shell: ShellModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(shell.tabs) { tab in
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.title).lineLimit(1)
                        Button {
                            shell.closeTab(id: tab.id)
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(shell.selectedTabId == tab.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { shell.selectedTabId = tab.id }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 38)
    }
}

struct StatusBarView: View {
    @Bindable var shell: ShellModel
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Text(shell.statusMessage).font(.caption)
            Spacer()
            if let user = shell.currentUser.currentUser {
                Label(user.displayName, systemImage: "person.circle").font(.caption).foregroundStyle(.secondary)
            }
            Label("Online", systemImage: "wifi").font(.caption).foregroundStyle(.secondary)
            Text(now, style: .time).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.bar)
        .onReceive(clock) { now = $0 }
    }
}
