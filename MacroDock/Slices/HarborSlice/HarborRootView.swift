import SwiftUI

/// Role in MVVM-C: persistent harbour root. Every function arrives as a detent sheet.
struct HarborRootView: View {
    @Bindable var master: DockMaster
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TidePalette.background.ignoresSafeArea()
            Image("mdk_Texture")
                .resizable(resizingMode: .tile)
                .opacity(0.16)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if let harbor = master.harborVM {
                harborMap(harbor)
            } else if let fault = master.launchFault {
                TideFaultBanner(message: fault, retry: {
                    Task { await master.weighAnchor() }
                })
            } else {
                ProgressView()
                    .tint(TidePalette.ink)
                    .opacity(master.isReady ? 0 : 1)
            }
        }
        .sheet(item: $master.rootSheet, onDismiss: { master.dismissRoot() }) { sheet in
            sheetBody(sheet)
                .presentationDetents((sheet == .onboarding || sheet == .log || sheet == .goals) ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(sheet == .onboarding)
                .sheet(isPresented: $master.nestedLading) {
                    if let lading = master.ladingVM {
                        CargoLadingSheet(model: lading, detent: $master.ladingDetent)
                            .presentationDetents([.medium, .large], selection: $master.ladingDetent)
                            .presentationDragIndicator(.visible)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await master.harborVM?.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await master.harborVM?.refresh() }
        }
    }

    @ViewBuilder
    private func sheetBody(_ sheet: HarborSheet) -> some View {
        switch sheet {
        case .onboarding:
            if let model = master.onboardingVM {
                FirstWatchOnboardingView(model: model)
            }
        case .search:
            if let model = master.searchVM {
                QuaySearchView(model: model)
            }
        case .scan:
            if let model = master.scanVM {
                HatchScanView(model: model)
            }
        case .log:
            if let model = master.logVM {
                ManifestLogView(model: model)
            }
        case .plan:
            if let model = master.planVM {
                VoyagePlanView(model: model)
            }
        case .wish:
            if let model = master.wishVM {
                WishLedgerView(model: model)
            }
        case .goals:
            if let model = master.goalsVM {
                QuayGoalsView(model: model)
            }
        case .hold:
            if let model = master.holdVM {
                HoldStockView(model: model)
            }
        case .lading:
            if let model = master.ladingVM {
                CargoLadingSheet(model: model, detent: $master.ladingDetent)
            }
        }
    }

    private func harborMap(_ harbor: HarborViewModel) -> some View {
        ZStack {
            VStack(spacing: BerthMetrics.space(2)) {
                header(harbor)
                tideCard(harbor)
                slotStrip(harbor)
                if !harbor.lowStock.isEmpty {
                    lowStockBanner(harbor)
                }
                Spacer(minLength: BerthMetrics.space(1))
                dockControls(harbor)
            }
            .padding(.horizontal, BerthMetrics.space(2))
            .padding(.top, BerthMetrics.space(1))
            .padding(.bottom, BerthMetrics.space(2))

            if harbor.showSuccess {
                Image("mdk_SuccessMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .accessibilityLabel("Cargo logged")
                    .transition(.opacity)
            }
        }
        .animation(TideMotion.fadeIfReduced(reduceMotion), value: harbor.showSuccess)
    }

    private func header(_ harbor: HarborViewModel) -> some View {
        VStack(spacing: BerthMetrics.space(1)) {
            HarborSceneCanvas(crates: harbor.crates, onSelectBarcode: { barcode in
                harbor.onSelectCrate?(barcode)
            })
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .clipShape(Rectangle())
            .clipped()
            .allowsHitTesting(true)
            .accessibilityLabel("Harbour hold map. Crates show pantry stock.")
            Text("MACRODOCK")
                .font(SignalType.mast)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.ink)
            Text("Know what is in the hold")
                .font(SignalType.signal)
                .foregroundStyle(TidePalette.muted)
            Text(harbor.voyageDay.date(), style: .date)
                .font(SignalType.log)
                .foregroundStyle(TidePalette.ink)
        }
        .frame(maxWidth: .infinity)
        .background(TidePalette.background.opacity(0.72))
    }

    private func tideCard(_ harbor: HarborViewModel) -> some View {
        VStack(alignment: .leading, spacing: BerthMetrics.space(1)) {
            Text("TODAY'S TIDE")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(TideFormat.kcalText(harbor.totals.kcal))
                    .font(SignalType.beacon)
                    .foregroundStyle(harbor.totals.kcal > harbor.targets.kcal ? TidePalette.accent : TidePalette.ink)
                    .contentTransition(.numericText())
                    .animation(TideMotion.fadeIfReduced(reduceMotion), value: harbor.totals.kcal)
                Text("kcal / \(TideFormat.kcalText(harbor.targets.kcal))")
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.muted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Energy \(TideFormat.kcalText(harbor.totals.kcal)) of \(TideFormat.kcalText(harbor.targets.kcal)) kilocalories")
            macroRow(title: "Protein", value: harbor.totals.protein, target: harbor.targets.protein, asset: "mdk_MacroProtein")
            macroRow(title: "Carbs", value: harbor.totals.carbs, target: harbor.targets.carbs, asset: "mdk_MacroCarbs")
            macroRow(title: "Fat", value: harbor.totals.fat, target: harbor.targets.fat, asset: "mdk_MacroFat")
        }
        .padding(BerthMetrics.space(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TidePalette.surface)
    }

    private func macroRow(title: String, value: Double?, target: Double, asset: String) -> some View {
        HStack(spacing: BerthMetrics.space(1)) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(SignalType.log)
                .foregroundStyle(TidePalette.ink)
                .lineLimit(1)
            Spacer(minLength: BerthMetrics.space(1))
            Text("\(TideFormat.compactMacro(value)) / \(TideFormat.macroText(target)) g")
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
                .lineLimit(1)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(TideFormat.macroText(value)) of \(TideFormat.macroText(target)) grams")
    }

    private func slotStrip(_ harbor: HarborViewModel) -> some View {
        HStack(spacing: BerthMetrics.space(1)) {
            ForEach(WatchSlot.allCases, id: \.self) { slot in
                let count = harbor.entries(for: slot).count
                Button {
                    harbor.onOpenLog?()
                } label: {
                    VStack(spacing: 4) {
                        Image(slot.asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        Text(slot.title)
                            .font(SignalType.signal)
                            .foregroundStyle(TidePalette.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                        Text(count == 0 ? "empty" : "\(TideFormat.kcalText(harbor.slotEnergy(slot))) kcal")
                            .font(SignalType.signal)
                            .foregroundStyle(TidePalette.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: BerthMetrics.tap)
                    .padding(.vertical, BerthMetrics.space(1))
                    .background(TidePalette.surface)
                }
                .accessibilityLabel("\(slot.title), \(count) items. Open manifest.")
            }
        }
    }

    private func lowStockBanner(_ harbor: HarborViewModel) -> some View {
        Button {
            harbor.onOpenHold?()
        } label: {
            HStack {
                Text("LOW HOLD")
                    .font(SignalType.signal)
                    .kerning(SignalType.headerKerning)
                    .foregroundStyle(TidePalette.ink)
                Spacer()
                Text(restockLine(harbor.lowStock.count))
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.ink)
                    .lineLimit(1)
            }
            .padding(BerthMetrics.space(2))
            .frame(maxWidth: .infinity, minHeight: BerthMetrics.tap)
            .background(TidePalette.accent)
        }
        .accessibilityLabel("Low hold. \(restockLine(harbor.lowStock.count)). Open pantry.")
    }

    private func restockLine(_ count: Int) -> String {
        count == 1 ? "1 crate needs restock" : "\(count) crates need restock"
    }

    private func dockControls(_ harbor: HarborViewModel) -> some View {
        VStack(spacing: BerthMetrics.space(1)) {
            HStack(spacing: BerthMetrics.space(1)) {
                dockButton("Search quay", action: { harbor.onOpenSearch?() })
                dockButton("Scan hatch", action: { harbor.onOpenScan?() })
            }
            HStack(spacing: BerthMetrics.space(1)) {
                dockButton("Manifest", action: { harbor.onOpenLog?() })
                dockButton("Voyage plan", action: { harbor.onOpenPlan?() })
            }
            HStack(spacing: BerthMetrics.space(1)) {
                dockButton("Wish pennants", action: { harbor.onOpenWish?() })
                dockButton("Hold stock", action: { harbor.onOpenHold?() })
            }
            dockButton("Tide goals", action: { harbor.onOpenGoals?() })
        }
    }

    private func dockButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(HarborActionStyle())
            .accessibilityLabel(title)
    }
}
