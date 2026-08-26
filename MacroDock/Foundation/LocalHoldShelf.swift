import Foundation

/// Role in MVVM-C: bundled local shelf. Search never dead-ends.
enum LocalHoldShelf {
    static let all: [CargoProduct] = [
        CargoProduct(
            barcode: "0018627103257",
            name: "Hold Granola",
            brand: "Galley Stores",
            kcal100: 471,
            protein100: 10.0,
            carbs100: 64.0,
            fat100: 20.0,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        ),
        CargoProduct(
            barcode: "3038350208002",
            name: "Quay Couscous",
            brand: "Dock Stores",
            kcal100: 376,
            protein100: 12.8,
            carbs100: 77.4,
            fat100: 0.6,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        ),
        CargoProduct(
            barcode: "0024000163015",
            name: "Tin Sweetcorn",
            brand: "Hold Tins",
            kcal100: 81,
            protein100: 2.9,
            carbs100: 17.1,
            fat100: 1.0,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        ),
        CargoProduct(
            barcode: "0021000658084",
            name: "Galley Cheddar",
            brand: "Cold Hold",
            kcal100: 403,
            protein100: 24.9,
            carbs100: 1.3,
            fat100: 33.1,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        ),
        CargoProduct(
            barcode: "8410054010128",
            name: "Hold Quinoa",
            brand: "Dry Stores",
            kcal100: 368,
            protein100: 14.1,
            carbs100: 64.2,
            fat100: 6.1,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        ),
        CargoProduct(
            barcode: "4013000000000",
            name: "Deck Apple",
            brand: "Fresh Hold",
            kcal100: 52,
            protein100: 0.3,
            carbs100: 13.8,
            fat100: 0.2,
            imageURL: nil,
            shelfAsset: "mdk_ProductPlaceholder",
            refreshedEpoch: 0
        )
    ]

    static func matches(_ query: String) -> [CargoProduct] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        return all.filter { product in
            product.name.localizedCaseInsensitiveContains(needle)
                || (product.brand?.localizedCaseInsensitiveContains(needle) ?? false)
                || product.barcode.contains(needle)
        }
    }

    static func product(barcode: String) -> CargoProduct? {
        all.first { $0.barcode == barcode }
    }
}
