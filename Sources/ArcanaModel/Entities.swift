//
//  Entities.swift
//  ArcanaModel — the business domain models (Customer / Product / Order), ported to
//  SwiftData @Model. Every entity carries the audit + soft-delete + sync field groups the
//  Windows BaseEntity provided. Money/quantity use `Decimal` (never Double).
//

import Foundation
import SwiftData

/// Decimal rounding helper (banker's-plain to a scale), for money math.
public extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

@Model
public final class Customer {
    @Attribute(.unique) public var code: String
    public var name: String
    public var contactName: String?
    public var phone: String?
    public var email: String?
    public var address: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var country: String?
    public var taxId: String?
    public var creditLimit: Decimal
    public var balance: Decimal
    public var isActive: Bool
    public var notes: String?

    // Audit / soft-delete / sync (BaseEntity field groups).
    public var createdAt: Date
    public var modifiedAt: Date?
    public var isSoftDeleted: Bool
    public var syncId: UUID
    public var isPendingSync: Bool

    public init(code: String, name: String, creditLimit: Decimal = 0, balance: Decimal = 0, isActive: Bool = true) {
        self.code = code
        self.name = name
        self.creditLimit = creditLimit
        self.balance = balance
        self.isActive = isActive
        self.createdAt = Date()
        self.isSoftDeleted = false
        self.syncId = UUID()
        self.isPendingSync = true
    }
}

@Model
public final class ProductCategory {
    @Attribute(.unique) public var code: String
    public var name: String
    public var parentId: Int?
    public var sortOrder: Int
    public var createdAt: Date
    public var isSoftDeleted: Bool

    public init(code: String, name: String, parentId: Int? = nil, sortOrder: Int = 0) {
        self.code = code
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.isSoftDeleted = false
    }
}

@Model
public final class Product {
    @Attribute(.unique) public var code: String   // SKU
    public var name: String
    public var productDescription: String?
    public var categoryId: Int?
    public var unit: String
    public var price: Decimal
    public var cost: Decimal
    public var stockQuantity: Decimal
    public var minStockLevel: Decimal
    public var maxStockLevel: Decimal
    public var isActive: Bool
    public var barcode: String?
    public var weight: Decimal?

    public var createdAt: Date
    public var modifiedAt: Date?
    public var isSoftDeleted: Bool
    public var syncId: UUID
    public var isPendingSync: Bool

    public init(code: String, name: String, unit: String = "PCS", price: Decimal = 0, cost: Decimal = 0,
                stockQuantity: Decimal = 0, isActive: Bool = true) {
        self.code = code
        self.name = name
        self.unit = unit
        self.price = price
        self.cost = cost
        self.stockQuantity = stockQuantity
        self.minStockLevel = 0
        self.maxStockLevel = 0
        self.isActive = isActive
        self.createdAt = Date()
        self.isSoftDeleted = false
        self.syncId = UUID()
        self.isPendingSync = true
    }
}

public enum OrderStatus: String, Sendable, Codable, CaseIterable {
    case draft, pending, confirmed, processing, shipped, delivered, completed, cancelled
}

public enum PaymentStatus: String, Sendable, Codable, CaseIterable {
    case unpaid, partialPaid, paid, refunded
}

public enum PaymentMethod: String, Sendable, Codable, CaseIterable {
    case cash, creditCard, bankTransfer, check, credit
}

@Model
public final class Order {
    @Attribute(.unique) public var orderNumber: String
    public var orderDate: Date
    public var customerId: Int
    public var customerName: String
    public var statusRaw: String
    public var paymentStatusRaw: String
    public var paymentMethodRaw: String
    public var subtotal: Decimal
    public var taxRate: Decimal
    public var taxAmount: Decimal
    public var discountAmount: Decimal
    public var shippingCost: Decimal
    public var totalAmount: Decimal
    public var paidAmount: Decimal
    public var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \OrderItem.order) public var items: [OrderItem]

    public var createdAt: Date
    public var modifiedAt: Date?
    public var isSoftDeleted: Bool
    public var syncId: UUID
    public var isPendingSync: Bool

    public var status: OrderStatus {
        get { OrderStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    public var paymentStatus: PaymentStatus {
        get { PaymentStatus(rawValue: paymentStatusRaw) ?? .unpaid }
        set { paymentStatusRaw = newValue.rawValue }
    }
    public var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .cash }
        set { paymentMethodRaw = newValue.rawValue }
    }

    public init(orderNumber: String, customerId: Int, customerName: String, taxRate: Decimal = 5) {
        self.orderNumber = orderNumber
        self.orderDate = Date()
        self.customerId = customerId
        self.customerName = customerName
        self.statusRaw = OrderStatus.draft.rawValue
        self.paymentStatusRaw = PaymentStatus.unpaid.rawValue
        self.paymentMethodRaw = PaymentMethod.cash.rawValue
        self.subtotal = 0
        self.taxRate = taxRate
        self.taxAmount = 0
        self.discountAmount = 0
        self.shippingCost = 0
        self.totalAmount = 0
        self.paidAmount = 0
        self.items = []
        self.createdAt = Date()
        self.isSoftDeleted = false
        self.syncId = UUID()
        self.isPendingSync = true
    }

    /// Recomputes subtotal / tax / total from the line items (faithful to the C# CalculateTotals).
    public func calculateTotals() {
        subtotal = items.reduce(Decimal(0)) { $0 + $1.lineTotal }
        taxAmount = (subtotal * taxRate / 100).rounded(2)
        totalAmount = subtotal + taxAmount + shippingCost - discountAmount
    }
}

@Model
public final class OrderItem {
    public var lineNumber: Int
    public var productId: Int
    public var productCode: String
    public var productName: String
    public var unit: String
    public var quantity: Decimal
    public var unitPrice: Decimal
    public var discountPercent: Decimal
    public var notes: String?
    public var order: Order?

    public init(lineNumber: Int, productId: Int, productCode: String, productName: String,
                unit: String = "PCS", quantity: Decimal, unitPrice: Decimal, discountPercent: Decimal = 0) {
        self.lineNumber = lineNumber
        self.productId = productId
        self.productCode = productCode
        self.productName = productName
        self.unit = unit
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
    }

    /// Line total = qty × price × (1 − discount%/100), rounded to 2 (matches the C# computed).
    public var lineTotal: Decimal {
        (quantity * unitPrice * (1 - discountPercent / 100)).rounded(2)
    }
}
