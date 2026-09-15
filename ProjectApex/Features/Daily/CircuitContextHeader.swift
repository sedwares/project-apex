//
//  CircuitContextHeader.swift
//  ProjectApex
//
//  A compact "what you're building for" strip pinned atop every build
//  screen (Daily Bay, Quick Race, Custom Test). Reuses the section bars
//  and weather effects so the player never loses the context of their
//  decisions.
//
//  F1 RESTYLE (pass 7, fix 1):
//  Timing tower treatment: 4px red left stripe via .overlay(alignment: .leading)
//  so the VStack drives natural height and the stripe never expands to fill
//  all available safeAreaInset space. Section bars + budget inline.
//

import SwiftUI
import ProjectApexCore

struct CircuitContextHeader: View {
    let circuit: Circuit
    let weather: Weather
    let budget: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: archetype name (left) + weather condition (right)
            HStack(alignment: .firstTextBaseline) {
                Text(circuit.archetype.displayName)
                    .apexDisplay(19)
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Image(systemName: weatherSymbol(weather))
                    Text(weather.displayName)
                }
                .apexLabel(Theme.Color.signal)
            }

            // Row 2: circuit section bars + budget
            // Bars read left→right in lap order; first bar is always
            // signal red (entry sector) so you can orient the sequence
            // the same way the Engineering Bay reads it.
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(Array(circuit.sections.enumerated()), id: \.offset) { idx, section in
                        Rectangle()
                            .fill(idx == 0 ? Theme.Color.signal : sectionBarColor(section))
                            .frame(width: sectionBarWidth(section), height: 3)
                    }
                }
                Spacer(minLength: 8)
                Text("\(budget) CR")
                    .apexData(11, weight: .medium, color: Theme.Color.muted)
            }

            // Row 3: weather modifier — one sentence on how today differs
            Text(weatherEffect(weather))
                .font(Theme.Font.body(11, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Extra leading padding clears the 4px stripe overlay.
        .padding(.leading, 16)
        .padding(.trailing, Theme.Metric.gutter)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(Theme.Color.panel)
        // Stripe pinned as overlay so the VStack drives height — never expands.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.Color.signal)
                .frame(width: 4)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    // MARK: - Section bars

    /// Bar widths tuned to the visual weight of each section type.
    /// Straights run wide; braking zones and hairpins run narrow.
    private func sectionBarWidth(_ section: TrackSectionType) -> CGFloat {
        switch section {
        case .longStraight:                     return 22
        case .finalStraight:                    return 18
        case .shortStraight:                    return 9
        case .heavyBrakingZone:                 return 11
        case .hairpin:                          return 8
        case .fastCorner:                       return 18
        case .mediumCorner:                     return 14
        case .slowCorner:                       return 11
        case .technicalSector:                  return 12
        case .elevationClimb, .elevationDrop:   return 15
        case .bumpySector:                      return 13
        }
    }

    /// Colour encodes section character at a glance.
    /// Braking zones are gold-tinted (caution), speed sectors are cream,
    /// the rest are subdued. The first bar is always signal red (see body).
    private func sectionBarColor(_ section: TrackSectionType) -> Color {
        switch section {
        case .heavyBrakingZone, .hairpin:
            return Theme.Color.notice.opacity(0.35)
        case .longStraight, .finalStraight, .fastCorner:
            return Theme.Color.cream.opacity(0.28)
        default:
            return Theme.Color.cream.opacity(0.14)
        }
    }

    // MARK: - Weather helpers

    private func weatherSymbol(_ w: Weather) -> String {
        switch w {
        case .sunny: return "sun.max"
        case .hot: return "thermometer.sun"
        case .cold: return "snowflake"
        case .rain: return "cloud.rain"
        case .windy: return "wind"
        }
    }

    private func weatherEffect(_ w: Weather) -> String {
        switch w {
        case .sunny: return "Clean conditions — pure setup racing"
        case .hot: return "Cooling and tires taxed on the final lap"
        case .cold: return "Slow warm-up, less grip early"
        case .rain: return "Grip and braking cut — stability pays"
        case .windy: return "Stability and aero efficiency taxed"
        }
    }
}
