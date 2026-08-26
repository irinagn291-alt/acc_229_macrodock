import Algorithms
import SwiftUI

struct ManifestRow: Identifiable, Equatable {
    var id: String { entry.id }
    let entry: LadingEntry
    let product: CargoProduct
}

/// Role in MVVM-C: Log ViewModel. Groups by watch using swift-algorithms. Coordinator assigns onAddCargo.
@MainActor
@Observable
final class ManifestLogViewModel {
    var voyageDay: VoyageDay = .today
    var rows: [ManifestRow] = []
    var pendingDelete: ManifestRow?
    var highlightedID: String?
    var onAddCargo: (() -> Void)?

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    var groups: [(WatchSlot, [ManifestRow])] {
        let sorted = rows.sorted { $0.entry.slot.rank < $1.entry.slot.rank }
        return sorted.chunked(on: \.entry.slot).map { ($0.0, Array($0.1)) }
    }

    func refresh() async {
        do {
            let entries = try await store.entries(voyageDay: voyageDay, eaten: true)
            let products = try await store.loadProducts(barcodes: entries.map(\.barcode))
            rows = entries.compactMap { entry in
                guard let product = products[entry.barcode] else { return nil }
                return ManifestRow(entry: entry, product: product)
            }
        } catch {
            rows = []
        }
    }

    func shiftDay(_ delta: Int) {
        voyageDay = voyageDay.adding(days: delta)
        Task { await refresh() }
    }

    func delete(_ row: ManifestRow) {
        Task {
            do {
                try await store.deleteLading(id: row.entry.id)
                await refresh()
            } catch {
                return
            }
        }
    }

    func slotTotal(_ rows: [ManifestRow]) -> Double {
        rows.reduce(0) { partial, row in
            partial + (PortionRigging.portion(product: row.product, grams: row.entry.grams).kcal ?? 0)
        }
    }
}

struct ManifestLogView: View {
    @Bindable var model: ManifestLogViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: BerthMetrics.space(2)) {
                HStack {
                    Button("Previous day") { model.shiftDay(-1) }
                        .font(SignalType.log)
                        .foregroundStyle(TidePalette.ink)
                        .frame(minWidth: BerthMetrics.tap, minHeight: BerthMetrics.tap)
                        .accessibilityLabel("Previous voyage day")
                    Spacer()
                    Text(model.voyageDay.date(), style: .date)
                        .font(SignalType.berth)
                        .foregroundStyle(TidePalette.ink)
                    Spacer()
                    Button("Next day") { model.shiftDay(1) }
                        .font(SignalType.log)
                        .foregroundStyle(TidePalette.ink)
                        .frame(minWidth: BerthMetrics.tap, minHeight: BerthMetrics.tap)
                        .accessibilityLabel("Next voyage day")
                }
                if model.rows.isEmpty {
                    TideEmptyState(
                        image: "mdk_EmptyLog",
                        headline: "EMPTY MANIFEST",
                        line: "Nothing eaten on this voyage day. Search the quay to log cargo.",
                        actionTitle: "Search the quay",
                        action: { model.onAddCargo?() }
                    )
                } else {
                    List {
                        ForEach(model.groups, id: \.0) { slot, rows in
                            Section {
                                ForEach(rows) { row in
                                    ManifestLine(row: row)
                                        .listRowBackground(row.id == model.highlightedID ? TidePalette.accent : TidePalette.surface)
                                        .swipeActions {
                                            Button("Delete", role: .destructive) {
                                                model.pendingDelete = row
                                            }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(slot.title.uppercased())
                                        .font(SignalType.signal)
                                        .kerning(SignalType.headerKerning)
                                    Spacer()
                                    Text("\(TideFormat.kcalText(model.slotTotal(rows))) kcal")
                                        .font(SignalType.signal)
                                }
                                .foregroundStyle(TidePalette.muted)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.horizontal, BerthMetrics.space(2))
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MANIFEST")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
            .confirmationDialog("Strike this lading from the manifest?", isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Strike it", role: .destructive) {
                    if let row = model.pendingDelete {
                        model.delete(row)
                    }
                    model.pendingDelete = nil
                }
                Button("Keep it", role: .cancel) { model.pendingDelete = nil }
            }
        }
        .tint(TidePalette.ink)
    }
}

struct ManifestLine: View {
    let row: ManifestRow

    var body: some View {
        HStack(spacing: BerthMetrics.space(1)) {
            CargoThumb(product: row.product)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.product.name)
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
                    .lineLimit(1)
                Text("\(TideFormat.gramsText(row.entry.grams)) g")
                    .font(SignalType.signal)
                    .foregroundStyle(TidePalette.muted)
            }
            Spacer(minLength: BerthMetrics.space(1))
            Text("\(TideFormat.macroText(PortionRigging.portion(product: row.product, grams: row.entry.grams).kcal)) kcal")
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
                .lineLimit(1)
        }
        .frame(minHeight: BerthMetrics.tap)
    }
}
