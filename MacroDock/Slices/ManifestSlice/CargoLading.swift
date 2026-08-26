import SwiftUI

enum LadingFinish: Equatable, Sendable {
    case eatenToday
    case planned
    case cancelled
}

/// Role in MVVM-C: Detail + Assign in one sheet. Coordinator assigns onFinished. Never builds other VMs.
@MainActor
@Observable
final class CargoLadingViewModel {
    let product: CargoProduct
    var gramsText = "100"
    var selectedSlot: WatchSlot = .dawnWatch
    var useFuture = false
    var futureOffset = 1
    var alreadyWished = false
    var isCommitting = false
    var fault: String?
    var showBerth = false
    var onFinished: ((LadingFinish) -> Void)?

    private let store: HarborStore

    init(store: HarborStore, product: CargoProduct) {
        self.store = store
        self.product = product
    }

    var grams: Double? { PortionRigging.validatedGrams(gramsText) }
    var portion: PortionDraw { PortionRigging.portion(product: product, grams: grams ?? 0) }

    var voyageDay: VoyageDay {
        useFuture ? VoyageDay.today.adding(days: futureOffset) : .today
    }

    var effectiveSlot: WatchSlot {
        BerthAssignment.resolvedSlot(selectedSlot, voyageDay: voyageDay, today: .today)
    }

    var remappedSnack: Bool {
        selectedSlot == .shipsBiscuit && useFuture
    }

    func refreshWishState() async {
        alreadyWished = (try? await store.isWished(barcode: product.barcode)) ?? false
    }

    func addWish() {
        guard !alreadyWished, !isCommitting else { return }
        Task {
            isCommitting = true
            defer { isCommitting = false }
            do {
                let inserted = try await store.upsertWish(product: product)
                alreadyWished = true
                if inserted { HapticBeacon.commit() }
            } catch {
                fault = "The wish pennant would not hoist."
            }
        }
    }

    func commit() {
        guard let grams else {
            fault = "Grams must be a positive measure, not zero or a wild load."
            return
        }
        guard !isCommitting else { return }
        Task {
            isCommitting = true
            defer { isCommitting = false }
            let draft = LadingDraft(
                product: product,
                grams: grams,
                slot: effectiveSlot,
                voyageDay: voyageDay,
                isEaten: !useFuture
            )
            do {
                _ = try await store.insertLading(draft)
                HapticBeacon.commit()
                onFinished?(useFuture ? .planned : .eatenToday)
            } catch {
                fault = "The lading could not be written into the hold."
            }
        }
    }
}

struct CargoLadingSheet: View {
    @Bindable var model: CargoLadingViewModel
    @Binding var detent: PresentationDetent

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BerthMetrics.space(2)) {
                    ZStack(alignment: .bottomLeading) {
                        Image("mdk_CardBackdrop")
                            .resizable()
                            .scaledToFill()
                            .frame(height: 140)
                            .clipped()
                            .accessibilityHidden(true)
                        HStack(spacing: BerthMetrics.space(1)) {
                            CargoThumb(product: model.product)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.product.name)
                                    .font(SignalType.berth)
                                    .foregroundStyle(TidePalette.ink)
                                    .lineLimit(2)
                                Text(model.product.brand ?? "Unmarked hold")
                                    .font(SignalType.signal)
                                    .foregroundStyle(TidePalette.muted)
                                    .lineLimit(1)
                            }
                        }
                        .padding(BerthMetrics.space(2))
                    }
                    perHundred
                    gramsField
                    liveTotals
                    if let fault = model.fault {
                        Text(fault)
                            .font(SignalType.log)
                            .foregroundStyle(TidePalette.accent)
                    }
                    Button(model.alreadyWished ? "Already on the wish ledger" : "Hoist a wish pennant") {
                        model.addWish()
                    }
                    .buttonStyle(HarborActionStyle())
                    .disabled(model.alreadyWished || model.isCommitting)
                    Button("Berth this cargo") {
                        model.showBerth = true
                        detent = .large
                    }
                    .buttonStyle(HarborActionStyle())
                    if model.showBerth || detent == .large {
                        berth
                    }
                }
                .padding(.bottom, BerthMetrics.space(3))
            }
            .scrollDismissesKeyboard(.interactively)
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LADING")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
        .onChange(of: detent) { _, value in
            if value == .large { model.showBerth = true }
        }
    }

    private var perHundred: some View {
        VStack(alignment: .leading, spacing: BerthMetrics.space(1)) {
            Text("PER 100 G")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            macroLine("Energy", value: model.product.kcal100.map { TideFormat.kcalText($0) } ?? "unknown", unit: "kcal")
            macroLine("Protein", value: TideFormat.macroText(model.product.protein100), unit: "g")
            macroLine("Carbs", value: TideFormat.macroText(model.product.carbs100), unit: "g")
            macroLine("Fat", value: TideFormat.macroText(model.product.fat100), unit: "g")
        }
        .padding(BerthMetrics.space(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TidePalette.surface)
    }

    private func macroLine(_ title: String, value: String, unit: String) -> some View {
        HStack {
            Text(title)
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.ink)
            Spacer()
            Text(value == "unknown" ? "unknown" : "\(value) \(unit)")
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.muted)
                .lineLimit(1)
        }
    }

    private var gramsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GRAMS")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            TextField("Grams", text: $model.gramsText)
                .keyboardType(.decimalPad)
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.ink)
                .padding(BerthMetrics.space(1))
                .frame(minHeight: BerthMetrics.tap)
                .background(TidePalette.surface)
                .accessibilityLabel("Portion grams")
        }
        .padding(.horizontal, BerthMetrics.space(2))
    }

    private var liveTotals: some View {
        VStack(alignment: .leading, spacing: BerthMetrics.space(1)) {
            Text("THIS LADING")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            Text("\(TideFormat.macroText(model.portion.kcal)) kcal")
                .font(SignalType.mast)
                .foregroundStyle(TidePalette.ink)
            Text("P \(TideFormat.macroText(model.portion.protein)) · C \(TideFormat.macroText(model.portion.carbs)) · F \(TideFormat.macroText(model.portion.fat))")
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
        }
        .padding(BerthMetrics.space(2))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var berth: some View {
        VStack(alignment: .leading, spacing: BerthMetrics.space(2)) {
            Text("BERTH ASSIGNMENT")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            ForEach(WatchSlot.allCases, id: \.self) { slot in
                Button {
                    model.selectedSlot = slot
                } label: {
                    HStack {
                        Image(slot.asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text(slot.title)
                            .font(SignalType.cargo)
                            .foregroundStyle(TidePalette.ink)
                        Spacer()
                        if model.selectedSlot == slot {
                            Image("mdk_ControlFace")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(BerthMetrics.space(1))
                    .frame(minHeight: BerthMetrics.tap)
                    .background(model.selectedSlot == slot ? TidePalette.accent : TidePalette.surface)
                }
                .accessibilityLabel(slot.title)
                .accessibilityAddTraits(model.selectedSlot == slot ? .isSelected : [])
            }
            Toggle(isOn: $model.useFuture) {
                Text("Berth on a later voyage day")
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
            }
            .tint(TidePalette.accent)
            .frame(minHeight: BerthMetrics.tap)
            if model.useFuture {
                Stepper(value: $model.futureOffset, in: 1...14) {
                    Text("In \(model.futureOffset) days")
                        .font(SignalType.cargo)
                        .foregroundStyle(TidePalette.ink)
                }
                .frame(minHeight: BerthMetrics.tap)
            }
            if model.remappedSnack {
                Text("Ship's Biscuit cannot be planned. It remaps to Dog Watch, the evening berth.")
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.muted)
            }
            Button("Confirm berth") { model.commit() }
                .buttonStyle(HarborActionStyle())
                .disabled(model.isCommitting || model.grams == nil)
        }
        .padding(BerthMetrics.space(2))
        .background(TidePalette.surface)
    }
}
