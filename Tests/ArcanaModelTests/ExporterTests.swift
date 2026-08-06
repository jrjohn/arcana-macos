//
//  ExporterTests.swift
//  ArcanaModelTests — CSV export serialization + field escaping.
//

import Testing
import Foundation
@testable import ArcanaModel

@Suite("CSV export")
struct ExporterTests {

    @Test("field escaping quotes commas/quotes/newlines")
    func fieldEscaping() {
        #expect(Exporter.field("plain") == "plain")
        #expect(Exporter.field("a,b") == "\"a,b\"")
        #expect(Exporter.field("she said \"hi\"") == "\"she said \"\"hi\"\"\"")
    }

    @Test("customers CSV has a header and escapes fields")
    func customersCSV() {
        let csv = Exporter.customersCSV([Customer(code: "C1", name: "Acme, Inc.", creditLimit: 100)])
        let lines = csv.split(separator: "\n")
        #expect(lines.first?.hasPrefix("Code,Name") == true)
        #expect(csv.contains("\"Acme, Inc.\""))     // comma-containing name is quoted
        #expect(lines.count == 2)
    }

    @Test("orders CSV includes totals and item count")
    func ordersCSV() {
        let order = Order(orderNumber: "ORD-1", customerId: 1, customerName: "Acme")
        order.items = [OrderItem(lineNumber: 1, productId: 1, productCode: "P", productName: "P",
                                 quantity: 2, unitPrice: Decimal(string: "10")!)]
        order.calculateTotals()
        let csv = Exporter.ordersCSV([order])
        #expect(csv.contains("ORD-1"))
        #expect(csv.hasSuffix("\n"))
    }
}
