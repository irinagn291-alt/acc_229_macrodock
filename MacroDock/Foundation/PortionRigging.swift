import Foundation

/// Role in MVVM-C: pure portion maths. Round only at display, never here.
enum PortionRigging {
    static let kjPerKcal = 4.184
    static let maxGrams = 10_000.0

    static func kcalPer100(kcal: Double?, kilojoules: Double?) -> Double? {
        if let kcal { return kcal }
        if let kilojoules { return kilojoules / kjPerKcal }
        return nil
    }

    static func scale(_ per100: Double?, grams: Double) -> Double? {
        guard let per100 else { return nil }
        return per100 * grams / 100
    }

    static func portion(product: CargoProduct, grams: Double) -> PortionDraw {
        PortionDraw(
            kcal: scale(product.kcal100, grams: grams),
            protein: scale(product.protein100, grams: grams),
            carbs: scale(product.carbs100, grams: grams),
            fat: scale(product.fat100, grams: grams)
        )
    }

    static func validatedGrams(_ raw: String) -> Double? {
        guard let grams = TideFormat.parseGrams(raw) else { return nil }
        guard grams > 0, grams <= maxGrams else { return nil }
        return grams
    }
}
