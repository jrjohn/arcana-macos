//
//  OrderDetailView.swift
//  ArcanaShell — the editable order detail: customer + status + payment, line items with
//  add / remove / quantity / discount, and live-recomputed totals.
//

import SwiftUI
import SwiftData
import ArcanaModel

struct OrderDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var order: Order

    @Query(filter: #Predicate<Customer> { !$0.isSoftDeleted }, sort: \Customer.code)
    private var customers: [Customer]
    @Query(filter: #Predicate<Product> { $0.isActive && !$0.isSoftDeleted }, sort: \Product.code)
    private var products: [Product]

    @State private var saved = false

    var body: some View {
        Form {
            Section("Order") {
                LabeledContent("Number", value: order.orderNumber)
                Picker("Customer", selection: customerBinding) {
                    Text("— none —").tag(0)
                    ForEach(customers) { Text($0.name).tag($0.persistentModelID.hashValue) }
                }
                Picker("Status", selection: statusBinding) {
                    ForEach(OrderStatus.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Payment", selection: paymentBinding) {
                    ForEach(PaymentMethod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }

            Section("Items") {
                if order.items.isEmpty {
                    Text("No line items yet — add a product below.")
                        .foregroundStyle(.secondary).font(.callout)
                }
                ForEach(order.items.sorted { $0.lineNumber < $1.lineNumber }) { item in
                    OrderItemRow(item: item) { recalculate() }
                }
                Menu {
                    ForEach(products) { product in
                        Button("\(product.name) — \(product.price, format: .currency(code: "USD"))") {
                            addItem(product)
                        }
                    }
                } label: {
                    Label("Add product", systemImage: "plus.circle")
                }
            }

            Section("Totals") {
                LabeledContent("Subtotal", value: order.subtotal, format: .currency(code: "USD"))
                HStack {
                    Text("Tax rate %")
                    Spacer()
                    TextField("", text: decimalText($order.taxRate, onCommit: recalculate))
                        .frame(width: 70).multilineTextAlignment(.trailing)
                }
                LabeledContent("Tax", value: order.taxAmount, format: .currency(code: "USD"))
                HStack {
                    Text("Shipping")
                    Spacer()
                    TextField("", text: decimalText($order.shippingCost, onCommit: recalculate))
                        .frame(width: 90).multilineTextAlignment(.trailing)
                }
                LabeledContent {
                    Text(order.totalAmount, format: .currency(code: "USD")).font(.headline)
                } label: {
                    Text("Total").font(.headline)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    save()
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                }
            }
        }
        .navigationTitle(order.orderNumber)
    }

    // MARK: - Bindings

    private var statusBinding: Binding<OrderStatus> {
        Binding(get: { order.status }, set: { order.status = $0; markDirty() })
    }
    private var paymentBinding: Binding<PaymentMethod> {
        Binding(get: { order.paymentMethod }, set: { order.paymentMethod = $0; markDirty() })
    }
    private var customerBinding: Binding<Int> {
        Binding(
            get: { customers.first { $0.persistentModelID.hashValue == order.customerId }?.persistentModelID.hashValue ?? 0 },
            set: { newHash in
                if let picked = customers.first(where: { $0.persistentModelID.hashValue == newHash }) {
                    order.customerId = newHash
                    order.customerName = picked.name
                    markDirty()
                }
            })
    }

    private func decimalText(_ value: Binding<Decimal>, onCommit: @escaping () -> Void) -> Binding<String> {
        Binding(
            get: { NSDecimalNumber(decimal: value.wrappedValue).stringValue },
            set: { value.wrappedValue = Decimal(string: $0) ?? value.wrappedValue; onCommit() })
    }

    // MARK: - Actions

    private func addItem(_ product: Product) {
        let nextLine = (order.items.map(\.lineNumber).max() ?? 0) + 1
        let item = OrderItem(lineNumber: nextLine, productId: product.persistentModelID.hashValue,
                             productCode: product.code, productName: product.name,
                             unit: product.unit, quantity: 1, unitPrice: product.price)
        item.order = order
        order.items.append(item)
        recalculate()
    }

    private func recalculate() {
        order.calculateTotals()
        markDirty()
    }

    private func markDirty() {
        saved = false
        order.isPendingSync = true
    }

    private func save() {
        order.calculateTotals()
        do {
            try context.save()
            saved = true
        } catch {
            saved = false
        }
    }
}

/// One editable order line: quantity / unit price / discount, with a live line total.
struct OrderItemRow: View {
    @Bindable var item: OrderItem
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.productName).font(.callout)
                Text(item.productCode).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            field("Qty", $item.quantity, width: 52)
            field("Price", $item.unitPrice, width: 72)
            field("Disc%", $item.discountPercent, width: 52)
            Text(item.lineTotal, format: .currency(code: "USD"))
                .font(.callout.monospacedDigit())
                .frame(width: 84, alignment: .trailing)
            Button(role: .destructive) {
                item.order?.items.removeAll { $0 === item }
                onEdit()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func field(_ label: String, _ value: Binding<Decimal>, width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField("", text: Binding(
                get: { NSDecimalNumber(decimal: value.wrappedValue).stringValue },
                set: { value.wrappedValue = Decimal(string: $0) ?? value.wrappedValue; onEdit() }))
                .frame(width: width)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
        }
    }
}
