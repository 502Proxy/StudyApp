import SwiftUI
import WidgetKit

/// Due flashcards in total and per module; a click opens the module with the most.
struct DueCardsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DueCards", provider: SnapshotProvider()) { entry in
            DueCardsSummary(snapshot: entry.snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(entry.snapshot.dueModules.first.map { StudyAppLink.module($0.moduleID, section: "flashcards").url })
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fällige Karteikarten")
        .description("Wie viele Karteikarten heute fällig sind.")
        .supportedFamilies([.systemSmall])
    }
}

/// Total of due cards and the modules with the most; shared by two widgets.
struct DueCardsSummary: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Wiederholen", systemImage: "rectangle.stack")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(snapshot.dueCards)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(snapshot.dueCards == 1 ? "Karte fällig" : "Karten fällig")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(snapshot.dueModules.prefix(2), id: \.moduleID) { module in
                Text("\(module.moduleName) \(module.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
