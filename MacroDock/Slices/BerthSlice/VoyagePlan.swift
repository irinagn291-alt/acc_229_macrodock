import Algorithms
import SwiftUI

struct PlanRow: Identifiable, Equatable {
    var id: String { entry.id }
    let entry: LadingEntry
    let product: CargoProduct
}

/// Role in MVVM-C: Plan ViewModel. 14-day horizon, windows of 7 via swift-algorithms.
@MainActor
@Observable
final class VoyagePlanViewModel {
    var rows: [PlanRow] = []
    var convertingID: String?
    var onAddCargo: (() -> Void)?

    private let store: HarborStore
    let horizonDays = 14

    init(store: HarborStore) {
        self.store = store
    }

    var weekWindows: [[VoyageDay]] {
        let today = VoyageDay.today
        let days = (1...horizonDays).map { today.adding(days: $0) }
        return days.chunks(ofCount: 7).map { Array($0) }
    }

    func refresh() async {
        do {
            let entries = try await store.plannedEntries(
                from: VoyageDay.today.adding(days: 1),
                through: VoyageDay.today.adding(days: horizonDays)
            )
            let products = try await store.loadProducts(barcodes: entries.map(\.barcode))
            rows = entries.compactMap { entry in
                guard let product = products[entry.barcode] else { return nil }
                return PlanRow(entry: entry, product: product)
            }
        } catch {
            rows = []
        }
    }

    func rows(on day: VoyageDay) -> [PlanRow] {
        rows.filter { $0.entry.voyageDay == day }
    }

    func convert(_ row: PlanRow) {
        guard convertingID == nil else { return }
        convertingID = row.id
        Task {
            defer { convertingID = nil }
            do {
                try await store.markEaten(id: row.entry.id, today: .today)
                HapticBeacon.commit()
                await refresh()
            } catch {
                return
            }
        }
    }
}

struct VoyagePlanView: View {
    @Bindable var model: VoyagePlanViewModel

    var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty {
                    TideEmptyState(
                        image: "mdk_EmptyPlan",
                        headline: "CLEAR HORIZON",
                        line: "Nothing is berthed on the next 14 voyage days.",
                        actionTitle: "Search the quay",
                        action: { model.onAddCargo?() }
                    )
                } else {
                    List {
                        ForEach(model.weekWindows.indices, id: \.self) { index in
                            let window = model.weekWindows[index]
                            Section {
                                ForEach(window, id: \.ordinal) { day in
                                    let dayRows = model.rows(on: day)
                                    if !dayRows.isEmpty {
                                        ForEach(dayRows) { row in
                                            HStack {
                                                ManifestLine(row: ManifestRow(entry: row.entry, product: row.product))
                                                Button("Eat now") { model.convert(row) }
                                                    .font(SignalType.signal)
                                                    .foregroundStyle(TidePalette.ink)
                                                    .frame(minWidth: BerthMetrics.tap, minHeight: BerthMetrics.tap)
                                                    .disabled(model.convertingID == row.id)
                                                    .accessibilityLabel("Convert planned cargo to eaten today")
                                            }
                                            .listRowBackground(TidePalette.surface)
                                        }
                                    }
                                }
                            } header: {
                                Text("WATCH WINDOW \(index + 1)")
                                    .font(SignalType.signal)
                                    .kerning(SignalType.headerKerning)
                                    .foregroundStyle(TidePalette.muted)
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
                    Text("VOYAGE PLAN")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
    }
}
