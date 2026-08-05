//
//  SyncView.swift
//  ArcanaShell — the Sync screen: shows this node's CRDT sync state, drives a local sync
//  pass over pending changes, and demonstrates conflict resolution.
//

import SwiftUI
import SwiftData
import ArcanaSync

struct SyncView: View {
    @Environment(\.modelContext) private var context
    @State private var engine = SyncEngine()
    @State private var pending = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                GroupBox("This node") {
                    LabeledContent("Node ID", value: engine.nodeId)
                    LabeledContent("State", value: engine.state == .syncing ? "Syncing…" : "Idle")
                    LabeledContent("Pending changes", value: "\(pending)")
                    LabeledContent("Last sync") {
                        Text(engine.lastSyncTime.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")
                    }
                }

                HStack {
                    Button {
                        engine.syncNow(context: context)
                        pending = engine.pendingCount(context: context)
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.state == .syncing)

                    Button {
                        engine.demonstrateConflict()
                    } label: {
                        Label("Demonstrate conflict resolution", systemImage: "arrow.triangle.merge")
                    }
                }

                if !engine.log.isEmpty {
                    GroupBox("Activity") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.callout.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .onAppear { pending = engine.pendingCount(context: context) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("CRDT Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.title2.bold())
            Text("Local-first: every change advances a vector clock. No remote peer is connected yet — a sync pass advances this node's clocks and drains the pending queue; the same clocks + resolver will drive real multi-node merges once a transport is added.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
