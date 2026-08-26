import Foundation

/// Role in MVVM-C: domain entity for a cached cargo product.
struct CargoProduct: Identifiable, Hashable, Sendable, Equatable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let kcal100: Double?
    let protein100: Double?
    let carbs100: Double?
    let fat100: Double?
    let imageURL: URL?
    let shelfAsset: String?
    let refreshedEpoch: Int64
}

/// Role in MVVM-C: domain entity for a logged or planned lading.
struct LadingEntry: Identifiable, Hashable, Sendable, Equatable {
    let id: String
    let barcode: String
    let grams: Double
    let slot: WatchSlot
    let voyageDay: VoyageDay
    let isEaten: Bool
    let createdEpoch: Int64
}

/// Role in MVVM-C: daily tide targets. Never stored as computed remainders.
struct TideTargets: Hashable, Sendable, Equatable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let harbourDefault = TideTargets(kcal: 2200, protein: 140, carbs: 250, fat: 70)
}

/// Role in MVVM-C: wish pennant, unique by barcode.
struct WishPennant: Identifiable, Hashable, Sendable, Equatable {
    var id: String { barcode }
    let barcode: String
    let addedEpoch: Int64
}

/// Role in MVVM-C: pantry hold stock for one product, independent of the wish ledger.
struct HoldStock: Identifiable, Hashable, Sendable, Equatable {
    var id: String { barcode }
    let barcode: String
    let grams: Double
    let lowThreshold: Double

    var isLow: Bool { grams <= lowThreshold }
}

/// Role in MVVM-C: restock indent, independent of WishPennant.
struct RestockIndent: Identifiable, Hashable, Sendable, Equatable {
    var id: String { barcode }
    let barcode: String
    let addedEpoch: Int64
}

enum WatchSlot: String, CaseIterable, Sendable, Hashable, Codable {
    case dawnWatch
    case forenoonWatch
    case dogWatch
    case shipsBiscuit

    var title: String {
        switch self {
        case .dawnWatch: "Dawn Watch"
        case .forenoonWatch: "Forenoon Watch"
        case .dogWatch: "Dog Watch"
        case .shipsBiscuit: "Ship's Biscuit"
        }
    }

    var asset: String {
        switch self {
        case .dawnWatch: "mdk_SlotDawnWatch"
        case .forenoonWatch: "mdk_SlotForenoonWatch"
        case .dogWatch: "mdk_SlotDogWatch"
        case .shipsBiscuit: "mdk_SlotShipSBiscuit"
        }
    }

    var rank: Int {
        switch self {
        case .dawnWatch: 0
        case .forenoonWatch: 1
        case .dogWatch: 2
        case .shipsBiscuit: 3
        }
    }

    var canPlanAhead: Bool {
        self != .shipsBiscuit
    }
}

/// Role in MVVM-C: pure berth rules. Snack remaps to Evening (Dog Watch) when dated ahead.
enum BerthAssignment {
    static func resolvedSlot(_ slot: WatchSlot, voyageDay: VoyageDay, today: VoyageDay) -> WatchSlot {
        if voyageDay > today && slot == .shipsBiscuit {
            return .dogWatch
        }
        return slot
    }

    static func allowsFuture(_ slot: WatchSlot) -> Bool {
        slot.canPlanAhead
    }
}

struct ManifestTotals: Sendable, Equatable {
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    static func aggregate(entries: [LadingEntry], products: [String: CargoProduct]) -> ManifestTotals {
        var kcal = 0.0
        var proteinSum = 0.0
        var carbsSum = 0.0
        var fatSum = 0.0
        var proteinKnown = false
        var carbsKnown = false
        var fatKnown = false
        for entry in entries {
            guard let product = products[entry.barcode] else { continue }
            let portion = PortionRigging.portion(product: product, grams: entry.grams)
            if let value = portion.kcal { kcal += value }
            if let value = portion.protein {
                proteinSum += value
                proteinKnown = true
            }
            if let value = portion.carbs {
                carbsSum += value
                carbsKnown = true
            }
            if let value = portion.fat {
                fatSum += value
                fatKnown = true
            }
        }
        return ManifestTotals(
            kcal: kcal,
            protein: proteinKnown ? proteinSum : nil,
            carbs: carbsKnown ? carbsSum : nil,
            fat: fatKnown ? fatSum : nil
        )
    }
}

struct PortionDraw: Sendable, Equatable {
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
}

enum LadingKind: Sendable, Equatable {
    case eatenToday
    case planned(VoyageDay)
}

struct LadingDraft: Sendable, Equatable {
    let product: CargoProduct
    let grams: Double
    let slot: WatchSlot
    let voyageDay: VoyageDay
    let isEaten: Bool
}

enum HarborFault: Error, Sendable, Equatable {
    case transport
    case notFound
    case decoding
    case cancelled
    case cameraDenied
    case cameraRestricted
    case noEnergy
    case invalidGrams
    case store(String)
}

struct HoldCrate: Identifiable, Sendable, Equatable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let grams: Double
    let isLow: Bool
}
