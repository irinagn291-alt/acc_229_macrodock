import Foundation
import SQLite3

enum KeelValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

protocol KeelBindable: Sendable {
    func asKeelValue() -> KeelValue
}

extension String: KeelBindable {
    func asKeelValue() -> KeelValue { .text(self) }
}

extension Int: KeelBindable {
    func asKeelValue() -> KeelValue { .integer(Int64(self)) }
}

extension Int64: KeelBindable {
    func asKeelValue() -> KeelValue { .integer(self) }
}

extension Double: KeelBindable {
    func asKeelValue() -> KeelValue { .real(self) }
}

extension Bool: KeelBindable {
    func asKeelValue() -> KeelValue { .integer(self ? 1 : 0) }
}

extension Optional: KeelBindable where Wrapped: KeelBindable {
    func asKeelValue() -> KeelValue {
        switch self {
        case .none: .null
        case .some(let value): value.asKeelValue()
        }
    }
}

/// Role in MVVM-C: typed table token for the hand-rolled query builder.
struct KeelTable: Sendable {
    let name: String
}

/// Role in MVVM-C: typed column token for the hand-rolled query builder.
struct KeelColumn<Value: KeelBindable>: Sendable {
    let name: String
    init(_ name: String) { self.name = name }
}

struct KeelPredicate: Sendable {
    let sql: String
    let binds: [KeelValue]

    static func && (lhs: KeelPredicate, rhs: KeelPredicate) -> KeelPredicate {
        KeelPredicate(sql: "(\(lhs.sql)) AND (\(rhs.sql))", binds: lhs.binds + rhs.binds)
    }
}

func == <Value: KeelBindable>(lhs: KeelColumn<Value>, rhs: Value) -> KeelPredicate {
    KeelPredicate(sql: "\(lhs.name) = ?", binds: [rhs.asKeelValue()])
}

func <= <Value: KeelBindable>(lhs: KeelColumn<Value>, rhs: Value) -> KeelPredicate {
    KeelPredicate(sql: "\(lhs.name) <= ?", binds: [rhs.asKeelValue()])
}

func >= <Value: KeelBindable>(lhs: KeelColumn<Value>, rhs: Value) -> KeelPredicate {
    KeelPredicate(sql: "\(lhs.name) >= ?", binds: [rhs.asKeelValue()])
}

/// Role in MVVM-C: typed select builder. Persistence only; UI never sees SQL.
struct KeelSelect: Sendable {
    var table: String
    var columns: [String]
    var predicate: KeelPredicate?
    var orderSQL: String?
    var limitCount: Int?

    func `where`(_ predicate: KeelPredicate) -> KeelSelect {
        var copy = self
        copy.predicate = predicate
        return copy
    }

    func orderBy(_ column: String, descending: Bool = false) -> KeelSelect {
        var copy = self
        copy.orderSQL = "\(column) \(descending ? "DESC" : "ASC")"
        return copy
    }

    func limit(_ count: Int) -> KeelSelect {
        var copy = self
        copy.limitCount = count
        return copy
    }

    func compiled() -> (String, [KeelValue]) {
        var sql = "SELECT \(columns.joined(separator: ", ")) FROM \(table)"
        var binds: [KeelValue] = []
        if let predicate {
            sql += " WHERE \(predicate.sql)"
            binds.append(contentsOf: predicate.binds)
        }
        if let orderSQL {
            sql += " ORDER BY \(orderSQL)"
        }
        if let limitCount {
            sql += " LIMIT \(limitCount)"
        }
        return (sql, binds)
    }
}

func keelSelect(_ columns: [String], from table: KeelTable) -> KeelSelect {
    KeelSelect(table: table.name, columns: columns)
}

enum KeelFault: Error, Sendable, Equatable {
    case open(Int32, String)
    case prepare(Int32, String)
    case bind(Int32)
    case step(Int32, String)
    case closed
}

enum KeelSchema {
    static let products = KeelTable(name: "cargo_products")
    static let lading = KeelTable(name: "lading_entries")
    static let targets = KeelTable(name: "tide_targets")
    static let wishes = KeelTable(name: "wish_pennants")
    static let stock = KeelTable(name: "hold_stock")
    static let restock = KeelTable(name: "restock_indents")
    static let flags = KeelTable(name: "harbor_flags")

    static let barcode = KeelColumn<String>("barcode")
    static let voyageDay = KeelColumn<Int>("voyage_day")
    static let isEaten = KeelColumn<Bool>("is_eaten")
    static let grams = KeelColumn<Double>("grams")
    static let flagKey = KeelColumn<String>("key")
}

/// Role in MVVM-C: serial SQLite connection via the C API. Owned only by HarborStore.
final class KeelConnection {
    private var handle: OpaquePointer?

    init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        let code = sqlite3_open_v2(fileURL.path, &opened, flags, nil)
        guard code == SQLITE_OK, let opened else {
            throw KeelFault.open(code, Self.message(opened))
        }
        handle = opened
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func exec(_ sql: String) throws {
        guard let handle else { throw KeelFault.closed }
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &error)
        if let error {
            let text = String(cString: error)
            sqlite3_free(error)
            if code != SQLITE_OK {
                throw KeelFault.step(code, text)
            }
        } else if code != SQLITE_OK {
            throw KeelFault.step(code, Self.message(handle))
        }
    }

    @discardableResult
    func run(_ sql: String, binds: [KeelValue] = []) throws -> [[KeelValue]] {
        guard let handle else { throw KeelFault.closed }
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareCode == SQLITE_OK, let statement else {
            throw KeelFault.prepare(prepareCode, Self.message(handle))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in binds.enumerated() {
            try bind(statement, index: Int32(index + 1), value: value)
        }
        var rows: [[KeelValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let count = sqlite3_column_count(statement)
                var row: [KeelValue] = []
                row.reserveCapacity(Int(count))
                for column in 0..<count {
                    row.append(extract(statement, index: column))
                }
                rows.append(row)
            } else if step == SQLITE_DONE {
                break
            } else {
                throw KeelFault.step(step, Self.message(handle))
            }
        }
        return rows
    }

    func run(_ select: KeelSelect) throws -> [[KeelValue]] {
        let compiled = select.compiled()
        return try run(compiled.0, binds: compiled.1)
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try exec("ROLLBACK;")
            throw error
        }
    }

    func userVersion() throws -> Int {
        let rows = try run("PRAGMA user_version;")
        if case .integer(let value)? = rows.first?.first {
            return Int(value)
        }
        return 0
    }

    func setUserVersion(_ version: Int) throws {
        try exec("PRAGMA user_version = \(version);")
    }

    private func migrate() throws {
        let version = try userVersion()
        if version < 1 {
            try exec(Self.schemaV1)
            try setUserVersion(1)
        }
    }

    private func bind(_ statement: OpaquePointer, index: Int32, value: KeelValue) throws {
        let code: Int32
        switch value {
        case .null:
            code = sqlite3_bind_null(statement, index)
        case .integer(let integer):
            code = sqlite3_bind_int64(statement, index, integer)
        case .real(let real):
            code = sqlite3_bind_double(statement, index, real)
        case .text(let text):
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            code = sqlite3_bind_text(statement, index, text, -1, transient)
        }
        guard code == SQLITE_OK else { throw KeelFault.bind(code) }
    }

    private func extract(_ statement: OpaquePointer, index: Int32) -> KeelValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let pointer = sqlite3_column_text(statement, index) {
                return .text(String(cString: pointer))
            }
            return .null
        default:
            return .null
        }
    }

    private static func message(_ handle: OpaquePointer?) -> String {
        guard let handle, let pointer = sqlite3_errmsg(handle) else { return "unknown keel fault" }
        return String(cString: pointer)
    }

    private static let schemaV1 = """
        CREATE TABLE cargo_products (
            barcode TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT,
            kcal100 REAL,
            protein100 REAL,
            carbs100 REAL,
            fat100 REAL,
            image_url TEXT,
            shelf_asset TEXT,
            refreshed_epoch INTEGER NOT NULL
        );
        CREATE INDEX idx_cargo_products_barcode ON cargo_products(barcode);
        CREATE TABLE lading_entries (
            id TEXT PRIMARY KEY,
            barcode TEXT NOT NULL,
            grams REAL NOT NULL,
            slot TEXT NOT NULL,
            voyage_day INTEGER NOT NULL,
            is_eaten INTEGER NOT NULL,
            created_epoch INTEGER NOT NULL,
            FOREIGN KEY (barcode) REFERENCES cargo_products(barcode)
        );
        CREATE INDEX idx_lading_voyage_day ON lading_entries(voyage_day);
        CREATE INDEX idx_lading_barcode ON lading_entries(barcode);
        CREATE TABLE tide_targets (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            kcal REAL NOT NULL,
            protein REAL NOT NULL,
            carbs REAL NOT NULL,
            fat REAL NOT NULL
        );
        CREATE TABLE wish_pennants (
            barcode TEXT PRIMARY KEY,
            added_epoch INTEGER NOT NULL,
            FOREIGN KEY (barcode) REFERENCES cargo_products(barcode)
        );
        CREATE TABLE hold_stock (
            barcode TEXT PRIMARY KEY,
            grams REAL NOT NULL,
            low_threshold REAL NOT NULL,
            FOREIGN KEY (barcode) REFERENCES cargo_products(barcode)
        );
        CREATE INDEX idx_hold_stock_grams ON hold_stock(grams);
        CREATE TABLE restock_indents (
            barcode TEXT PRIMARY KEY,
            added_epoch INTEGER NOT NULL,
            FOREIGN KEY (barcode) REFERENCES cargo_products(barcode)
        );
        CREATE TABLE harbor_flags (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL
        );
        """
}
