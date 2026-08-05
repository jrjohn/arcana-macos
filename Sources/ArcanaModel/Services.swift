//
//  Services.swift
//  ArcanaModel — the SwiftData schema, domain services (Customer / Product / Order), and
//  the first-launch identity seed. Services are `@MainActor` (SwiftData `ModelContext` is
//  main-actor here), return `AppResult`, and honor soft-delete + `isPendingSync` on write.
//

import Foundation
import SwiftData

/// The full model schema (all `@Model` types), and an in-memory container helper for tests.
public enum ArcanaSchema {
    public static let models: [any PersistentModel.Type] = [
        Customer.self, Product.self, ProductCategory.self, Order.self, OrderItem.self,
        User.self, Role.self, AppPermission.self, UserRole.self, RolePermission.self,
        UserPermission.self, AuditLog.self,
    ]

    /// A container backed by memory (for previews / tests / a fresh run).
    @MainActor
    public static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

// MARK: - Customer

@MainActor
public struct CustomerService {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func create(_ customer: Customer) -> AppResult<Customer> {
        guard !customer.code.isEmpty, !customer.name.isEmpty else {
            return .failure(.validation("Customer code and name are required"))
        }
        if codeExists(customer.code) { return .failure(.validation("Customer code '\(customer.code)' already exists")) }
        customer.isPendingSync = true
        context.insert(customer)
        return save(customer)
    }

    public func get(byCode code: String) -> Customer? {
        try? context.fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.code == code && !$0.isSoftDeleted })).first
    }

    public func codeExists(_ code: String) -> Bool {
        get(byCode: code) != nil
    }

    public func search(_ term: String, maxResults: Int = 20) -> [Customer] {
        var descriptor = FetchDescriptor<Customer>(
            predicate: #Predicate { !$0.isSoftDeleted && ($0.name.contains(term) || $0.code.contains(term)) },
            sortBy: [SortDescriptor(\.name)])
        descriptor.fetchLimit = maxResults
        return (try? context.fetch(descriptor)) ?? []
    }

    public func page(_ request: PageRequest) -> AppResult<PagedResult<Customer>> {
        let filter = FetchDescriptor<Customer>(predicate: #Predicate { !$0.isSoftDeleted })
        let total = (try? context.fetchCount(filter)) ?? 0
        var descriptor = FetchDescriptor<Customer>(predicate: #Predicate { !$0.isSoftDeleted }, sortBy: [SortDescriptor(\.code)])
        descriptor.fetchLimit = request.pageSize
        descriptor.fetchOffset = request.skip
        do {
            let items = try context.fetch(descriptor)
            return .success(PagedResult(items: items, page: request.page, pageSize: request.pageSize, totalCount: total))
        } catch { return .failure(.data("\(error)")) }
    }

    public func softDelete(_ customer: Customer) -> AppResult<Void> {
        customer.isSoftDeleted = true
        customer.isPendingSync = true
        do { try context.save(); return .success(()) } catch { return .failure(.data("\(error)")) }
    }

    private func save(_ customer: Customer) -> AppResult<Customer> {
        do { try context.save(); return .success(customer) } catch { return .failure(.data("\(error)")) }
    }
}

// MARK: - Product

@MainActor
public struct ProductService {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func create(_ product: Product) -> AppResult<Product> {
        guard !product.code.isEmpty, !product.name.isEmpty else {
            return .failure(.validation("Product code and name are required"))
        }
        if get(byCode: product.code) != nil {
            return .failure(.validation("Product code '\(product.code)' already exists"))
        }
        product.isPendingSync = true
        context.insert(product)
        do { try context.save(); return .success(product) } catch { return .failure(.data("\(error)")) }
    }

    public func get(byCode code: String) -> Product? {
        try? context.fetch(FetchDescriptor<Product>(predicate: #Predicate { $0.code == code && !$0.isSoftDeleted })).first
    }

    public func page(_ request: PageRequest) -> AppResult<PagedResult<Product>> {
        let total = (try? context.fetchCount(FetchDescriptor<Product>(predicate: #Predicate { !$0.isSoftDeleted }))) ?? 0
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { !$0.isSoftDeleted }, sortBy: [SortDescriptor(\.code)])
        descriptor.fetchLimit = request.pageSize
        descriptor.fetchOffset = request.skip
        do {
            let items = try context.fetch(descriptor)
            return .success(PagedResult(items: items, page: request.page, pageSize: request.pageSize, totalCount: total))
        } catch { return .failure(.data("\(error)")) }
    }
}

// MARK: - Order

@MainActor
public struct OrderService {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func create(_ order: Order) -> AppResult<Order> {
        guard order.customerId > 0 else { return .failure(.validation("Order requires a customer")) }
        if order.orderNumber.isEmpty { order.orderNumber = generateOrderNumber() }
        for (index, item) in order.items.enumerated() { item.lineNumber = index + 1 }
        order.calculateTotals()
        order.isPendingSync = true
        context.insert(order)
        do { try context.save(); return .success(order) } catch { return .failure(.data("\(error)")) }
    }

    public func get(byNumber number: String) -> Order? {
        try? context.fetch(FetchDescriptor<Order>(predicate: #Predicate { $0.orderNumber == number && !$0.isSoftDeleted })).first
    }

    public func changeStatus(_ order: Order, to status: OrderStatus) -> AppResult<Order> {
        order.status = status
        order.isPendingSync = true
        do { try context.save(); return .success(order) } catch { return .failure(.data("\(error)")) }
    }

    public func page(_ request: PageRequest) -> AppResult<PagedResult<Order>> {
        let total = (try? context.fetchCount(FetchDescriptor<Order>(predicate: #Predicate { !$0.isSoftDeleted }))) ?? 0
        var descriptor = FetchDescriptor<Order>(predicate: #Predicate { !$0.isSoftDeleted },
                                                 sortBy: [SortDescriptor(\.orderDate, order: .reverse)])
        descriptor.fetchLimit = request.pageSize
        descriptor.fetchOffset = request.skip
        do {
            let items = try context.fetch(descriptor)
            return .success(PagedResult(items: items, page: request.page, pageSize: request.pageSize, totalCount: total))
        } catch { return .failure(.data("\(error)")) }
    }

    /// Generates `ORD-yyyyMMdd-####`, the sequence being the next order count.
    public func generateOrderNumber(now: Date = Date()) -> String {
        let count = (try? context.fetchCount(FetchDescriptor<Order>())) ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "ORD-\(formatter.string(from: now))-\(String(format: "%04d", count + 1))"
    }
}

// MARK: - Identity seed

public enum IdentitySeed {
    /// Seeds the system permission catalog, the Administrator role (with all permissions),
    /// and an initial admin user — idempotent. Returns the admin user.
    @MainActor
    @discardableResult
    public static func seed(context: ModelContext, hasher: PasswordHasher = PasswordHasher(),
                            adminPassword: String = "admin") -> User {
        // Permissions.
        for code in SystemPermissions.all where (try? context.fetch(
            FetchDescriptor<AppPermission>(predicate: #Predicate { $0.code == code })))?.isEmpty ?? true {
            context.insert(AppPermission(code: code, displayName: code, category: String(code.prefix(while: { $0 != "." }))))
        }

        // Administrator role + all permission grants (role id 1 by convention on first seed).
        let adminRoleName = SystemRoles.administrator
        let adminRole: Role
        if let existing = try? context.fetch(FetchDescriptor<Role>(predicate: #Predicate { $0.name == adminRoleName })).first {
            adminRole = existing
        } else {
            adminRole = Role(name: SystemRoles.administrator, displayName: "Administrator", isSystem: true, priority: 100)
            context.insert(adminRole)
            for code in SystemPermissions.all {
                context.insert(RolePermission(roleId: 1, permissionCode: code))
            }
        }

        // Admin user.
        let admin: User
        if let existing = try? context.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.username == "admin" })).first {
            admin = existing
        } else {
            admin = User(username: "admin", displayName: "Administrator",
                         passwordHash: hasher.hash(adminPassword), isActive: true)
            context.insert(admin)
            context.insert(UserRole(userId: 1, roleId: 1))
        }

        try? context.save()
        return admin
    }
}
