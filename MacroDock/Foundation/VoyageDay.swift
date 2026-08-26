import Foundation

/// Role in MVVM-C: domain value. A calendar day as an Int ordinal since a fixed reference.
struct VoyageDay: Hashable, Sendable, Codable, Comparable {
    let ordinal: Int

    static let referenceComponents = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2024, month: 1, day: 1)

    static func from(_ date: Date, calendar: Calendar = .current) -> VoyageDay {
        let start = calendar.startOfDay(for: date)
        let reference = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 1_704_067_200)
        let referenceStart = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents([.day], from: referenceStart, to: start).day ?? 0
        return VoyageDay(ordinal: days)
    }

    static var today: VoyageDay {
        from(Date())
    }

    func date(calendar: Calendar = .current) -> Date {
        let reference = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 1_704_067_200)
        let start = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: ordinal, to: start) ?? start
    }

    func adding(days: Int) -> VoyageDay {
        VoyageDay(ordinal: ordinal + days)
    }

    static func < (lhs: VoyageDay, rhs: VoyageDay) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}
