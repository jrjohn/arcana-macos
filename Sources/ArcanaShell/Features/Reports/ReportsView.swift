//
//  ReportsView.swift
//  ArcanaShell — a real dashboard computed from live SwiftData: totals, revenue, orders by
//  status (charted), and low-stock products.
//

import SwiftUI
import SwiftData
import Charts
import ArcanaModel

struct ReportsView: View {
    @Query(filter: #Predicate<Customer> { !$0.isSoftDeleted }) private var customers: [Customer]
    @Query(filter: #Predicate<Product> { !$0.isSoftDeleted }) private var products: [Product]
    @Query(filter: #Predicate<Order> { !$0.isSoftDeleted }) private var orders: [Order]

    private var revenue: Decimal { orders.reduce(Decimal(0)) { $0 + $1.totalAmount } }
    private var lowStock: [Product] { products.filter { $0.minStockLevel > 0 && $0.stockQuantity <= $0.minStockLevel } }
    private var ordersByStatus: [(status: OrderStatus, count: Int)] {
        OrderStatus.allCases.map { status in (status, orders.filter { $0.status == status }.count) }
            .filter { $0.count > 0 }
    }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reports").font(.largeTitle.bold())

                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(title: "Customers", value: "\(customers.count)", systemImage: "person.2", tint: .blue)
                    MetricCard(title: "Products", value: "\(products.count)", systemImage: "shippingbox", tint: .orange)
                    MetricCard(title: "Orders", value: "\(orders.count)", systemImage: "cart", tint: .green)
                    MetricCard(title: "Revenue", value: revenue.formatted(.currency(code: "USD")), systemImage: "dollarsign.circle", tint: .purple)
                }

                if !ordersByStatus.isEmpty {
                    GroupBox("Orders by status") {
                        Chart(ordersByStatus, id: \.status) { row in
                            BarMark(x: .value("Status", row.status.rawValue.capitalized),
                                    y: .value("Count", row.count))
                            .foregroundStyle(by: .value("Status", row.status.rawValue.capitalized))
                        }
                        .chartLegend(.hidden)
                        .frame(height: 220)
                        .padding(.top, 4)
                    }
                }

                GroupBox("Low stock (\(lowStock.count))") {
                    if lowStock.isEmpty {
                        Text("All products are above their minimum stock level.")
                            .foregroundStyle(.secondary).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(lowStock) { product in
                                HStack {
                                    Label(product.name, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                    Spacer()
                                    Text("\(product.stockQuantity.formatted()) / min \(product.minStockLevel.formatted())")
                                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.title.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
