import XCTest
@testable import MacroDock

final class MacroDockTests: XCTestCase {
    func testPortionMathsAndKilojouleFallback() {
        let fromKcal = PortionRigging.kcalPer100(kcal: 200, kilojoules: 900)
        XCTAssertEqual(fromKcal, 200)
        let fromKj = PortionRigging.kcalPer100(kcal: nil, kilojoules: 418.4)
        XCTAssertEqual(fromKj ?? 0, 100, accuracy: 0.0001)
        let none = PortionRigging.kcalPer100(kcal: nil, kilojoules: nil)
        XCTAssertNil(none)
        let scaled = PortionRigging.scale(50, grams: 80)
        XCTAssertEqual(scaled ?? 0, 40, accuracy: 0.0001)
    }

    func testHatchCodeNormalisation() {
        XCTAssertEqual(HatchCode.normalize("40123456"), "40123456")
        XCTAssertEqual(HatchCode.normalize("3017620422003"), "3017620422003")
        XCTAssertEqual(HatchCode.normalize("012345678905"), "012345678905")
        XCTAssertTrue(HatchCode.candidates(from: "123456789012").contains("0123456789012"))
        let fromURL = HatchCode.normalize("https://world.openfoodfacts.org/product/3017620422003/nutella")
        XCTAssertEqual(fromURL, "3017620422003")
        XCTAssertNil(HatchCode.normalize("no-digits-here"))
        XCTAssertTrue(HatchCode.digitRuns(in: "aa12345678bb").contains("12345678"))
    }

    func testMissingMacrosStayUnknown() {
        let product = CargoProduct(
            barcode: "00000000",
            name: "Bare Tin",
            brand: nil,
            kcal100: 120,
            protein100: nil,
            carbs100: 10,
            fat100: nil,
            imageURL: nil,
            shelfAsset: nil,
            refreshedEpoch: 0
        )
        let portion = PortionRigging.portion(product: product, grams: 50)
        XCTAssertEqual(portion.kcal ?? 0, 60, accuracy: 0.0001)
        XCTAssertNil(portion.protein)
        XCTAssertEqual(portion.carbs ?? 0, 5, accuracy: 0.0001)
        XCTAssertNil(portion.fat)
        XCTAssertEqual(TideFormat.macroText(portion.protein), "unknown")
        XCTAssertNotEqual(TideFormat.macroText(portion.protein), "0")
    }

    func testDayTotalsAcrossFourSlots() {
        let granola = LocalHoldShelf.product(barcode: "0018627103257")!
        let couscous = LocalHoldShelf.product(barcode: "3038350208002")!
        let cheddar = LocalHoldShelf.product(barcode: "0021000658084")!
        let apple = LocalHoldShelf.product(barcode: "4013000000000")!
        let day = VoyageDay(ordinal: 10)
        let entries = [
            LadingEntry(id: "1", barcode: granola.barcode, grams: 100, slot: .dawnWatch, voyageDay: day, isEaten: true, createdEpoch: 1),
            LadingEntry(id: "2", barcode: couscous.barcode, grams: 100, slot: .forenoonWatch, voyageDay: day, isEaten: true, createdEpoch: 2),
            LadingEntry(id: "3", barcode: cheddar.barcode, grams: 100, slot: .dogWatch, voyageDay: day, isEaten: true, createdEpoch: 3),
            LadingEntry(id: "4", barcode: apple.barcode, grams: 100, slot: .shipsBiscuit, voyageDay: day, isEaten: true, createdEpoch: 4)
        ]
        let products = Dictionary(uniqueKeysWithValues: [granola, couscous, cheddar, apple].map { ($0.barcode, $0) })
        let totals = ManifestTotals.aggregate(entries: entries, products: products)
        XCTAssertEqual(totals.kcal, 471 + 376 + 403 + 52, accuracy: 0.001)
        XCTAssertEqual(totals.protein ?? 0, 10 + 12.8 + 24.9 + 0.3, accuracy: 0.001)
        XCTAssertEqual(WatchSlot.allCases.count, 4)
    }

    func testBerthAssignmentRejectsSnackOnFutureDay() {
        let today = VoyageDay(ordinal: 40)
        let tomorrow = VoyageDay(ordinal: 41)
        let remapped = BerthAssignment.resolvedSlot(.shipsBiscuit, voyageDay: tomorrow, today: today)
        XCTAssertEqual(remapped, .dogWatch)
        let sameDay = BerthAssignment.resolvedSlot(.shipsBiscuit, voyageDay: today, today: today)
        XCTAssertEqual(sameDay, .shipsBiscuit)
        XCTAssertFalse(BerthAssignment.allowsFuture(.shipsBiscuit))
        XCTAssertTrue(BerthAssignment.allowsFuture(.dogWatch))
    }

    func testVoyageDayAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let before = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10))!
        let after = calendar.date(from: DateComponents(year: 2024, month: 3, day: 11))!
        let first = VoyageDay.from(before, calendar: calendar)
        let second = VoyageDay.from(after, calendar: calendar)
        XCTAssertEqual(second.ordinal - first.ordinal, 1)
        XCTAssertEqual(calendar.startOfDay(for: first.date(calendar: calendar)), calendar.startOfDay(for: before))
    }

    func testOpenFoodFactsDecodingWithStringNutriments() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "3017620422003",
            "product_name": "Nutella",
            "brands": "Ferrero",
            "nutriments": {
              "energy-kcal_100g": "539",
              "proteins_100g": 6.3,
              "carbohydrates_100g": "57.5",
              "fat_100g": 30.9
            }
          }
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(OpenSeaProductResponseDTO.self, from: json)
        XCTAssertEqual(dto.status, 1)
        let product = OpenSeaMapper.domain(from: dto.product!)
        XCTAssertEqual(product?.kcal100, 539)
        XCTAssertEqual(product?.protein100, 6.3)
        XCTAssertEqual(product?.carbs100, 57.5)

        let missing = """
        {
          "status": 0,
          "product": {}
        }
        """.data(using: .utf8)!
        let empty = try JSONDecoder().decode(OpenSeaProductResponseDTO.self, from: missing)
        XCTAssertEqual(empty.status, 0)
    }

    func testWishUniquenessAndPantryDecrementRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mdk-test-\(UUID().uuidString).sqlite")
        let store = try HarborStore(fileURL: url)
        try await store.seedShelfIfNeeded()
        let cheddar = LocalHoldShelf.product(barcode: "0021000658084")!
        let first = try await store.upsertWish(product: cheddar)
        let second = try await store.upsertWish(product: cheddar)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let pennants = try await store.wishPennants()
        XCTAssertEqual(pennants.filter { $0.barcode == cheddar.barcode }.count, 1)

        try await store.setStock(barcode: cheddar.barcode, grams: 200, threshold: 80)
        let draft = LadingDraft(product: cheddar, grams: 40, slot: .dogWatch, voyageDay: .today, isEaten: true)
        _ = try await store.insertLading(draft)
        let after = try await store.stock(barcode: cheddar.barcode)
        XCTAssertEqual(after?.grams ?? -1, 160, accuracy: 0.001)
        XCTAssertFalse(after?.isLow ?? true)

        try await store.setStock(barcode: cheddar.barcode, grams: 50, threshold: 80)
        let low = try await store.lowStock()
        XCTAssertTrue(low.contains { $0.barcode == cheddar.barcode })

        let restockBefore = try await store.restockIndents()
        XCTAssertFalse(restockBefore.contains { $0.barcode == cheddar.barcode })
        try await store.addRestock(barcode: cheddar.barcode)
        let restock = try await store.restockIndents()
        XCTAssertTrue(restock.contains { $0.barcode == cheddar.barcode })
        let wishes = try await store.wishPennants()
        XCTAssertTrue(wishes.contains { $0.barcode == cheddar.barcode })
        XCTAssertNotEqual(restock.count, 0)
    }

    func testPersistenceReloadsAfterReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mdk-reopen-\(UUID().uuidString).sqlite")
        let granola = LocalHoldShelf.product(barcode: "0018627103257")!
        let day = VoyageDay(ordinal: 77)
        do {
            let store = try HarborStore(fileURL: url)
            try await store.seedShelfIfNeeded()
            try await store.saveTargets(TideTargets(kcal: 2100, protein: 130, carbs: 200, fat: 60))
            _ = try await store.insertLading(
                LadingDraft(product: granola, grams: 55, slot: .dawnWatch, voyageDay: day, isEaten: true)
            )
        }
        let reopened = try HarborStore(fileURL: url)
        let targets = try await reopened.loadTargets()
        XCTAssertEqual(targets?.kcal, 2100)
        let entries = try await reopened.entries(voyageDay: day, eaten: true)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.grams ?? 0, 55, accuracy: 0.0001)
        let product = try await reopened.loadProduct(barcode: granola.barcode)
        XCTAssertEqual(product?.name, granola.name)
    }
}
