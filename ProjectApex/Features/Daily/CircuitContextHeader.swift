//
//  CircuitContextHeader.swift
//  ProjectApex
//
//  A compact "what you're building for" strip pinned atop every build
//  screen (Daily Bay, Quick Race, Custom Test). Reuses the section
//  glyphs and weather effects so the player never loses the context of
//  their decisions.
//
//  Livery: the archetype is condensed display type, the conditions sit
//  to the right as a micro-label, and the layout glyphs run underneath.
//  Deliberately quieter than the home screen's header band — this one is
//  pinned above a scrolling list of choices and has to stay out of the
//  way of the thing you came here to do.
//

import SwiftUI
import ProjectApexCore

struct CircuitContextHeader: View {
    let circuit: Circuit
    let weather: Weather
    let budget: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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

            HStack(spacing: 6) {
                ForEach(Array(circuit.sections.enumerated()), id: \.offset) { _, section in
                    Image(systemName: glyph(for: section))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Color.faint)
                }
                Spacer(minLength: 0)
            }

            Text(weatherEffect(weather))
                .font(Theme.Font.body(11, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(Theme.Color.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    private func glyph(for section: TrackSectionType) -> String {
        switch section {
        case .longStraight, .shortStraight: return "arrow.right"
        case .finalStraight: return "flag.checkered"
        case .heavyBrakingZone: return "octagon"
        case .hairpin: return "arrow.uturn.down"
        case .slowCorner, .mediumCorner: return "arrow.turn.up.right"
        case .fastCorner: return "arrow.up.right"
        case .technicalSector: return "scribble"
        case .elevationClimb: return "arrow.up.forward"
        case .elevationDrop: return "arrow.down.forward"
        case .bumpySector: return "waveform.path"
        }
    }

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
