import Foundation

/// An exam of a module: detected from the calendar or entered by hand.
struct Exam: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var moduleID: UUID
    var title: String
    var startDate: Date
    var location: String
    /// External ID of the calendar event the exam was detected from; `nil` for exams entered by hand.
    var calendarEventKey: String?
    /// Detected exams the user dismissed stay stored so they are not detected again.
    var isHidden = false
    /// Keys of the study plan items the user ticked off (`StudyPlanItem.id`).
    var completedPlanItems: Set<String> = []

    var isManual: Bool { calendarEventKey == nil }
}

enum ExamError: LocalizedError, Equatable {
    case emptyTitle
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Bitte gib der Prüfung einen Namen."
        case .notFound: "Die Prüfung wurde nicht gefunden."
        }
    }
}

/// „heute“, „morgen“, „in 12 Tagen“ – counted in calendar days, not 24-hour periods.
enum ExamCountdown {
    static func days(until date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func text(days: Int) -> String {
        switch days {
        case ..<0: "vorbei"
        case 0: "heute"
        case 1: "morgen"
        default: "in \(days) Tagen"
        }
    }

    /// Compact form for badges: „heute“, „morgen“, „12 T.“.
    static func shortText(days: Int) -> String {
        days > 1 ? "\(days) T." : text(days: days)
    }
}

extension UUID {
    /// A UUID derived from `key`, so an exam detected from the same calendar event keeps its identity
    /// between launches without being stored. Uses two FNV-1a hashes; not meant for security.
    static func stable(from key: String) -> UUID {
        func fnv1a(_ seed: UInt64) -> UInt64 {
            key.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        }
        let high = fnv1a(0xcbf2_9ce4_8422_2325)
        let low = fnv1a(0x8422_2325_cbf2_9ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (8 * UInt64(index)))
            bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (8 * UInt64(index)))
        }
        // Mark as version 4 / RFC 4122 variant so it is a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
