import SwiftUI

/// Role in MVVM-C: Goals ViewModel. Validates tide targets. Coordinator assigns replay/reset closures.
@MainActor
@Observable
final class QuayGoalsViewModel {
    var kcalText = ""
    var proteinText = ""
    var carbsText = ""
    var fatText = ""
    var isSaving = false
    var fault: String?
    var confirmReset = false
    var onReplayOnboarding: (() -> Void)?
    var onReset: (() -> Void)?

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    func refresh() async {
        let targets = (try? await store.loadTargets()) ?? .harbourDefault
        kcalText = TideFormat.kcalText(targets.kcal)
        proteinText = TideFormat.macroText(targets.protein)
        carbsText = TideFormat.macroText(targets.carbs)
        fatText = TideFormat.macroText(targets.fat)
    }

    var canSave: Bool { parsed() != nil && !isSaving }

    func save() {
        guard let targets = parsed() else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.saveTargets(targets)
                HapticBeacon.commit()
                fault = nil
            } catch {
                fault = "The tide book would not take the new targets."
            }
        }
    }

    func resetHold() {
        Task {
            do {
                try await store.resetAllData()
                await refresh()
                onReset?()
            } catch {
                fault = "The hold could not be cleared."
            }
        }
    }

    private func parsed() -> TideTargets? {
        guard let kcal = TideFormat.parseGrams(kcalText), kcal >= 800, kcal <= 6000,
              let protein = TideFormat.parseGrams(proteinText), protein > 0, protein <= 500,
              let carbs = TideFormat.parseGrams(carbsText), carbs > 0, carbs <= 500,
              let fat = TideFormat.parseGrams(fatText), fat > 0, fat <= 500
        else { return nil }
        return TideTargets(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }
}

struct QuayGoalsView: View {
    @Bindable var model: QuayGoalsViewModel
    @State private var showContact = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BerthMetrics.space(2)) {
                    Text("TIDE GOALS")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                    field("Energy kcal", text: $model.kcalText)
                    field("Protein g", text: $model.proteinText)
                    field("Carbs g", text: $model.carbsText)
                    field("Fat g", text: $model.fatText)
                    if let fault = model.fault {
                        Text(fault)
                            .font(SignalType.log)
                            .foregroundStyle(TidePalette.accent)
                    }
                    Button("Save tide") { model.save() }
                        .buttonStyle(HarborActionStyle())
                        .disabled(!model.canSave)
                    Button("Replay first watch") { model.onReplayOnboarding?() }
                        .buttonStyle(HarborActionStyle())
                    Button("Clear the entire hold") { model.confirmReset = true }
                        .buttonStyle(HarborActionStyle(destructive: true))
                    Button("Contact the dock office") { showContact = true }
                        .font(SignalType.cargo)
                        .foregroundStyle(TidePalette.ink)
                        .frame(minHeight: BerthMetrics.tap)
                    Text("Nutrition data is credited to Open Food Facts, a public database. MacroDock is a personal food log, not medical advice.")
                        .font(SignalType.signal)
                        .foregroundStyle(TidePalette.muted)
                }
                .padding(BerthMetrics.space(2))
            }
            .scrollDismissesKeyboard(.interactively)
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("GOALS")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
            .confirmationDialog("Clear every lading, wish, stock and restock row?", isPresented: $model.confirmReset, titleVisibility: .visible) {
                Button("Clear the hold", role: .destructive) { model.resetHold() }
                Button("Keep cargo", role: .cancel) {}
            }
            .sheet(isPresented: $showContact) {
                ContactWebSheet()
            }
        }
        .tint(TidePalette.ink)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.ink)
                .padding(BerthMetrics.space(1))
                .frame(minHeight: BerthMetrics.tap)
                .background(TidePalette.surface)
                .accessibilityLabel(title)
        }
    }
}
