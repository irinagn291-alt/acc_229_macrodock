import Foundation

/// Role in MVVM-C: barcode normalisation. Accepts camera, typed field, or pasted URL.
enum HatchCode {
    static func digitRuns(in raw: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in raw {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    static func normalize(_ raw: String) -> String? {
        candidates(from: raw).first
    }

    static func candidates(from raw: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for run in digitRuns(in: raw) {
            guard run.count >= 8, run.count <= 14 else { continue }
            append(run, seen: &seen, ordered: &ordered)
            if run.count == 12 {
                append("0" + run, seen: &seen, ordered: &ordered)
            }
        }
        return ordered
    }

    private static func append(_ code: String, seen: inout Set<String>, ordered: inout [String]) {
        if seen.insert(code).inserted {
            ordered.append(code)
        }
    }
}
