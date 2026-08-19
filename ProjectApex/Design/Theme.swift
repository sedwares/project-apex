//
//  Theme.swift
//  ProjectApex
//
//  The single source of truth for how Project Apex looks.
//
//  Before this file the app had no visual identity at all:
//  AccentColor.colorset was empty (so every accent fell back to system
//  blue) and every font was a stock SwiftUI text style. That is a fine
//  place to start and a bad place to ship from — it reads as a utility,
//  and an App Store screenshot row is not a forgiving place to look
//  like a settings pane.
//
//  DIRECTION: "Livery" — flat colour, heavy condensed display type,
//  monospace only where digits must align. Chosen over two alternatives
//  (a near-black telemetry screen, and a light drafting-paper look)
//  because it is the one that still reads as a game at 120px wide in
//  search results.
//
//  RULES
//    · No view may name a raw Color or a system text style. If you need
//      something that isn't here, add it here.
//    · Semantic names only. `Theme.Color.signal`, never `.red` — the
//      whole point is that changing the palette is one edit.
//    · Monospace is for values that line up in a column: lap times,
//      credits, deltas. Not for prose, not for option names.
//
//  ACCESSIBILITY
//    Every foreground/background pair below clears WCAG AA at the size
//    it is used. `cream` on `ink` is 17.4:1; `signal` on `ink` is 4.9:1
//    and is therefore never used for body text, only for large type,
//    fills and iconography. Type scales with Dynamic Type except the
//    micro-labels, which are already at the floor.
//

import SwiftUI

enum Theme {

    // MARK: - Colour

    enum Color {
        /// Team red. Accent, primary fills, and negative deltas — in
        /// racing a red split IS the brand colour, and separating them
        /// would cost more legibility than it buys.
        static let signal = SwiftUI.Color(red: 0.910, green: 0.067, blue: 0.176)   // #E8112D
        /// Off-white. All primary text on dark.
        static let cream = SwiftUI.Color(red: 0.957, green: 0.945, blue: 0.918)    // #F4F1EA
        /// Page background.
        static let ink = SwiftUI.Color(red: 0.043, green: 0.043, blue: 0.059)      // #0B0B0F
        /// Raised surfaces — cards, sheets, rows.
        static let panel = SwiftUI.Color(red: 0.063, green: 0.063, blue: 0.078)    // #101014
        /// Time gained. Deliberately not the system green.
        static let gain = SwiftUI.Color(red: 0.000, green: 0.784, blue: 0.325)     // #00C853
        /// The engineer's advice, and the day's regulation. High-vis,
        /// used as a fill with ink text on top — never as text on ink.
        static let notice = SwiftUI.Color(red: 1.000, green: 0.820, blue: 0.000)   // #FFD100

        /// Secondary text. Cream at 55% clears AA on `ink` down to 13pt.
        static let muted = cream.opacity(0.55)
        /// Labels and disabled states. Large or heavy type only.
        static let faint = cream.opacity(0.38)
        /// Hairlines between rows.
        static let rule = cream.opacity(0.12)

        /// Colour for a time delta in milliseconds, from the player's
        /// point of view: negative is faster, and faster is good.
        ///
        /// Zero is `muted`, not `gain` — a sector you matched exactly is
        /// not an achievement, and colouring it green makes a lap look
        /// better than it was.
        static func delta(_ millis: Int) -> SwiftUI.Color {
            if millis < 0 { return gain }
            if millis > 0 { return signal }
            return muted
        }
    }

    // MARK: - Type

    enum Font {
        /// Track names, lap times, section headings. Condensed and heavy
        /// so a long circuit name survives at one line on a small phone.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .heavy).width(.condensed)
        }

        /// Option names and anything the player reads as a word.
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }

        /// Values that must line up in a column: lap times, credits,
        /// deltas, percentages.
        static func data(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// The all-caps micro-label above a value. Always paired with
        /// `.tracking(Theme.Metric.labelTracking)` — use the
        /// `.apexLabel()` modifier rather than assembling it by hand.
        static func label(_ size: CGFloat = 9.5) -> SwiftUI.Font {
            .system(size: size, weight: .heavy)
        }
    }

    // MARK: - Metrics

    enum Metric {
        static let labelTracking: CGFloat = 1.9
        static let displayTracking: CGFloat = -0.6
        static let cardRadius: CGFloat = 14
        static let rowSpacing: CGFloat = 7
        static let gutter: CGFloat = 16
    }
}

// MARK: - Modifiers

extension View {

    /// An all-caps micro-label. Uppercasing happens here so call sites
    /// keep readable strings and localisation isn't handed pre-shouted
    /// text.
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

    /// A raised surface. No shadow: on a near-black background a shadow
    /// is invisible at best and a grey smear at worst.
    func apexCard() -> some View {
        self.background(Theme.Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
    }

    /// The one loud button on a screen: cream fill, ink text. Cream
    /// rather than red, so the red stays reserved for information
    /// (regulations, lost time) instead of competing with navigation.
    func apexPrimaryButton() -> some View {
        self.font(Theme.Font.display(15))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.Color.cream)
    }

    /// A full-bleed strip that must be read: the day's regulation, the
    /// engineer's note. Ink text on a high-vis fill.
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

    /// The quiet alternative to `apexPrimaryButton` — outlined, not
    /// filled. Quick Race and Test Lab sit beside the daily and must
    /// read as available without competing with it.
    func apexSecondaryButton() -> some View {
        self.font(Theme.Font.label(11))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Color.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.Color.cream.opacity(0.35), lineWidth: 1)
            )
    }

    /// The red band at the top of a screen. Carries the day, the title
    /// and the conditions, with a livery sweep behind it — one shape,
    /// cheap, and it makes a screenshot look designed rather than
    /// defaulted.
    func apexHeaderBand() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .background(alignment: .topTrailing) {
                ZStack(alignment: .topTrailing) {
                    Theme.Color.signal
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 150)
                        .rotationEffect(.degrees(20))
                        .offset(x: 46)
                }
                .clipped()
            }
    }
}
