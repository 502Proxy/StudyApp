import SwiftUI

// MARK: - Karten

/// Weiße Karte mit feiner Kontur und weichem Schatten – das Grundelement des Layouts.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Spacing.card
    var radius: CGFloat = Theme.Radius.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.surfaceBorder, lineWidth: 1)
            }
            .shadow(color: Theme.shadow.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.card, radius: CGFloat = Theme.Radius.large) -> some View {
        modifier(CardStyle(padding: padding, radius: radius))
    }
}

/// Karten-Buttons heben sich beim Überfahren leicht ab.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardButtonBody(configuration: configuration)
    }

    private struct CardButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .brightness(isHovered ? -0.015 : 0)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Überschriften

/// Kopfzeile einer Seite: großer Titel, Untertitel und optionale Aktionen rechts.
struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, subtitle: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

/// Zwischenüberschrift innerhalb einer Seite.
struct SectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var accessory: () -> Accessory

    init(_ title: String, systemImage: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            accessory()
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - Kennzahlen

/// Kachel mit Symbol, Zahl und Beschreibung; führt beim Klick in den jeweiligen Bereich.
struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.textPrimary)
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Kleine Elemente

/// Kleines Etikett, z. B. für Veranstaltungsarten oder Zählwerte.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Pulsierender Hinweis „Live“ für laufende Vorlesungen.
struct LiveBadge: View {
    var text = "LIVE"
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.live)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 0.35 : 1)
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.live)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.live.opacity(0.12), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
        }
        .accessibilityLabel("Läuft gerade")
    }
}

/// Fortschrittsbalken für laufende Termine.
struct SlimProgressBar: View {
    let progress: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint).frame(width: max(4, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityValue("\(Int(progress * 100)) Prozent")
    }
}

/// Moderne Tab-Leiste mit Symbolen, z. B. für die Bereiche eines Moduls.
struct PillTabBar<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let systemImage: (Item) -> String
    @Namespace private var namespace

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        systemImage: @escaping (Item) -> String
    ) {
        self.items = items
        _selection = selection
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        // Wird es eng, zeigen nur noch der gewählte Bereich Titel und Symbol, die übrigen nur ihr Symbol.
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = item == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = item }
                } label: {
                    Label(title(item), systemImage: systemImage(item))
                        .labelStyle(TabLabelStyle(showsTitle: !compact || isSelected))
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.surface)
                                    .shadow(color: Theme.shadow.opacity(0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title(item))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TabLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration)
        } else {
            configuration.icon
        }
    }
}

/// Einheitlicher Leerzustand mit optionaler Aktion.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 6) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Kurze Statusmeldung am unteren Rand.
struct StatusToast: View {
    let message: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.surfaceBorder) }
            .shadow(color: Theme.shadow.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
