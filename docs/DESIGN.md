# Design

All colours, spacing and fonts come from `Theme` (`Presentation/DesignSystem/Theme.swift`). Views never use hex values or `Color.white`/`.black` directly.

## Colours

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F5F5F7` | `#1C1C1E` | Window background |
| `surface` | `#FFFFFF` | `#2C2C2E` | Cards and tiles |
| `surfaceSecondary` | `#F2F2F7` | `#3A3A3C` | Chips, inputs, recessed areas |
| `surfaceBorder` | `#E5E5EA` | `#38383A` | Card outlines (they replace shadows in dark mode) |
| `textPrimary` / `textSecondary` / `textTertiary` | `#1D1D1F` / `#6E6E73` / `#8E8E93` | `#F5F5F7` / `#AEAEB2` / `#98989D` | Text |
| `accent` | `#0062CC` | `#0A6CD6` | Fills, tints, selection (also the `AccentColor` asset) |
| `accentText` | `#0062CC` | `#4DA3FF` | Accent-coloured text and small symbols |
| `success` / `warning` / `danger` / `live` | system green, orange, red | lighter system variants | States |

- The dark greys are the neutral macOS greys, so content matches the system sidebar, toolbar and title bar.
- Text colours keep at least 4.5:1 contrast on their surface. Use `accentText`, not `accent`, for text.
- Module colours are Apple's system colours (`ModuleColor+Color.swift`).
- AppKit views (PDFKit) use `Theme.AppKitColors`.
- The app follows the system appearance unless the user picks light or dark in the settings.

## Layout

The redesign in #30 is tracked in steps: colours (#31), sidebar (#32), Today (#33) and module sections (#34). Mockups: [`docs/design/mockups/`](design/mockups/).
