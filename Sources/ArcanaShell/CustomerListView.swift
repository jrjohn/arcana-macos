//
//  CustomerListView.swift
//  ArcanaShell — a real, SwiftData-backed feature view (the P5 vertical slice): the Customer
//  list, live via @Query, with inline create through CustomerService.
//

import SwiftUI
import SwiftData
import ArcanaModel

struct CustomerListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Customer> { !$0.isSoftDeleted }, sort: \Customer.code)
    private var customers: [Customer]

    @State private var newCode = ""
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Code", text: $newCode).frame(width: 120)
                TextField("Name", text: $newName)
                Button("Add", action: add)
                    .disabled(newCode.isEmpty || newName.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
            Divider()
            if customers.isEmpty {
                ContentUnavailableView("No customers yet", systemImage: "person.2",
                                       description: Text("Add one above to get started."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(customers) { customer in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.name).font(.headline)
                        Text(customer.code).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func add() {
        let result = CustomerService(context: context).create(Customer(code: newCode, name: newName))
        if case .success = result {
            newCode = ""
            newName = ""
        }
    }
}
