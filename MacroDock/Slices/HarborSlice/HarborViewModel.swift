import Foundation

/// Role in MVVM-C: Harbour Today ViewModel. Exposes @Observable state and closure navigation only.
@MainActor
@Observable
final class HarborViewModel {
    var onOpenSearch: (() -> Void)?
    var onOpenScan: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onOpenPlan: (() -> Void)?
    var onOpenWish: (() -> Void)?
    var onOpenGoals: (() -> Void)?
    var onOpenHold: (() -> Void)?
    var onSelectCrate: ((String) -> Void)?

    var voyageDay: VoyageDay = .today
    var targets: TideTargets = .harbourDefault
    var eaten: [LadingEntry] = []
    var products: [String: CargoProduct] = [:]
    var lowStock: [HoldStock] = []
    var crates: [HoldCrate] = []
    var totals = ManifestTotals(kcal: 0, protein: nil, carbs: nil, fat: nil)
    var highlightedID: String?
    var showSuccess = false

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    func refresh() async {
        voyageDay = .today
        do {
            targets = try await store.loadTargets() ?? .harbourDefault
            eaten = try await store.entries(voyageDay: voyageDay, eaten: true)
            let map = try await store.loadProducts(barcodes: eaten.map(\.barcode))
            products = map
            totals = ManifestTotals.aggregate(entries: eaten, products: map)
            let stock = try await store.allStock()
            let stockProducts = try await store.loadProducts(barcodes: stock.map(\.barcode))
            crates = stock.map { item in
                HoldCrate(
                    barcode: item.barcode,
                    name: stockProducts[item.barcode]?.name ?? item.barcode,
                    grams: item.grams,
                    isLow: item.isLow
                )
            }
            lowStock = stock.filter(\.isLow)
        } catch {
            eaten = []
            totals = ManifestTotals(kcal: 0, protein: nil, carbs: nil, fat: nil)
        }
    }

    func entries(for slot: WatchSlot) -> [LadingEntry] {
        eaten.filter { $0.slot == slot }
    }

    func slotEnergy(_ slot: WatchSlot) -> Double {
        ManifestTotals.aggregate(entries: entries(for: slot), products: products).kcal
    }

    func flashSuccess() {
        showSuccess = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            showSuccess = false
        }
    }
}
