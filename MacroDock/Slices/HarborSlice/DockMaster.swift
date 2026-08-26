import SwiftUI

enum HarborSheet: String, Identifiable, Equatable {
    case onboarding
    case search
    case scan
    case log
    case plan
    case wish
    case goals
    case hold
    case lading

    var id: String { rawValue }
}

/// Role in MVVM-C: Coordinator. Constructs every ViewModel and assigns navigation closures.
/// ViewModels never construct other ViewModels.
@MainActor
@Observable
final class DockMaster {
    private(set) var store: HarborStore?
    let client = OpenSeaClient()

    var isReady = false
    var launchFault: String?
    var rootSheet: HarborSheet?
    var nestedLading = false
    var ladingDetent: PresentationDetent = .medium

    var harborVM: HarborViewModel?
    var onboardingVM: FirstWatchOnboardingViewModel?
    var searchVM: QuaySearchViewModel?
    var scanVM: HatchScanViewModel?
    var ladingVM: CargoLadingViewModel?
    var logVM: ManifestLogViewModel?
    var planVM: VoyagePlanViewModel?
    var wishVM: WishLedgerViewModel?
    var goalsVM: QuayGoalsViewModel?
    var holdVM: HoldStockViewModel?

    func weighAnchor() async {
        do {
            let store = try HarborStore.applicationStore()
            try await store.seedShelfIfNeeded()
            try await store.seedDemoIfNeeded(today: .today)
            self.store = store
            let harbor = HarborViewModel(store: store)
            wireHarbor(harbor)
            harborVM = harbor
            await harbor.refresh()
            isReady = true
            if try await store.isOnboardingComplete() == false {
                presentOnboarding()
            } else {
                applyReviewScreenIfNeeded()
            }
        } catch {
            launchFault = "The hold could not be opened. Restart the watch."
        }
    }

    private func applyReviewScreenIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ReviewScreen"), index + 1 < args.count else { return }
        switch args[index + 1] {
        case "log": presentLog()
        case "goals": presentGoals()
        default: break
        }
    }

    func presentOnboarding() {
        guard let store else { return }
        let model = FirstWatchOnboardingViewModel(store: store)
        model.onFinished = { [weak self] in
            self?.rootSheet = nil
            self?.onboardingVM = nil
            Task { await self?.harborVM?.refresh() }
        }
        onboardingVM = model
        rootSheet = .onboarding
    }

    func presentSearch() {
        guard let store else { return }
        let model = QuaySearchViewModel(store: store, client: client)
        model.onSelectProduct = { [weak self] product in
            self?.presentLading(product, nested: true)
        }
        searchVM = model
        rootSheet = .search
    }

    func presentScan() {
        guard let store else { return }
        let model = HatchScanViewModel(store: store, client: client)
        model.onSelectProduct = { [weak self] product in
            self?.presentLading(product, nested: true)
        }
        scanVM = model
        rootSheet = .scan
    }

    func presentLog() {
        guard let store else { return }
        let model = ManifestLogViewModel(store: store)
        model.onAddCargo = { [weak self] in
            self?.rootSheet = nil
            self?.presentSearch()
        }
        logVM = model
        rootSheet = .log
        Task { await model.refresh() }
    }

    func presentPlan() {
        guard let store else { return }
        let model = VoyagePlanViewModel(store: store)
        model.onAddCargo = { [weak self] in
            self?.rootSheet = nil
            self?.presentSearch()
        }
        planVM = model
        rootSheet = .plan
        Task { await model.refresh() }
    }

    func presentWish() {
        guard let store else { return }
        let model = WishLedgerViewModel(store: store)
        model.onSelectProduct = { [weak self] product in
            self?.presentLading(product, nested: true)
        }
        model.onAddCargo = { [weak self] in
            self?.rootSheet = nil
            self?.presentSearch()
        }
        wishVM = model
        rootSheet = .wish
        Task { await model.refresh() }
    }

    func presentGoals() {
        guard let store else { return }
        let model = QuayGoalsViewModel(store: store)
        model.onReplayOnboarding = { [weak self] in
            self?.rootSheet = nil
            self?.presentOnboarding()
        }
        model.onReset = { [weak self] in
            Task { await self?.harborVM?.refresh() }
        }
        goalsVM = model
        rootSheet = .goals
        Task { await model.refresh() }
    }

    func presentHold() {
        guard let store else { return }
        let model = HoldStockViewModel(store: store)
        model.onSelectProduct = { [weak self] product in
            self?.presentLading(product, nested: true)
        }
        holdVM = model
        rootSheet = .hold
        Task { await model.refresh() }
    }

    func presentLading(_ product: CargoProduct, nested: Bool) {
        guard let store else { return }
        ladingDetent = .medium
        let model = CargoLadingViewModel(store: store, product: product)
        model.onFinished = { [weak self] kind in
            guard let self else { return }
            self.nestedLading = false
            self.ladingVM = nil
            switch kind {
            case .eatenToday:
                self.rootSheet = nil
                Task {
                    await self.harborVM?.refresh()
                    self.harborVM?.flashSuccess()
                }
            case .planned:
                self.rootSheet = nil
                self.presentPlan()
            case .cancelled:
                break
            }
        }
        ladingVM = model
        Task { await model.refreshWishState() }
        if nested, rootSheet != nil, rootSheet != .lading {
            nestedLading = true
        } else {
            rootSheet = .lading
        }
    }

    func dismissRoot() {
        guard rootSheet == nil else { return }
        nestedLading = false
        onboardingVM = nil
        searchVM = nil
        scanVM = nil
        ladingVM = nil
        logVM = nil
        planVM = nil
        wishVM = nil
        goalsVM = nil
        holdVM = nil
        Task { await harborVM?.refresh() }
    }

    private func wireHarbor(_ harbor: HarborViewModel) {
        harbor.onOpenSearch = { [weak self] in self?.presentSearch() }
        harbor.onOpenScan = { [weak self] in self?.presentScan() }
        harbor.onOpenLog = { [weak self] in self?.presentLog() }
        harbor.onOpenPlan = { [weak self] in self?.presentPlan() }
        harbor.onOpenWish = { [weak self] in self?.presentWish() }
        harbor.onOpenGoals = { [weak self] in self?.presentGoals() }
        harbor.onOpenHold = { [weak self] in self?.presentHold() }
        harbor.onSelectCrate = { [weak self] barcode in
            Task { await self?.openCrate(barcode) }
        }
    }

    private func openCrate(_ barcode: String) async {
        guard let store, let product = try? await store.loadProduct(barcode: barcode) else { return }
        presentLading(product, nested: false)
    }
}
