//
//  OrderWindowView.swift
//  ArcanaShell — the content of a popped-out order window (a tear-off document window).
//  Resolves the order from its PersistentIdentifier in the shared model container.
//

import SwiftUI
import SwiftData
import ArcanaModel

struct OrderWindowView: View {
    @Environment(\.modelContext) private var context
    let orderID: PersistentIdentifier?

    var body: some View {
        Group {
            if let id = orderID, let order = context.model(for: id) as? Order {
                OrderDetailView(order: order)
                    .navigationTitle(order.orderNumber)
            } else {
                ContentUnavailableView("Order not found", systemImage: "cart")
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
