import Foundation

/// Role in MVVM-C: persistence seam. UI never sees statements or cursors.
actor HarborStore {
    private let connection: KeelConnection

    init(fileURL: URL) throws {
        connection = try KeelConnection(fileURL: fileURL)
    }

    static func applicationStore() throws -> HarborStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("MacroDock", isDirectory: true)
        return try HarborStore(fileURL: folder.appendingPathComponent("harbor.sqlite"))
    }

    func seedShelfIfNeeded() throws {
        for product in LocalHoldShelf.all {
            if try loadProduct(barcode: product.barcode) == nil {
                try saveProduct(product)
            }
        }
        if try loadTargets() == nil {
            try saveTargets(TideTargets.harbourDefault)
        }
    }

    func isOnboardingComplete() throws -> Bool {
        let query = keelSelect(["value"], from: KeelSchema.flags)
            .where(KeelSchema.flagKey == "onboarding")
        let rows = try connection.run(query)
        if case .integer(let value)? = rows.first?.first {
            return value == 1
        }
        return false
    }

    func markOnboardingComplete() throws {
        try connection.run(
            """
            INSERT INTO harbor_flags(key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            binds: ["onboarding".asKeelValue(), true.asKeelValue()]
        )
    }

    func saveProduct(_ product: CargoProduct) throws {
        try connection.run(
            """
            INSERT INTO cargo_products(
                barcode, name, brand, kcal100, protein100, carbs100, fat100, image_url, shelf_asset, refreshed_epoch
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(barcode) DO UPDATE SET
                name = excluded.name,
                brand = excluded.brand,
                kcal100 = excluded.kcal100,
                protein100 = excluded.protein100,
                carbs100 = excluded.carbs100,
                fat100 = excluded.fat100,
                image_url = excluded.image_url,
                shelf_asset = excluded.shelf_asset,
                refreshed_epoch = excluded.refreshed_epoch
            """,
            binds: [
                product.barcode.asKeelValue(),
                product.name.asKeelValue(),
                product.brand.asKeelValue(),
                product.kcal100.asKeelValue(),
                product.protein100.asKeelValue(),
                product.carbs100.asKeelValue(),
                product.fat100.asKeelValue(),
                product.imageURL?.absoluteString.asKeelValue() ?? .null,
                product.shelfAsset.asKeelValue(),
                product.refreshedEpoch.asKeelValue()
            ]
        )
    }

    func loadProduct(barcode: String) throws -> CargoProduct? {
        let query = keelSelect(
            ["barcode", "name", "brand", "kcal100", "protein100", "carbs100", "fat100", "image_url", "shelf_asset", "refreshed_epoch"],
            from: KeelSchema.products
        ).where(KeelSchema.barcode == barcode)
        return try connection.run(query).first.flatMap(Self.product(from:))
    }

    func loadProducts(barcodes: [String]) throws -> [String: CargoProduct] {
        var map: [String: CargoProduct] = [:]
        for barcode in barcodes {
            if let product = try loadProduct(barcode: barcode) {
                map[barcode] = product
            }
        }
        return map
    }

    func insertLading(_ draft: LadingDraft) throws -> LadingEntry {
        let entry = LadingEntry(
            id: UUID().uuidString,
            barcode: draft.product.barcode,
            grams: draft.grams,
            slot: draft.slot,
            voyageDay: draft.voyageDay,
            isEaten: draft.isEaten,
            createdEpoch: Int64(Date().timeIntervalSince1970)
        )
        try saveProduct(draft.product)
        try connection.transaction {
            try connection.run(
                """
                INSERT INTO lading_entries(id, barcode, grams, slot, voyage_day, is_eaten, created_epoch)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                binds: [
                    entry.id.asKeelValue(),
                    entry.barcode.asKeelValue(),
                    entry.grams.asKeelValue(),
                    entry.slot.rawValue.asKeelValue(),
                    entry.voyageDay.ordinal.asKeelValue(),
                    entry.isEaten.asKeelValue(),
                    entry.createdEpoch.asKeelValue()
                ]
            )
            if entry.isEaten {
                try decrementStockLocked(barcode: entry.barcode, grams: entry.grams)
            }
        }
        return entry
    }

    func deleteLading(id: String) throws {
        try connection.run("DELETE FROM lading_entries WHERE id = ?", binds: [id.asKeelValue()])
    }

    func entries(voyageDay: VoyageDay, eaten: Bool?) throws -> [LadingEntry] {
        var query = keelSelect(
            ["id", "barcode", "grams", "slot", "voyage_day", "is_eaten", "created_epoch"],
            from: KeelSchema.lading
        ).where(KeelSchema.voyageDay == voyageDay.ordinal)
        if let eaten {
            query = query.where(KeelSchema.voyageDay == voyageDay.ordinal && KeelSchema.isEaten == eaten)
        }
        query = query.orderBy("created_epoch")
        return try connection.run(query).compactMap(Self.entry(from:))
    }

    func plannedEntries(from start: VoyageDay, through end: VoyageDay) throws -> [LadingEntry] {
        let query = keelSelect(
            ["id", "barcode", "grams", "slot", "voyage_day", "is_eaten", "created_epoch"],
            from: KeelSchema.lading
        )
        .where(KeelSchema.isEaten == false && KeelSchema.voyageDay >= start.ordinal && KeelSchema.voyageDay <= end.ordinal)
        .orderBy("voyage_day")
        return try connection.run(query).compactMap(Self.entry(from:))
    }

    func markEaten(id: String, today: VoyageDay) throws {
        guard let existing = try entry(id: id) else { return }
        try connection.transaction {
            try connection.run(
                "UPDATE lading_entries SET is_eaten = ?, voyage_day = ? WHERE id = ?",
                binds: [true.asKeelValue(), today.ordinal.asKeelValue(), id.asKeelValue()]
            )
            try decrementStockLocked(barcode: existing.barcode, grams: existing.grams)
        }
    }

    func loadTargets() throws -> TideTargets? {
        let rows = try connection.run("SELECT kcal, protein, carbs, fat FROM tide_targets WHERE id = 1")
        guard let row = rows.first, row.count == 4 else { return nil }
        return TideTargets(
            kcal: Self.real(row[0]) ?? 0,
            protein: Self.real(row[1]) ?? 0,
            carbs: Self.real(row[2]) ?? 0,
            fat: Self.real(row[3]) ?? 0
        )
    }

    func saveTargets(_ targets: TideTargets) throws {
        try connection.run(
            """
            INSERT INTO tide_targets(id, kcal, protein, carbs, fat) VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kcal = excluded.kcal,
                protein = excluded.protein,
                carbs = excluded.carbs,
                fat = excluded.fat
            """,
            binds: [
                targets.kcal.asKeelValue(),
                targets.protein.asKeelValue(),
                targets.carbs.asKeelValue(),
                targets.fat.asKeelValue()
            ]
        )
    }

    func wishPennants() throws -> [WishPennant] {
        let rows = try connection.run("SELECT barcode, added_epoch FROM wish_pennants ORDER BY added_epoch DESC")
        return rows.compactMap { row in
            guard case .text(let barcode) = row[0] else { return nil }
            return WishPennant(barcode: barcode, addedEpoch: Self.int(row[1]) ?? 0)
        }
    }

    func isWished(barcode: String) throws -> Bool {
        let query = keelSelect(["barcode"], from: KeelSchema.wishes).where(KeelSchema.barcode == barcode)
        return try !connection.run(query).isEmpty
    }

    @discardableResult
    func upsertWish(product: CargoProduct) throws -> Bool {
        try saveProduct(product)
        let existed = try isWished(barcode: product.barcode)
        try connection.run(
            """
            INSERT INTO wish_pennants(barcode, added_epoch) VALUES (?, ?)
            ON CONFLICT(barcode) DO UPDATE SET added_epoch = excluded.added_epoch
            """,
            binds: [product.barcode.asKeelValue(), Int64(Date().timeIntervalSince1970).asKeelValue()]
        )
        return !existed
    }

    func deleteWish(barcode: String) throws {
        try connection.run("DELETE FROM wish_pennants WHERE barcode = ?", binds: [barcode.asKeelValue()])
    }

    func allStock() throws -> [HoldStock] {
        let rows = try connection.run("SELECT barcode, grams, low_threshold FROM hold_stock ORDER BY grams ASC")
        return rows.compactMap(Self.stock(from:))
    }

    func stock(barcode: String) throws -> HoldStock? {
        let query = keelSelect(["barcode", "grams", "low_threshold"], from: KeelSchema.stock)
            .where(KeelSchema.barcode == barcode)
        return try connection.run(query).first.flatMap(Self.stock(from:))
    }

    func setStock(barcode: String, grams: Double, threshold: Double = 80) throws {
        try connection.run(
            """
            INSERT INTO hold_stock(barcode, grams, low_threshold) VALUES (?, ?, ?)
            ON CONFLICT(barcode) DO UPDATE SET grams = excluded.grams, low_threshold = excluded.low_threshold
            """,
            binds: [barcode.asKeelValue(), grams.asKeelValue(), threshold.asKeelValue()]
        )
    }

    func lowStock() throws -> [HoldStock] {
        let rows = try connection.run("SELECT barcode, grams, low_threshold FROM hold_stock WHERE grams <= low_threshold")
        return rows.compactMap(Self.stock(from:))
    }

    func restockIndents() throws -> [RestockIndent] {
        let rows = try connection.run("SELECT barcode, added_epoch FROM restock_indents ORDER BY added_epoch DESC")
        return rows.compactMap { row in
            guard case .text(let barcode) = row[0] else { return nil }
            return RestockIndent(barcode: barcode, addedEpoch: Self.int(row[1]) ?? 0)
        }
    }

    func addRestock(barcode: String) throws {
        try connection.run(
            """
            INSERT INTO restock_indents(barcode, added_epoch) VALUES (?, ?)
            ON CONFLICT(barcode) DO UPDATE SET added_epoch = excluded.added_epoch
            """,
            binds: [barcode.asKeelValue(), Int64(Date().timeIntervalSince1970).asKeelValue()]
        )
    }

    func deleteRestock(barcode: String) throws {
        try connection.run("DELETE FROM restock_indents WHERE barcode = ?", binds: [barcode.asKeelValue()])
    }

    func resetAllData() throws {
        try connection.transaction {
            try connection.exec("DELETE FROM lading_entries;")
            try connection.exec("DELETE FROM wish_pennants;")
            try connection.exec("DELETE FROM hold_stock;")
            try connection.exec("DELETE FROM restock_indents;")
            try connection.exec("DELETE FROM cargo_products;")
            try connection.exec("DELETE FROM tide_targets;")
        }
        try seedShelfIfNeeded()
        try saveTargets(TideTargets.harbourDefault)
    }

    func seedDemoIfNeeded(today: VoyageDay) throws {
        #if targetEnvironment(simulator)
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "mdk.demo.v1") == false else { return }
        try seedDemoDay(today: today)
        try markOnboardingComplete()
        defaults.set(true, forKey: "mdk.demo.v1")
        #endif
    }

    func seedDemoDay(today: VoyageDay) throws {
        let granola = LocalHoldShelf.product(barcode: "0018627103257")
        let couscous = LocalHoldShelf.product(barcode: "3038350208002")
        let cheddar = LocalHoldShelf.product(barcode: "0021000658084")
        let apple = LocalHoldShelf.product(barcode: "4013000000000")
        let quinoa = LocalHoldShelf.product(barcode: "8410054010128")
        let corn = LocalHoldShelf.product(barcode: "0024000163015")
        if let granola {
            _ = try insertLading(LadingDraft(product: granola, grams: 60, slot: .dawnWatch, voyageDay: today, isEaten: true))
        }
        if let couscous {
            _ = try insertLading(LadingDraft(product: couscous, grams: 150, slot: .forenoonWatch, voyageDay: today, isEaten: true))
        }
        if let cheddar {
            _ = try insertLading(LadingDraft(product: cheddar, grams: 40, slot: .dogWatch, voyageDay: today, isEaten: true))
        }
        if let apple {
            _ = try insertLading(LadingDraft(product: apple, grams: 120, slot: .shipsBiscuit, voyageDay: today, isEaten: true))
        }
        if let quinoa {
            _ = try insertLading(LadingDraft(product: quinoa, grams: 80, slot: .forenoonWatch, voyageDay: today.adding(days: 1), isEaten: false))
        }
        if let corn {
            _ = try upsertWish(product: corn)
        }
        try setStock(barcode: "0018627103257", grams: 400)
        try setStock(barcode: "3038350208002", grams: 200)
        try setStock(barcode: "0024000163015", grams: 40)
        try setStock(barcode: "0021000658084", grams: 300)
        try setStock(barcode: "8410054010128", grams: 90)
        try setStock(barcode: "4013000000000", grams: 600)
    }

    private func entry(id: String) throws -> LadingEntry? {
        let rows = try connection.run(
            "SELECT id, barcode, grams, slot, voyage_day, is_eaten, created_epoch FROM lading_entries WHERE id = ?",
            binds: [id.asKeelValue()]
        )
        return rows.first.flatMap(Self.entry(from:))
    }

    private func decrementStockLocked(barcode: String, grams: Double) throws {
        guard let current = try stock(barcode: barcode) else { return }
        let next = max(0, current.grams - grams)
        try setStock(barcode: barcode, grams: next, threshold: current.lowThreshold)
    }

    private static func product(from row: [KeelValue]) -> CargoProduct? {
        guard row.count >= 10, case .text(let barcode) = row[0], case .text(let name) = row[1] else { return nil }
        let brand: String?
        if case .text(let value) = row[2] { brand = value } else { brand = nil }
        let imageURL: URL?
        if case .text(let value) = row[7] { imageURL = URL(string: value) } else { imageURL = nil }
        let shelf: String?
        if case .text(let value) = row[8] { shelf = value } else { shelf = nil }
        return CargoProduct(
            barcode: barcode,
            name: name,
            brand: brand,
            kcal100: real(row[3]),
            protein100: real(row[4]),
            carbs100: real(row[5]),
            fat100: real(row[6]),
            imageURL: imageURL,
            shelfAsset: shelf,
            refreshedEpoch: int(row[9]) ?? 0
        )
    }

    private static func entry(from row: [KeelValue]) -> LadingEntry? {
        guard row.count >= 7, case .text(let id) = row[0], case .text(let barcode) = row[1] else { return nil }
        guard case .text(let slotRaw) = row[3], let slot = WatchSlot(rawValue: slotRaw) else { return nil }
        return LadingEntry(
            id: id,
            barcode: barcode,
            grams: real(row[2]) ?? 0,
            slot: slot,
            voyageDay: VoyageDay(ordinal: Int(int(row[4]) ?? 0)),
            isEaten: (int(row[5]) ?? 0) == 1,
            createdEpoch: int(row[6]) ?? 0
        )
    }

    private static func stock(from row: [KeelValue]) -> HoldStock? {
        guard case .text(let barcode) = row.first else { return nil }
        return HoldStock(
            barcode: barcode,
            grams: real(row[1]) ?? 0,
            lowThreshold: real(row[2]) ?? 80
        )
    }

    private static func real(_ value: KeelValue) -> Double? {
        switch value {
        case .real(let number): number
        case .integer(let number): Double(number)
        default: nil
        }
    }

    private static func int(_ value: KeelValue) -> Int64? {
        switch value {
        case .integer(let number): number
        case .real(let number): Int64(number)
        default: nil
        }
    }
}
