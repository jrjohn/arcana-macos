//
//  Exporter.swift
//  ArcanaModel — pure CSV serialization for the feature lists (used by the shell's file
//  export). Kept here (not in the UI) so it is unit-testable.
//

import Foundation

public enum Exporter {

    /// Escapes a field for CSV (quotes it when it contains a comma, quote, or newline).
    public static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    private static func money(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    public static func customersCSV(_ customers: [Customer]) -> String {
        var lines = [row(["Code", "Name", "Email", "Phone", "City", "CreditLimit", "Balance", "Active"])]
        for c in customers {
            lines.append(row([c.code, c.name, c.email ?? "", c.phone ?? "", c.city ?? "",
                              money(c.creditLimit), money(c.balance), c.isActive ? "yes" : "no"]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func productsCSV(_ products: [Product]) -> String {
        var lines = [row(["Code", "Name", "Unit", "Price", "Cost", "Stock", "MinStock", "Active"])]
        for p in products {
            lines.append(row([p.code, p.name, p.unit, money(p.price), money(p.cost),
                              money(p.stockQuantity), money(p.minStockLevel), p.isActive ? "yes" : "no"]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func ordersCSV(_ orders: [Order]) -> String {
        var lines = [row(["OrderNumber", "Customer", "Status", "Payment", "Subtotal", "Tax", "Total", "Items"])]
        for o in orders {
            lines.append(row([o.orderNumber, o.customerName, o.status.rawValue, o.paymentMethod.rawValue,
                              money(o.subtotal), money(o.taxAmount), money(o.totalAmount), "\(o.items.count)"]))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
