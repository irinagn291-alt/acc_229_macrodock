import SwiftUI

struct WishRow: Identifiable, Equatable {
    var id: String { pennant.barcode }
    let pennant: WishPennant
    let product: CargoProduct
}

/// Role in MVVM-C: Wish ledger ViewModel. Barcode unique. Coordinator assigns onSelectProduct.
@MainActor
@Observable
final class WishLedgerViewModel {
    var rows: [WishRow] = []
    var onSelectProduct: ((CargoProduct) -> Void)?
    var onAddCargo: (() -> Void)?

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    func refresh() async {
        do {
            let pennants = try await store.wishPennants()
            let products = try await store.loadProducts(barcodes: pennants.map(\.barcode))
            rows = pennants.compactMap { pennant in
                guard let product = products[pennant.barcode] else { return nil }
                return WishRow(pennant: pennant, product: product)
            }
        } catch {
            rows = []
        }
    }

    func drop(_ row: WishRow) {
        Task {
            try? await store.deleteWish(barcode: row.pennant.barcode)
            await refresh()
        }
    }
}

struct WishLedgerView: View {
    @Bindable var model: WishLedgerViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty {
                    TideEmptyState(
                        image: "mdk_EmptyWish",
                        headline: "NO PENNANTS",
                        line: "The wish ledger is empty. Hoist a product from search or the hatch.",
                        actionTitle: "Search the quay",
                        action: { model.onAddCargo?() }
                    )
                } else {
                    List {
                        ForEach(model.rows) { row in
                            Button {
                                model.onSelectProduct?(row.product)
                            } label: {
                                CargoRow(product: row.product)
                            }
                            .listRowBackground(TidePalette.surface)
                            .swipeActions {
                                Button("Drop", role: .destructive) { model.drop(row) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("WISH PENNANTS")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
    }
}
