import SwiftUI

/// Role in MVVM-C: onboarding ViewModel. Writes targets and the completion flag. Never builds other VMs.
@MainActor
@Observable
final class FirstWatchOnboardingViewModel {
    var page = 0
    var kcalText = TideFormat.kcalText(TideTargets.harbourDefault.kcal)
    var proteinText = TideFormat.macroText(TideTargets.harbourDefault.protein)
    var carbsText = TideFormat.macroText(TideTargets.harbourDefault.carbs)
    var fatText = TideFormat.macroText(TideTargets.harbourDefault.fat)
    var isSaving = false
    var onFinished: (() -> Void)?

    private let store: HarborStore

    init(store: HarborStore) {
        self.store = store
    }

    func skip() {
        Task { await finish(using: .harbourDefault) }
    }

    func complete() {
        Task { await finish(using: parsedTargets() ?? .harbourDefault) }
    }

    private func parsedTargets() -> TideTargets? {
        guard let kcal = TideFormat.parseGrams(kcalText), kcal >= 800, kcal <= 6000,
              let protein = TideFormat.parseGrams(proteinText), protein > 0, protein <= 500,
              let carbs = TideFormat.parseGrams(carbsText), carbs > 0, carbs <= 500,
              let fat = TideFormat.parseGrams(fatText), fat > 0, fat <= 500
        else { return nil }
        return TideTargets(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    private func finish(using targets: TideTargets) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.saveTargets(targets)
            try await store.markOnboardingComplete()
            HapticBeacon.commit()
            onFinished?()
        } catch {
            onFinished?()
        }
    }
}

struct FirstWatchOnboardingView: View {
    @Bindable var model: FirstWatchOnboardingViewModel

    var body: some View {
        ZStack {
            TidePalette.background.ignoresSafeArea()
            VStack(spacing: BerthMetrics.space(2)) {
                TabView(selection: $model.page) {
                    page(
                        image: "mdk_Onboarding1",
                        title: "READ THE HOLD",
                        line: "MacroDock keeps a personal food log. It is not medical advice. Nutrition figures come from Open Food Facts.",
                        tag: 0
                    )
                    page(
                        image: "mdk_Onboarding2",
                        title: "SEARCH OR SCAN",
                        line: "Find cargo by name on the quay, or scan a hatch code with the camera. Typed codes work on the Simulator.",
                        tag: 1
                    )
                    page(
                        image: "mdk_Onboarding3",
                        title: "SET THE TIDE",
                        line: "Write daily energy and macro targets. Skip uses a sensible harbour default.",
                        tag: 2
                    )
                    targetsPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                HStack(spacing: BerthMetrics.space(1)) {
                    Button("Skip with defaults") { model.skip() }
                        .font(SignalType.log)
                        .foregroundStyle(TidePalette.muted)
                        .frame(minHeight: BerthMetrics.tap)
                    if model.page < 3 {
                        Button("Next watch") { model.page += 1 }
                            .buttonStyle(HarborActionStyle())
                    } else {
                        Button("Weigh anchor") { model.complete() }
                            .buttonStyle(HarborActionStyle())
                            .disabled(model.isSaving)
                    }
                }
                .padding(.horizontal, BerthMetrics.space(2))
                .padding(.bottom, BerthMetrics.space(2))
            }
        }
    }

    private func page(image: String, title: String, line: String, tag: Int) -> some View {
        VStack(spacing: BerthMetrics.space(2)) {
            Image(image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
            Text(title)
                .font(SignalType.berth)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.ink)
            Text(line)
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BerthMetrics.space(2))
        }
        .tag(tag)
    }

    private var targetsPage: some View {
        ScrollView {
            VStack(spacing: BerthMetrics.space(2)) {
                Image("mdk_TwistHero")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 180)
                    .accessibilityHidden(true)
                Text("HOLD TARGETS")
                    .font(SignalType.berth)
                    .kerning(SignalType.headerKerning)
                    .foregroundStyle(TidePalette.ink)
                Text("Pantry stock lives on the harbour map. Logging cargo lowers grams in the hold.")
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.muted)
                    .multilineTextAlignment(.center)
                targetField("Energy kcal", text: $model.kcalText)
                targetField("Protein g", text: $model.proteinText)
                targetField("Carbs g", text: $model.carbsText)
                targetField("Fat g", text: $model.fatText)
            }
            .padding(BerthMetrics.space(2))
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func targetField(_ title: String, text: Binding<String>) -> some View {
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
