import SwiftUI

/// Card with Stud.IP announcements: on „Heute“ the unread ones of all modules, in a module its latest ones.
struct AnnouncementsCard: View {
    let items: [AnnouncementItem]
    /// Shows the module of each announcement; off inside a module.
    var showsModule = true
    let onOpen: (AnnouncementItem) -> Void
    let onMarkAllRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Ankündigungen", systemImage: "megaphone") {
                if items.contains(where: { !$0.announcement.isRead }) {
                    Button("Alle gelesen", action: onMarkAllRead)
                        .buttonStyle(.link)
                        .font(Theme.Typography.small)
                }
            }
            ForEach(items) { item in
                Button { onOpen(item) } label: {
                    AnnouncementRow(item: item, showsModule: showsModule)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct AnnouncementRow: View {
    let item: AnnouncementItem
    let showsModule: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.announcement.isRead ? Color.clear : Theme.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
                .accessibilityLabel(item.announcement.isRead ? "Gelesen" : "Ungelesen")
            VStack(alignment: .leading, spacing: 3) {
                Text(item.announcement.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if showsModule {
                        ModuleBadge(name: item.module.name, color: item.module.color, size: 14)
                        Text(item.module.name)
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(item.announcement.publishedAt, format: .relative(presentation: .named))
                }
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                if !item.announcement.body.isEmpty {
                    Text(item.announcement.body)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Full text of an announcement.
struct AnnouncementDetailSheet: View {
    let item: AnnouncementItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ModuleBadge(name: item.module.name, color: item.module.color, size: 16)
                    Text(item.module.name)
                    Text("·")
                    Text(item.announcement.publishedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                Text(item.announcement.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(20)
            Divider()
            ScrollView {
                Text(item.announcement.body.isEmpty ? "Kein Text." : item.announcement.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 520, height: 440)
    }
}
