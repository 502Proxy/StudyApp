import SwiftUI

/// Termindetails mit direkter Modulverknüpfung und Sprungzielen in die Lernbereiche des Moduls.
struct CalendarEventDetailSheet: View {
    let event: StudyCalendarEvent
    let modules: [StudyModule]
    let color: Color
    /// Anzahl der Termine derselben Veranstaltung (inklusive dieses Termins).
    let seriesCount: Int
    /// Verknüpft den Termin; mit `true` auch alle Termine derselben Veranstaltung.
    let onLink: (UUID?, Bool) -> Void
    let onOpenModule: (UUID, ModuleSection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModuleID: UUID?
    @AppStorage("calendar.linkWholeSeries") private var appliesToSeries = true

    init(
        event: StudyCalendarEvent,
        modules: [StudyModule],
        color: Color,
        seriesCount: Int = 1,
        onLink: @escaping (UUID?, Bool) -> Void,
        onOpenModule: @escaping (UUID, ModuleSection) -> Void
    ) {
        self.event = event
        self.modules = modules
        self.color = color
        self.seriesCount = seriesCount
        self.onLink = onLink
        self.onOpenModule = onOpenModule
        _selectedModuleID = State(initialValue: event.moduleID)
    }

    private var linkedModule: StudyModule? {
        modules.first { $0.id == selectedModuleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.and.ellipse")
                    .textSelection(.enabled)
            }
            if !event.details.isEmpty {
                ScrollView {
                    Text(event.details)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            Divider()
            moduleLink
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .frame(minHeight: 320)
        .background(Theme.surface)
        .onChange(of: selectedModuleID) { _, newValue in
            if newValue != event.moduleID { onLink(newValue, appliesToSeries && seriesCount > 1) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(color).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(event.startDate.formatted(date: .complete, time: .omitted))
                    .foregroundStyle(Theme.textSecondary)
                Text(event.timeDescription())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var moduleLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Modul", selection: $selectedModuleID) {
                Text("Kein Modul").tag(UUID?.none)
                ForEach(modules) { module in
                    Text(module.name).tag(UUID?.some(module.id))
                }
            }
            if seriesCount > 1 {
                Toggle("Für alle \(seriesCount) Termine dieser Veranstaltung übernehmen", isOn: $appliesToSeries)
                    .toggleStyle(.checkbox)
                    .font(Theme.Typography.small)
            }

            if let module = linkedModule {
                Text("Springe direkt in „\(module.name)“")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(ModuleSection.allCases) { section in
                        Button {
                            onOpenModule(module.id, section)
                        } label: {
                            Label(section.title, systemImage: section.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
        }
    }
}
