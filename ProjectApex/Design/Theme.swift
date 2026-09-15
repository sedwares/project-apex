//
//  Theme.swift
//  ProjectApex
//
//  The single source of truth for how Project Apex looks.
//
//  DIRECTION: F1 Broadcast — Carbon Black ground, Warm Red accent,
//  timing-tower structure, condensed heavy type, monospace data.
//  Official F1 palette: #15151E (Carbon Black), #FF1E00 (Warm Red).
//
//  RULES
//    · No view may name a raw Color or a system text style.
//    · Semantic names only. `Theme.Color.signal`, never `.red`.
//    · Monospace for values that align in a column: lap times, credits.
//    · `session` (purple) = fastest lap / personal record — F1 sector coding.
//
//  ACCESSIBILITY
//    cream on ink: 16.8:1. signal on ink: 4.6:1 — large type and fills only.
//

import SwiftUI

enum Theme {

    // MARK: - Colour

    enum Color {
        /// F1 Warm Red (#FF1E00). Accent, fills, stripes, primary CTA.
        static let signal = SwiftUI.Color(red: 1.000, green: 0.118, blue: 0.000)
        /// Off-white. Primary text on dark. (#F0EFE8)
        static let cream = SwiftUI.Color(red: 0.941, green: 0.937, blue: 0.910)
        /// F1 Carbon Black (#15151E). Page background.
        static let ink = SwiftUI.Color(red: 0.082, green: 0.082, blue: 0.118)
        /// Dark navy panel (#12121C). Cards, headers, rows.
        static let panel = SwiftUI.Color(red: 0.071, green: 0.071, blue: 0.110)
        /// Fastest lap / personal record (#BF00FF). F1 purple sector coding.
        static let session = SwiftUI.Color(red: 0.749, green: 0.000, blue: 1.000)
        /// Time gained. (#00C853)
        static let gain = SwiftUI.Color(red: 0.000, green: 0.784, blue: 0.325)
        /// Championship gold / P1 treatment. (#FFD100)
        static let notice = SwiftUI.Color(red: 1.000, green: 0.820, blue: 0.000)

        /// Secondary text. 55% cream on ink clears AA at 13pt.
        static let muted = cream.opacity(0.55)
        /// Labels and disabled states. Large or heavy type only.
        static let faint = cream.opacity(0.38)
        /// Hairlines and rule separators.
        static let rule = cream.opacity(0.12)

        /// Delta colouring from the player's POV: negative = faster = good.
        static func delta(_ millis: Int) -> SwiftUI.Color {
            if millis < 0 { return gain }
            if millis > 0 { return signal }
            return muted
        }
    }

    // MARK: - Type

    enum Font {
        /// Track names, lap times, headings. Condensed + heavy.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .heavy).width(.condensed)
        }

        /// Option names and anything read as a word.
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }

        /// Values that must align: lap times, credits, deltas.
        static func data(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// All-caps micro-label. Always use `.apexLabel()` — it adds tracking.
        static func label(_ size: CGFloat = 9.5) -> SwiftUI.Font {
            .system(size: size, weight: .heavy)
        }
    }

    // MARK: - Metrics

    enum Metric {
        static let labelTracking: CGFloat = 1.9
        static let displayTracking: CGFloat = -0.6
        /// Sharp F1 style. Cards and row corners use this.
        static let cardRadius: CGFloat = 4
        static let gutter: CGFloat = 16
    }
}

// MARK: - Modifiers

extension View {

    /// All-caps micro-label. Uppercasing here keeps call-sites readable.
    func apexLabel(_ color: Color = Theme.Color.faint) -> some View {
        self.font(Theme.Font.label())
            .tracking(Theme.Metric.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func apexDisplay(_ size: CGFloat, color: Color = Theme.Color.cream) -> some View {
        self.font(Theme.Font.display(size))
            .tracking(Theme.Metric.displayTracking)
            .foregroundStyle(color)
    }

    func apexData(_ size: CGFloat, weight: Font.Weight = .semibold, color: Color = Theme.Color.cream) -> some View {
        self.font(Theme.Font.data(size, weight: weight))
            .foregroundStyle(color)
    }

    /// Raised surface. Sharp corners — F1 timing tower aesthetic.
    func apexCard() -> some View {
        self.background(Theme.Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
    }

    /// Primary CTA: F1 Warm Red fill with cream text.
    func apexPrimaryButton() -> some View {
        self.font(Theme.Font.display(15))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Color.signal)
    }

    /// Full-bleed notice strip. Ink text on high-vis fill.
    func apexNotice(_ fill: Color = Theme.Color.notice) -> some View {
        self.font(Theme.Font.label(10))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.vertical, 9)
            .background(fill)
    }
}

extension View {

    /// Quiet secondary button: outlined, not filled.
    func apexSecondaryButton() -> some View {
        self.font(Theme.Font.label(11))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                Rectangle()
                    .stroke(Theme.Color.cream.opacity(0.30), lineWidth: 1)
            )
    }
}
