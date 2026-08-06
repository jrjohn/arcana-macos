//
//  OrdersView.swift
//  ArcanaShell — the Order module master-detail (the Windows flagship): a live order list on
//  the left, an editable order detail on the right (customer, line items, live totals, status).
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ArcanaModel

// MARK: - Master (list) + detail split

struct OrdersView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Order> { !$0.isSoftDeleted },
           sort: \Order.orderDate, order: .reverse)
    private var orders: [Order]
    @State private var selectedID: PersistentIdentifier?
    @State private var isExporting = false
    @Environment(DialogService.self) private var dialogs: DialogService?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        newOrder()
                    } label: {
                        Label("New Order", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Spacer()
                    Button { isExporting = true } label: { Image(systemName: "square.and.arrow.up") }
                        .help("Export to CSV")
                    Button(role: .destructive) {
                        confirmDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedID == nil)
                }
                .padding(8)
                Divider()
                List(orders, selection: $selectedID) { order in
                    OrderRow(order: order).tag(order.persistentModelID)
                }
                .listStyle(.inset)
                .onAppear {
                    if selectedID == nil, ProcessInfo.processInfo.environment["ARCANA_SHOT"] != nil {
                        selectedID = orders.first { $0.orderNumber.contains("SAMPLE") }?.persistentModelID ?? orders.first?.persistentModelID
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 360)

            Group {
                if let id = selectedID, let order = orders.first(where: { $0.persistentModelID == id }) {
                    OrderDetailView(order: order)
                } else {
                    ContentUnavailableView("Select an order",
                                           systemImage: "cart",
                                           description: Text("Choose an order on the left, or create a new one."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity)
        }
        .fileExporter(isPresented: $isExporting,
                      document: CSVDocument(Exporter.ordersCSV(orders)),
                      contentType: .commaSeparatedText,
                      defaultFilename: "orders") { result in
            if case .success = result { toasts?.show("Exported orders.csv", systemImage: "square.and.arrow.up") }
        }
    }

    private func newOrder() {
        let service = OrderService(context: context)
        let order = Order(orderNumber: "", customerId: 0, customerName: "New Customer", taxRate: 5)
        if case .success(let saved) = service.create(order) {
            selectedID = saved.persistentModelID
        } else {
            // create() rejects a missing customer; make a draft directly so the user can fill it in.
            order.orderNumber = service.generateOrderNumber()
            context.insert(order)
            try? context.save()
            selectedID = order.persistentModelID
        }
    }

    private func confirmDelete() {
        guard let id = selectedID, let order = orders.first(where: { $0.persistentModelID == id }) else { return }
        let number = order.orderNumber
        let doDelete: () -> Void = {
            order.isSoftDeleted = true
            order.isPendingSync = true
            try? context.save()
            selectedID = nil
            toasts?.show("Deleted \(number)", systemImage: "trash")
        }
        if let dialogs {
            dialogs.confirm("Delete order?", message: "“\(number)” will be removed.",
                            confirmTitle: "Delete", destructive: true, action: doDelete)
        } else {
            doDelete()
        }
    }
}

// MARK: - List row

struct OrderRow: View {
    let order: Order
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.orderNumber).font(.headline)
                Text(order.customerName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(order.totalAmount, format: .currency(code: "USD"))
                    .font(.subheadline.monospacedDigit())
                OrderStatusBadge(status: order.status)
            }
        }
        .padding(.vertical, 2)
    }
}

struct OrderStatusBadge: View {
    let status: OrderStatus
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status {
        case .draft, .pending: return .secondary
        case .confirmed, .processing: return .blue
        case .shipped, .delivered: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }
}
