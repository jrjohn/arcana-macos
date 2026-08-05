//
//  ModelTests.swift
//  ArcanaModelTests — the domain math, the auth crypto, the RBAC resolver, and the
//  SwiftData-backed services.
//

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import ArcanaModel

@Suite("Order math")
struct OrderMathTests {

    @Test("line total applies quantity, price, and discount, rounded to 2")
    func lineTotal() {
        let item = OrderItem(lineNumber: 1, productId: 1, productCode: "P", productName: "P",
                             quantity: 1, unitPrice: Decimal(string: "5")!, discountPercent: 10)
        #expect(item.lineTotal == Decimal(string: "4.5")!)
    }

    @Test("calculateTotals sums items, taxes, and totals")
    func calculateTotals() {
        let order = Order(orderNumber: "X", customerId: 1, customerName: "Acme", taxRate: 5)
        order.items = [
            OrderItem(lineNumber: 1, productId: 1, productCode: "A", productName: "A",
                      quantity: 2, unitPrice: Decimal(string: "10")!),
            OrderItem(lineNumber: 2, productId: 2, productCode: "B", productName: "B",
                      quantity: 1, unitPrice: Decimal(string: "5")!, discountPercent: 10),
        ]
        order.calculateTotals()
        #expect(order.subtotal == Decimal(string: "24.5")!)     // 20 + 4.5
        #expect(order.taxAmount == Decimal(string: "1.23")!)    // 24.5 * 5% = 1.225 → 1.23
        #expect(order.totalAmount == Decimal(string: "25.73")!)
    }
}

@Suite("Password hashing (PBKDF2)")
struct PasswordHasherTests {
    private let hasher = PasswordHasher()

    @Test("hash then verify round-trips; wrong password fails")
    func roundTrip() {
        let hash = hasher.hash("s3cr3t!")
        #expect(hasher.verify("s3cr3t!", hash: hash))
        #expect(!hasher.verify("wrong", hash: hash))
    }

    @Test("hash string has the version:iterations:salt:hash shape")
    func format() {
        let parts = hasher.hash("x").split(separator: ":")
        #expect(parts.count == 4)
        #expect(parts[0] == "1")
        #expect(parts[1] == "100000")
    }

    @Test("needsRehash flags malformed or weaker hashes")
    func needsRehash() {
        #expect(hasher.needsRehash("garbage"))
        #expect(hasher.needsRehash("1:1000:c2FsdA==:aGFzaA=="))   // fewer iterations
        #expect(!hasher.needsRehash(hasher.hash("ok")))
    }
}

@Suite("Token service (HMAC)")
struct TokenServiceTests {
    private let service = TokenService(key: SymmetricKey(data: Data(repeating: 7, count: 32)))

    @Test("generated token validates and carries the identity")
    func validate() {
        let (token, _) = service.generateAccessToken(userId: 42, username: "neo")
        let result = service.validate(token)
        #expect(result.isValid)
        #expect(result.userId == 42)
        #expect(result.username == "neo")
    }

    @Test("a tampered token fails signature validation")
    func tamper() {
        let (token, _) = service.generateAccessToken(userId: 1, username: "a")
        let tampered = String(token.dropLast()) + (token.hasSuffix("A") ? "B" : "A")
        #expect(!service.validate(tampered).isValid)
    }

    @Test("an expired token is rejected as expired")
    func expiry() {
        let past = Date(timeIntervalSince1970: 1000)
        let (token, _) = service.generateAccessToken(userId: 1, username: "a", now: past)
        let result = service.validate(token, now: past.addingTimeInterval(7200))
        #expect(!result.isValid)
        #expect(result.isExpired)
    }
}

@Suite("RBAC permission resolution")
struct PermissionResolverTests {

    @Test("role permissions union; a direct deny overrides a role grant")
    func unionAndDeny() {
        let roles = [
            RoleGrant(roleName: "Manager", permissions: ["orders.view", "orders.create", "orders.delete"]),
        ]
        let direct = [
            DirectPermission(code: "customers.view", isGranted: true),
            DirectPermission(code: "orders.delete", isGranted: false),   // explicit deny
        ]
        let resolved = PermissionResolver.resolve(roles: roles, direct: direct)
        #expect(resolved.contains("orders.view"))
        #expect(resolved.contains("customers.view"))
        #expect(!resolved.contains("orders.delete"))                    // deny wins
    }

    @Test("expired roles and permissions are filtered out")
    func expiryFiltering() {
        let past = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 5000)
        let roles = [
            RoleGrant(roleName: "Temp", expiresAt: past, permissions: ["orders.view"]),
            RoleGrant(roleName: "Perm", permissions: ["customers.view"]),
        ]
        let direct = [DirectPermission(code: "products.view", isGranted: true, expiresAt: past)]
        let resolved = PermissionResolver.resolve(roles: roles, direct: direct, now: now)
        #expect(resolved == ["customers.view"])
        #expect(PermissionResolver.roleNames(roles, now: now) == ["Perm"])
    }
}

@Suite("SwiftData services", .serialized)
@MainActor
struct ServiceTests {

    // One shared in-memory container for the whole suite. Creating/destroying a container
    // per test races CoreData's async teardown in the parallel test process (SIGTRAP), so
    // the suite runs serialized against a single long-lived container.
    static let container: ModelContainer = {
        try! ModelContainer(
            for: Schema(ArcanaSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    private var context: ModelContext { Self.container.mainContext }

    @Test("customer create de-dupes on code; soft-delete hides from queries")
    func customerLifecycle() throws {
        let service = CustomerService(context: context)

        let created = service.create(Customer(code: "C001", name: "Acme"))
        #expect((try? created.get()) != nil)

        let duplicate = service.create(Customer(code: "C001", name: "Other"))
        #expect((try? duplicate.get()) == nil)                          // rejected

        #expect(service.get(byCode: "C001") != nil)
        if case .success(let customer) = created {
            _ = service.softDelete(customer)
            #expect(service.get(byCode: "C001") == nil)                 // filtered after soft-delete
        }
    }

    @Test("order create generates a number, assigns line numbers, and totals")
    func orderCreate() throws {
        let service = OrderService(context: context)

        let order = Order(orderNumber: "", customerId: 7, customerName: "Acme", taxRate: 5)
        order.items = [OrderItem(lineNumber: 0, productId: 1, productCode: "A", productName: "A",
                                 quantity: 3, unitPrice: Decimal(string: "10")!)]
        let result = service.create(order)
        let saved = try #require(try? result.get())
        #expect(saved.orderNumber.hasPrefix("ORD-"))
        #expect(saved.items.first?.lineNumber == 1)
        #expect(saved.subtotal == Decimal(string: "30")!)
        #expect(saved.status == .draft)

        _ = service.changeStatus(saved, to: .confirmed)
        #expect(saved.status == .confirmed)
    }

    @Test("identity seed creates admin, role, and the permission catalog")
    func seed() throws {
        let admin = IdentitySeed.seed(context: context)
        #expect(admin.username == "admin")

        let permissions = try context.fetch(FetchDescriptor<AppPermission>())
        #expect(permissions.count == SystemPermissions.all.count)

        let roles = try context.fetch(FetchDescriptor<Role>())
        #expect(roles.contains { $0.name == SystemRoles.administrator })

        // The seeded admin password verifies.
        #expect(PasswordHasher().verify("admin", hash: admin.passwordHash))
    }
}
