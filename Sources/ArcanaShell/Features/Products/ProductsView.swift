//
//  ProductsView.swift
//  ArcanaShell — Product master-detail: a live list + an editable detail (SKU, pricing,
//  stock), create / edit / soft-delete, backed by SwiftData.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ArcanaModel

struct ProductsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Product> { !$0.isSoftDeleted }, sort: \Product.code)
    private var products: [Product]
    @State private var selectedID: PersistentIdentifier?
    @State private var search = ""
    @State private var isExporting = false
    @Environment(DialogService.self) private var dialogs: DialogService?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    private var filtered: [Product] {
        guard !search.isEmpty else { return products }
        return products.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Button { newProduct() } label: { Label("New", systemImage: "plus") }
                        .keyboardShortcut("n", modifiers: .command)
                    Spacer()
                    Button { isExporting = true } label: { Image(systemName: "square.and.arrow.up") }
                        .help("Export to CSV")
                    Button(role: .destructive) { confirmDelete() } label: { Image(systemName: "trash") }
                        .disabled(selectedID == nil)
                }
                .padding(8)
                Divider()
                List(filtered, selection: $selectedID) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline)
                            Text(product.code).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.price, format: .currency(code: "USD")).font(.subheadline.monospacedDigit())
                    }
                    .tag(product.persistentModelID)
                }
                .searchable(text: $search, placement: .sidebar)
                .onAppear {
                    if selectedID == nil, ProcessInfo.processInfo.environment["ARCANA_SHOT"] != nil {
                        selectedID = products.first?.persistentModelID
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 340)

            Group {
                if let id = selectedID, let product = products.first(where: { $0.persistentModelID == id }) {
                    ProductDetailView(product: product)
                } else {
                    ContentUnavailableView("Select a product", systemImage: "shippingbox",
                                           description: Text("Choose one on the left, or create a new product."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .fileExporter(isPresented: $isExporting,
                      document: CSVDocument(Exporter.productsCSV(products)),
                      contentType: .commaSeparatedText,
                      defaultFilename: "products") { result in
            if case .success = result { toasts?.show("Exported products.csv", systemImage: "square.and.arrow.up") }
        }
    }

    private func newProduct() {
        let next = (products.count + 1)
        let product = Product(code: String(format: "P%03d", next), name: "New Product")
        context.insert(product)
        try? context.save()
        selectedID = product.persistentModelID
    }

    private func confirmDelete() {
        guard let id = selectedID, let p = products.first(where: { $0.persistentModelID == id }) else { return }
        let name = p.name
        let doDelete: () -> Void = {
            p.isSoftDeleted = true; p.isPendingSync = true
            try? context.save()
            selectedID = nil
            toasts?.show("Deleted \(name)", systemImage: "trash")
        }
        if let dialogs {
            dialogs.confirm("Delete product?", message: "“\(name)” will be removed.",
                            confirmTitle: "Delete", destructive: true, action: doDelete)
        } else {
            doDelete()
        }
    }
}

struct ProductDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var product: Product
    @State private var saved = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("SKU / Code", text: $product.code).onChange(of: product.code) { dirty() }
                TextField("Name", text: $product.name).onChange(of: product.name) { dirty() }
                TextField("Unit", text: $product.unit).onChange(of: product.unit) { dirty() }
                Toggle("Active", isOn: $product.isActive).onChange(of: product.isActive) { dirty() }
            }
            Section("Pricing") {
                LabeledContent("Price") { DecimalField(title: "", value: $product.price, width: 120, onChange: dirty) }
                LabeledContent("Cost") { DecimalField(title: "", value: $product.cost, width: 120, onChange: dirty) }
                if product.cost > 0 {
                    LabeledContent("Margin", value: margin, format: .percent.precision(.fractionLength(1)))
                }
            }
            Section("Stock") {
                LabeledContent("On hand") { DecimalField(title: "", value: $product.stockQuantity, width: 120, onChange: dirty) }
                LabeledContent("Min level") { DecimalField(title: "", value: $product.minStockLevel, width: 120, onChange: dirty) }
                LabeledContent("Max level") { DecimalField(title: "", value: $product.maxStockLevel, width: 120, onChange: dirty) }
                if product.stockQuantity <= product.minStockLevel && product.minStockLevel > 0 {
                    Label("Below minimum stock level", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { save() } label: { Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down") }
            }
        }
        .navigationTitle(product.name)
    }

    private var margin: Double {
        let price = NSDecimalNumber(decimal: product.price).doubleValue
        let cost = NSDecimalNumber(decimal: product.cost).doubleValue
        guard price > 0 else { return 0 }
        return (price - cost) / price
    }
    private func dirty() { saved = false; product.isPendingSync = true; product.modifiedAt = Date() }
    private func save() { do { try context.save(); saved = true } catch { saved = false } }
}
