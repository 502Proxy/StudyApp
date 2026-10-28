import SwiftUI

/// Ordnet jedem aktiven Modul eine Stud.IP-Veranstaltung zu, aus der seine Folien geladen werden.
struct StudIPCoursesSheet: View {
    @Bindable var viewModel: StudIPViewModel
    let modules: [StudyModule]

    @Environment(\.dismiss) private var dismiss

    private var suggestionCount: Int {
        modules.filter { $0.studIPCourseID == nil && viewModel.suggestion(for: $0) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stud.IP-Veranstaltungen")
                    .font(Theme.Typography.title)
                Text("Aus der zugeordneten Veranstaltung werden alle PDFs des Dateibereichs in die Folien des Moduls geladen.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if suggestionCount > 0 {
                    Button("\(suggestionCount) Vorschläge übernehmen") {
                        viewModel.applySuggestions(to: modules)
                    }
                }
                Spacer()
                Button("Folien jetzt laden") {
                    Task { await viewModel.syncNow() }
                }
                .disabled(viewModel.isSyncing || !modules.contains { $0.studIPCourseID != nil })
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
        .background(Theme.surface)
        .task { await viewModel.loadCourses() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.isConnected {
            EmptyStateView(
                title: "Nicht mit Stud.IP verbunden",
                systemImage: "person.badge.key",
                message: "Melde dich zuerst in den Einstellungen (⌘,) unter „Stud.IP“ an."
            )
        } else if viewModel.isLoadingCourses && viewModel.courses.isEmpty {
            ProgressView("Veranstaltungen werden geladen …")
        } else if modules.isEmpty {
            EmptyStateView(
                title: "Keine aktiven Module",
                systemImage: "books.vertical",
                message: "Lege Module an oder importiere deinen Stundenplan."
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(modules) { module in
                        row(for: module)
                        if module.id != modules.last?.id { Divider() }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func row(for module: StudyModule) -> some View {
        let suggestion = module.studIPCourseID == nil ? viewModel.suggestion(for: module) : nil
        return HStack(spacing: 12) {
            ModuleBadge(name: module.name, color: module.color, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.name)
                    .font(Theme.Typography.headline)
                    .lineLimit(1)
                if let suggestion {
                    Text("Vorschlag: \(suggestion.title)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.accentText)
                        .lineLimit(1)
                } else {
                    Text(module.semester.title)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Picker("Veranstaltung", selection: courseBinding(for: module)) {
                Text("Keine").tag(String?.none)
                // Eine verknüpfte Veranstaltung, die Stud.IP nicht mehr liefert, bleibt sichtbar.
                if let id = module.studIPCourseID, viewModel.course(withID: id) == nil {
                    Text("Verknüpft (nicht gefunden)").tag(String?.some(id))
                }
                ForEach(viewModel.courses) { course in
                    Text(label(for: course)).tag(String?.some(course.id))
                }
            }
            .labelsHidden()
            .frame(width: 280)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func courseBinding(for module: StudyModule) -> Binding<String?> {
        Binding(
            get: { module.studIPCourseID },
            set: { viewModel.link(module, to: $0) }
        )
    }

    private func label(for course: StudIPCourse) -> String {
        [course.semester?.title, course.number.isEmpty ? nil : course.number, course.title]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
