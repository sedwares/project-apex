//
//  CircuitContextHeader.swift
//  ProjectApex
//
//  A compact "what you're building for" strip pinned atop every build
//  screen (Daily Bay, Quick Race, Custom Test). Reuses the section
//  glyphs and weather effects so the player never loses the context of
//  their decisions.
//

import SwiftUI
import ProjectApexCore

struct CircuitContextHeader: View {
    let circuit: Circuit
    let weather: Weather
    let budget: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(circuit.archetype.displayName, systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Label(weather.displayName, systemImage: weatherSymbol(weather))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(Array(circuit.sections.enumerated()), id: \.offset) { _, section in
                    Image(systemName: glyph(for: section))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(weatherEffect(weather))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
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
