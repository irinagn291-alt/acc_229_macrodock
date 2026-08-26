import SwiftUI

struct HoldRow: Identifiable, Equatable {
    var id: String { stock.barcode }
    let stock: HoldStock
    let product: CargoProduct
    let onRestock: Bool
}

/// Role in MVVM-C: Pantry inventory ViewModel. Stock is independent of the wish ledger.
@MainActor
@Observable
final class HoldStockViewModel {
    var rows: [HoldRow] = []
    var restockOnly = false
    var gramsDraft: [String: String] = [:]
    var onSelectProduct: ((CargoProduct) -> Void)?

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    var visible: [HoldRow] {
        restockOnly ? rows.filter(\.onRestock) : rows
    }

    func refresh() async {
        do {
            let stock = try await store.allStock()
            let restock = Set((try await store.restockIndents()).map(\.barcode))
            let products = try await store.loadProducts(barcodes: stock.map(\.barcode))
            rows = stock.compactMap { item in
                guard let product = products[item.barcode] else { return nil }
                return HoldRow(stock: item, product: product, onRestock: restock.contains(item.barcode))
            }
            for row in rows {
                gramsDraft[row.id] = TideFormat.gramsText(row.stock.grams)
            }
        } catch {
            rows = []
        }
    }

    func saveGrams(_ row: HoldRow) {
        guard let grams = gramsDraft[row.id].flatMap(PortionRigging.validatedGrams) else { return }
        Task {
            try? await store.setStock(barcode: row.stock.barcode, grams: grams, threshold: row.stock.lowThreshold)
            HapticBeacon.commit()
            await refresh()
        }
    }

    func pushRestock(_ row: HoldRow) {
        Task {
            try? await store.addRestock(barcode: row.stock.barcode)
            await refresh()
        }
    }

    func dropRestock(_ row: HoldRow) {
        Task {
            try? await store.deleteRestock(barcode: row.stock.barcode)
            await refresh()
        }
    }

    func stowLocalShelf() {
        Task {
            for product in LocalHoldShelf.all {
                try? await store.saveProduct(product)
                if (try? await store.stock(barcode: product.barcode)) == nil {
                    try? await store.setStock(barcode: product.barcode, grams: 250)
                }
            }
            await refresh()
        }
    }
}

struct HoldStockView: View {
    @Bindable var model: HoldStockViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: BerthMetrics.space(2)) {
                Image("mdk_TwistHero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .accessibilityHidden(true)
                Text("HOLD STOCK")
                    .font(SignalType.berth)
                    .kerning(SignalType.headerKerning)
                    .foregroundStyle(TidePalette.ink)
                Text("Grams on hand. Logging cargo lowers the crate. Restock is not the wish ledger.")
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.muted)
                    .multilineTextAlignment(.center)
                Toggle("Restock list only", isOn: $model.restockOnly)
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
                    .tint(TidePalette.accent)
                    .padding(.horizontal, BerthMetrics.space(2))
                    .frame(minHeight: BerthMetrics.tap)
                if model.visible.isEmpty {
                    TideEmptyState(
                        image: "mdk_TwistHero",
                        headline: model.restockOnly ? "RESTOCK CLEAR" : "EMPTY HOLD",
                        line: model.restockOnly
                            ? "Nothing waits on the restock list."
                            : "Set grams on a product after you berth it, or open a crate on the harbour.",
                        actionTitle: model.restockOnly ? "Show all crates" : "Stow local shelf",
                        action: {
                            if model.restockOnly {
                                model.restockOnly = false
                            } else {
                                model.stowLocalShelf()
                            }
                        }
                    )
                } else {
                    List {
                        ForEach(model.visible) { row in
                            VStack(alignment: .leading, spacing: BerthMetrics.space(1)) {
                                Button {
                                    model.onSelectProduct?(row.product)
                                } label: {
                                    HStack {
                                        CargoRow(product: row.product)
                                        if row.stock.isLow {
                                            Text("LOW")
                                                .font(SignalType.signal)
                                                .kerning(1.4)
                                                .foregroundStyle(TidePalette.ink)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(TidePalette.accent)
                                        }
                                    }
                                }
                                HStack {
                                    TextField("Grams", text: Binding(
                                        get: { model.gramsDraft[row.id] ?? "" },
                                        set: { model.gramsDraft[row.id] = $0 }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .font(SignalType.cargo)
                                    .foregroundStyle(TidePalette.ink)
                                    .padding(BerthMetrics.space(1))
                                    .frame(minHeight: BerthMetrics.tap)
                                    .background(TidePalette.background)
                                    .accessibilityLabel("Stock grams for \(row.product.name)")
                                    Button("Stow") { model.saveGrams(row) }
                                        .font(SignalType.cargo)
                                        .foregroundStyle(TidePalette.ink)
                                        .frame(minWidth: BerthMetrics.tap, minHeight: BerthMetrics.tap)
                                    Button(row.onRestock ? "Drop indent" : "Restock") {
                                        if row.onRestock {
                                            model.dropRestock(row)
                                        } else {
                                            model.pushRestock(row)
                                        }
                                    }
                                    .font(SignalType.signal)
                                    .foregroundStyle(TidePalette.ink)
                                    .frame(minHeight: BerthMetrics.tap)
                                    .accessibilityLabel(row.onRestock ? "Remove from restock list" : "Add to restock list")
                                }
                            }
                            .listRowBackground(TidePalette.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .padding(.top, BerthMetrics.space(2))
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PANTRY HOLD")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
    }
}
