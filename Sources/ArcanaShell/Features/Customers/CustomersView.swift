//
//  CustomersView.swift
//  ArcanaShell — Customer master-detail: a live list + an editable detail (all fields),
//  create / edit / soft-delete, backed by CustomerService + SwiftData.
//

import SwiftUI
import SwiftData
import ArcanaModel

struct CustomersView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Customer> { !$0.isSoftDeleted }, sort: \Customer.code)
    private var customers: [Customer]
    @State private var selectedID: PersistentIdentifier?
    @State private var search = ""

    private var filtered: [Customer] {
        guard !search.isEmpty else { return customers }
        return customers.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button { newCustomer() } label: { Label("New", systemImage: "plus") }
                    Spacer()
                    Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash") }
                        .disabled(selectedID == nil)
                }
                .padding(8)
                Divider()
                List(filtered, selection: $selectedID) { customer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name).font(.headline)
                        Text(customer.code).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(customer.persistentModelID)
                }
                .searchable(text: $search, placement: .sidebar)
                .onAppear {
                    if selectedID == nil, ProcessInfo.processInfo.environment["ARCANA_SHOT"] != nil {
                        selectedID = customers.first?.persistentModelID
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320)

            Group {
                if let id = selectedID, let customer = customers.first(where: { $0.persistentModelID == id }) {
                    CustomerDetailView(customer: customer)
                } else {
                    ContentUnavailableView("Select a customer", systemImage: "person.2",
                                           description: Text("Choose one on the left, or create a new customer."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
    }

    private func newCustomer() {
        let next = (customers.count + 1)
        let customer = Customer(code: String(format: "C%03d", next), name: "New Customer")
        context.insert(customer)
        try? context.save()
        selectedID = customer.persistentModelID
    }

    private func deleteSelected() {
        guard let id = selectedID, let c = customers.first(where: { $0.persistentModelID == id }) else { return }
        c.isSoftDeleted = true; c.isPendingSync = true
        try? context.save()
        selectedID = nil
    }
}

struct CustomerDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var customer: Customer
    @State private var saved = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Code", text: $customer.code).onChange(of: customer.code) { dirty() }
                TextField("Name", text: $customer.name).onChange(of: customer.name) { dirty() }
                Toggle("Active", isOn: $customer.isActive).onChange(of: customer.isActive) { dirty() }
            }
            Section("Contact") {
                TextField("Contact name", text: optional($customer.contactName)).onChange(of: customer.contactName) { dirty() }
                TextField("Phone", text: optional($customer.phone)).onChange(of: customer.phone) { dirty() }
                TextField("Email", text: optional($customer.email)).onChange(of: customer.email) { dirty() }
            }
            Section("Address") {
                TextField("Address", text: optional($customer.address)).onChange(of: customer.address) { dirty() }
                TextField("City", text: optional($customer.city)).onChange(of: customer.city) { dirty() }
                TextField("Country", text: optional($customer.country)).onChange(of: customer.country) { dirty() }
            }
            Section("Account") {
                LabeledContent("Credit limit") { DecimalField(title: "", value: $customer.creditLimit, width: 120, onChange: dirty) }
                LabeledContent("Balance") { DecimalField(title: "", value: $customer.balance, width: 120, onChange: dirty) }
                TextField("Notes", text: optional($customer.notes), axis: .vertical).lineLimit(2...4)
                    .onChange(of: customer.notes) { dirty() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { save() } label: { Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down") }
            }
        }
        .navigationTitle(customer.name)
    }

    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    private func dirty() { saved = false; customer.isPendingSync = true; customer.modifiedAt = Date() }
    private func save() { do { try context.save(); saved = true } catch { saved = false } }
}
