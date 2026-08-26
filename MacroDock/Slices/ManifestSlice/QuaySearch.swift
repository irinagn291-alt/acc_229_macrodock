import SwiftUI

enum QuaySearchPhase: Equatable {
    case idle
    case loading
    case results
    case empty
    case transport
}

/// Role in MVVM-C: Search ViewModel. Debounces, cancels, merges the local shelf. Coordinator assigns onSelectProduct.
@MainActor
@Observable
final class QuaySearchViewModel {
    var query = ""
    var products: [CargoProduct] = []
    var phase: QuaySearchPhase = .idle
    var showSpinner = false
    var onSelectProduct: ((CargoProduct) -> Void)?

    private let store: HarborStore
    private let client: OpenSeaClient
    private var searchTask: Task<Void, Never>?

    init(store: HarborStore, client: OpenSeaClient) {
        self.store = store
        self.client = client
    }

    func updateQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            phase = .idle
            products = []
            showSpinner = false
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await self.runSearch(trimmed)
        }
    }

    func retry() {
        updateQuery(query)
    }

    private func runSearch(_ terms: String) async {
        phase = .loading
        showSpinner = false
        let spinner = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.showSpinner = true
        }
        defer {
            spinner.cancel()
            showSpinner = false
        }
        do {
            let remote = try await client.search(terms: terms)
            if Task.isCancelled { return }
            let merged = Self.merge(remote: remote, local: LocalHoldShelf.matches(terms))
            products = merged
            phase = merged.isEmpty ? .empty : .results
            if merged.isEmpty {
                products = LocalHoldShelf.matches(terms)
                phase = products.isEmpty ? .empty : .results
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            let local = LocalHoldShelf.matches(terms)
            products = local
            phase = local.isEmpty ? .transport : .results
        }
    }

    private static func merge(remote: [CargoProduct], local: [CargoProduct]) -> [CargoProduct] {
        var seen: Set<String> = []
        var result: [CargoProduct] = []
        for product in remote + local {
            if seen.insert(product.barcode).inserted {
                result.append(product)
            }
        }
        return result
    }
}

struct QuaySearchView: View {
    @Bindable var model: QuaySearchViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: BerthMetrics.space(2)) {
                TextField("Name on the quay", text: $model.query)
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
                    .padding(BerthMetrics.space(1))
                    .frame(minHeight: BerthMetrics.tap)
                    .background(TidePalette.surface)
                    .accessibilityLabel("Search cargo by name")
                    .onChange(of: model.query) { _, value in
                        model.updateQuery(value)
                    }
                content
            }
            .padding(BerthMetrics.space(2))
            .background(TidePalette.background)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("QUAY SEARCH")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            Text("Type two letters to sound the quay.")
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .loading:
            if model.showSpinner {
                ProgressView()
                    .tint(TidePalette.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .results:
            List {
                ForEach(Array(model.products.enumerated()), id: \.element.barcode) { index, product in
                    Button {
                        model.onSelectProduct?(product)
                    } label: {
                        CargoRow(product: product)
                    }
                    .listRowBackground(TidePalette.surface)
                    .opacity(1)
                    .animation(TideMotion.curve.delay(Double(index) * 0.03), value: model.products.count)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        case .empty:
            TideEmptyState(
                image: "mdk_EmptySearch",
                headline: "FOG ON THE QUAY",
                line: "No cargo matched that name, even in the local hold.",
                actionTitle: "Clear the glass",
                action: {
                    model.query = ""
                    model.updateQuery("")
                }
            )
        case .transport:
            TideFaultBanner(message: "The open sea would not answer. Check the weather and try again.", retry: model.retry)
        }
    }
}

struct CargoRow: View {
    let product: CargoProduct

    var body: some View {
        HStack(spacing: BerthMetrics.space(1)) {
            CargoThumb(product: product)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
                    .lineLimit(1)
                Text(product.brand ?? "Unmarked hold")
                    .font(SignalType.signal)
                    .foregroundStyle(TidePalette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: BerthMetrics.space(1))
            Text(product.kcal100.map { "\(TideFormat.kcalText($0))/100g" } ?? "unknown")
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
                .lineLimit(1)
        }
        .frame(minHeight: BerthMetrics.tap)
        .contentShape(Rectangle())
    }
}
