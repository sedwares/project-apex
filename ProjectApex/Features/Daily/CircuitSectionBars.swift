//
//  CircuitSectionBars.swift
//  ProjectApex
//
//  The circuit profile strip: one bar per track section, left to right in
//  lap order.
//
//  ── WHY THIS EXISTS ────────────────────────────────────────────────
//  DailyHomeView and CircuitContextHeader each carried their own private
//  copy of the width table and the colour table. Identical today, free to
//  drift tomorrow — the same duplication that let SectorTier's thresholds
//  contradict the debrief prose. One strip, one definition.
//
//  Two things were also wrong with the strip itself, and both are fixed
//  here:
//
//  1. The FIRST SECTION's bar was painted signal red as a lap-start
//     marker. That overwrote real data: section 1's character became
//     invisible, and a circuit opening with a Heavy Braking Zone looked
//     exactly like one opening with a Long Straight. The marker is now a
//     separate tick, so every bar shows its own type.
//
//  2. Colour and width collided. `fastCorner` and `finalStraight` shared
//     both a width (18) and a colour, so they were indistinguishable, and
//     the two cream tiers sat at 14% and 28% opacity — a difference that
//     does not survive a 3pt bar on a near-black panel. Widths are now
//     unique within a colour family, and the families are far enough
//     apart to read.
//
//  The strip is deliberately not self-explanatory — no picture of eleven
//  bars is. Whoever shows it is expected to print
//  `circuit.compositionSummary()` beside it, which says the same thing in
//  words.
//

import SwiftUI
import ProjectApexCore

struct CircuitSectionBars: View {
    let sections: [TrackSectionType]
    var height: CGFloat = 3

    var body: some View {
        HStack(spacing: 2) {
            // Lap start marker — taller than the bars and clearly not one
            // of them, so it orients the lap without claiming a section.
            Rectangle()
                .fill(Theme.Color.signal)
                .frame(width: 2, height: height + 4)

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Rectangle()
                    .fill(Self.color(of: section))
                    .frame(width: Self.width(of: section), height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Circuit profile")
        .accessibilityValue(sections.compositionSummary())
    }

    // MARK: - Bar spec

    /// Width reads as the section's weight on the lap: straights run wide,
    /// hairpins narrow. Unique within a colour family so that two bars of
    /// the same colour are never the same size.
    static func width(of section: TrackSectionType) -> CGFloat {
        switch section {
        case .longStraight:      return 22
        case .finalStraight:     return 18
        case .shortStraight:     return 9
        case .heavyBrakingZone:  return 11
        case .fastCorner:        return 16
        case .mediumCorner:      return 13
        case .technicalSector:   return 12
        case .slowCorner:        return 10
        case .hairpin:           return 7
        case .elevationClimb:    return 15
        case .elevationDrop:     return 14
        case .bumpySector:       return 8
        }
    }

    /// Colour is the section FAMILY, the same grouping
    /// `compositionSummary()` names in words — so the picture and the
    /// sentence below it are one taxonomy, not two.
    static func color(of section: TrackSectionType) -> Color {
        switch section.family {
        case .straight: return Theme.Color.cream.opacity(0.58)   // flat out
        case .braking:  return Theme.Color.notice.opacity(0.80)  // caution
        case .corner:   return Theme.Color.cream.opacity(0.34)
        case .climb:    return Theme.Color.cream.opacity(0.26)
        case .drop:     return Theme.Color.cream.opacity(0.18)
        case .bumpy:    return Theme.Color.cream.opacity(0.18)
        }
    }
}
