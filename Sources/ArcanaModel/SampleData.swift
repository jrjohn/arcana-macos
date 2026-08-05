//
//  SampleData.swift
//  ArcanaModel — idempotent dev/demo seed so the feature screens have content to work with
//  (a few customers + products + one sample order). Safe to call on every launch.
//

import Foundation
import SwiftData

public enum SampleData {

    /// Seeds a handful of customers, products, and one order if the store is empty.
    @MainActor
    public static func seed(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Customer>())) ?? 0
        guard existing == 0 else { return }

        let customers = [
            Customer(code: "C001", name: "Acme Corporation", creditLimit: 50_000),
            Customer(code: "C002", name: "Globex Inc.", creditLimit: 30_000),
            Customer(code: "C003", name: "Umbrella Ltd.", creditLimit: 80_000),
        ]
        customers.forEach { context.insert($0) }

        let products = [
            Product(code: "P001", name: "Widget", unit: "PCS", price: Decimal(string: "19.99")!, cost: Decimal(string: "8.00")!, stockQuantity: 500),
            Product(code: "P002", name: "Gadget", unit: "PCS", price: Decimal(string: "49.50")!, cost: Decimal(string: "22.00")!, stockQuantity: 200),
            Product(code: "P003", name: "Gizmo", unit: "BOX", price: Decimal(string: "120.00")!, cost: Decimal(string: "70.00")!, stockQuantity: 60),
            Product(code: "P004", name: "Sprocket", unit: "PCS", price: Decimal(string: "4.25")!, cost: Decimal(string: "1.50")!, stockQuantity: 5_000),
        ]
        products.forEach { context.insert($0) }

        // One sample order for Acme with two lines.
        let order = Order(orderNumber: "ORD-SAMPLE-0001", customerId: 1, customerName: "Acme Corporation", taxRate: 5)
        order.items = [
            OrderItem(lineNumber: 1, productId: 1, productCode: "P001", productName: "Widget",
                      quantity: 10, unitPrice: Decimal(string: "19.99")!),
            OrderItem(lineNumber: 2, productId: 2, productCode: "P002", productName: "Gadget",
                      quantity: 3, unitPrice: Decimal(string: "49.50")!, discountPercent: 10),
        ]
        order.status = .confirmed
        order.calculateTotals()
        context.insert(order)

        try? context.save()
    }
}
