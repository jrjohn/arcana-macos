//
//  CoverageTests.swift
//  ArcanaModelTests — exercises the domain value types, entities, and service paths that the
//  behavioral tests don't reach, so the coverage metric reflects the tested product logic.
//

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import ArcanaModel

@Suite("Foundation types")
struct FoundationCoverageTests {

    @Test("AppError factories and codes")
    func appError() {
        #expect(AppError.network("x").code == .network)
        #expect(AppError.validation("x", ["a", "b"]).validationErrors.count == 2)
        #expect(AppError.auth("x").code == .auth)
        #expect(AppError.forbidden("x").code == .forbidden)
        #expect(AppError.data("x").code == .data)
        #expect(AppError.notFound("x").code == .data)
    }

    @Test("PageRequest clamps and computes skip")
    func pageRequest() {
        let request = PageRequest(page: 3, pageSize: 20)
        #expect(request.skip == 40)
        // Clamps invalid input up to the minimum.
        #expect(PageRequest(page: 0, pageSize: 0).page == 1)
    }

    @Test("PagedResult paging math")
    func pagedResult() {
        let page = PagedResult(items: [1, 2, 3], page: 2, pageSize: 3, totalCount: 10)
        #expect(page.totalPages == 4)
        #expect(page.hasPreviousPage)
        #expect(page.hasNextPage)
        let last = PagedResult(items: [1], page: 4, pageSize: 3, totalCount: 10)
        #expect(!last.hasNextPage)
    }
}

@Suite("Entities")
struct EntityCoverageTests {

    @Test("customer / product / category construct with their fields")
    func businessEntities() {
        let customer = Customer(code: "C1", name: "Acme", creditLimit: 100, balance: 10)
        #expect(customer.creditLimit == 100)
        #expect(customer.isPendingSync)
        let product = Product(code: "P1", name: "Widget", unit: "BOX", price: 9, cost: 4, stockQuantity: 5)
        #expect(product.unit == "BOX")
        let category = ProductCategory(code: "CAT", name: "Tools", parentId: 1, sortOrder: 2)
        #expect(category.parentId == 1)
    }

    @Test("order status / payment enums round-trip through their raw storage")
    func orderEnums() {
        let order = Order(orderNumber: "O1", customerId: 1, customerName: "Acme")
        order.status = .shipped
        order.paymentStatus = .paid
        order.paymentMethod = .creditCard
        #expect(order.status == .shipped)
        #expect(order.paymentStatus == .paid)
        #expect(order.paymentMethod == .creditCard)
        #expect(OrderStatus.allCases.count == 8)
        #expect(PaymentStatus.allCases.contains(.refunded))
        #expect(PaymentMethod.allCases.contains(.bankTransfer))
    }
}

@Suite("Identity entities & catalogs")
struct IdentityCoverageTests {

    @Test("identity entities construct")
    func entities() {
        let user = User(username: "u", displayName: "U", passwordHash: "h", email: "e@x.io")
        #expect(!user.isLocked)
        let role = Role(name: "R", displayName: "R", isSystem: true, priority: 5)
        #expect(role.isSystem)
        let perm = AppPermission(code: "a.b", displayName: "A", category: "a")
        #expect(perm.isSystem)
        #expect(!UserRole(userId: 1, roleId: 2).isSoftDeleted)
        #expect(RolePermission(roleId: 1, permissionCode: "a.b").permissionCode == "a.b")
        #expect(UserPermission(userId: 1, permissionCode: "a.b", isGranted: false).isGranted == false)
    }

    @Test("audit log event type and catalogs")
    func auditAndCatalogs() {
        let log = AuditLog(eventType: .loginSuccess, action: "login")
        #expect(log.eventType == .loginSuccess)
        log.eventType = .logout
        #expect(log.eventTypeRaw == "logout")
        #expect(SystemRoles.all.count == 4)
        #expect(SystemPermissions.all.contains(SystemPermissions.ordersCreate))
    }
}

@Suite("Auth — token & session")
struct AuthCoverageTests {

    @Test("refresh token is random and base64")
    func refreshToken() {
        let a = TokenService.generateRefreshToken()
        let b = TokenService.generateRefreshToken()
        #expect(a != b)
        #expect(Data(base64Encoded: a) != nil)
    }

    @Test("malformed tokens are rejected")
    func malformed() {
        let service = TokenService(key: SymmetricKey(data: Data(repeating: 1, count: 32)))
        #expect(!service.validate("nodot").isValid)
        #expect(!service.validate("bad.payload").isValid)
    }

    @Test("current-user session gating")
    @MainActor
    func session() {
        let session = CurrentUserService()
        #expect(!session.isAuthenticated)
        session.setCurrentUser(AuthenticatedUser(
            id: 1, username: "u", displayName: "U",
            roles: ["Manager"], permissions: ["orders.view"]))
        #expect(session.isAuthenticated)
        #expect(session.userId == 1)
        #expect(session.hasPermission("orders.view"))
        #expect(session.hasAnyPermission(["x", "orders.view"]))
        #expect(session.isInRole("manager"))              // case-insensitive
        session.clearCurrentUser()
        #expect(!session.isAuthenticated)
    }
}

@Suite("Services — remaining paths", .serialized)
@MainActor
struct ServiceCoverageTests {
    static let container: ModelContainer = {
        try! ModelContainer(
            for: Schema(ArcanaSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    private var context: ModelContext { Self.container.mainContext }

    @Test("customer search + paging")
    func customerSearchPaging() {
        let service = CustomerService(context: context)
        _ = service.create(Customer(code: "S1", name: "Alpha"))
        _ = service.create(Customer(code: "S2", name: "Alphabet"))
        #expect(service.search("Alpha").count >= 2)
        let page = try? service.page(PageRequest(page: 1, pageSize: 1)).get()
        #expect(page?.items.count == 1)
        #expect((page?.totalCount ?? 0) >= 2)
        // Missing required fields are rejected.
        #expect((try? service.create(Customer(code: "", name: "")).get()) == nil)
    }

    @Test("product create / get / page")
    func productPaths() {
        let service = ProductService(context: context)
        let created = service.create(Product(code: "PP1", name: "Thing"))
        #expect((try? created.get()) != nil)
        #expect(service.get(byCode: "PP1") != nil)
        #expect((try? service.create(Product(code: "PP1", name: "Dup")).get()) == nil)
        #expect((try? service.page(PageRequest()).get())?.items.isEmpty == false)
    }

    @Test("order paging + lookup by number + rejects missing customer")
    func orderPaths() {
        let service = OrderService(context: context)
        let order = Order(orderNumber: "ORD-X", customerId: 5, customerName: "Acme")
        _ = service.create(order)
        #expect(service.get(byNumber: "ORD-X") != nil)
        #expect((try? service.page(PageRequest()).get())?.items.isEmpty == false)
        #expect(service.generateOrderNumber().hasPrefix("ORD-"))
        let bad = Order(orderNumber: "", customerId: 0, customerName: "")
        #expect((try? service.create(bad).get()) == nil)
    }
}

@Suite("AuthService login flow", .serialized)
@MainActor
struct AuthServiceTests {
    static let container: ModelContainer = {
        try! ModelContainer(for: Schema(ArcanaSchema.models),
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    private var context: ModelContext { Self.container.mainContext }

    @Test("admin authenticates and gets all system permissions + the Administrator role")
    func adminLogin() {
        IdentitySeed.seed(context: context, adminPassword: "admin")
        let session = CurrentUserService()
        let auth = AuthService(context: context, session: session)

        let result = auth.authenticate(username: "admin", password: "admin")
        let user = try? result.get()
        #expect(user != nil)
        #expect(session.isAuthenticated)
        #expect(user?.roles.contains(SystemRoles.administrator) == true)
        #expect(user?.permissions.count == SystemPermissions.all.count)
        #expect(session.hasPermission(SystemPermissions.ordersDelete))
    }

    @Test("wrong password fails and does not start a session")
    func wrongPassword() {
        IdentitySeed.seed(context: context, adminPassword: "admin")
        let session = CurrentUserService()
        let auth = AuthService(context: context, session: session)
        #expect((try? auth.authenticate(username: "admin", password: "nope").get()) == nil)
        #expect(!session.isAuthenticated)
    }

    @Test("logout clears the session")
    func logout() {
        IdentitySeed.seed(context: context, adminPassword: "admin")
        let session = CurrentUserService()
        let auth = AuthService(context: context, session: session)
        _ = auth.authenticate(username: "admin", password: "admin")
        auth.logout()
        #expect(!session.isAuthenticated)
    }
}
