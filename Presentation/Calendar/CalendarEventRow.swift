import SwiftUI

/// Eine Terminkarte für Tagesliste, Agenda und Suche.
struct CalendarEventRow: View {
    let event: StudyCalendarEvent
    let module: StudyModule?
    let color: Color
    /// Tag, auf den sich die Zeitangabe bezieht.
    var day: Date?
    /// Zeigt zusätzlich das Datum (für Suchergebnisse).
    var showsDate = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if let module {
                    Label(module.name, systemImage: "books.vertical")
                        .font(.caption)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 4).padding(.vertical, 8).padding(.leading, 6)
            }
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.surfaceBorder, lineWidth: 0.7) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet die Termindetails")
    }

    private var timeText: String {
        let time = event.timeDescription(on: day)
        guard showsDate else { return time }
        return "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) · \(time)"
    }
}
