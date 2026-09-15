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

            // Row 2: circuit profile strip + budget.
            // Bars read left→right in lap order, after the start tick.
            HStack(alignment: .center, spacing: 0) {
                CircuitSectionBars(sections: circuit.sections)
                Spacer(minLength: 8)
                Text("\(budget) CR")
                    .apexData(11, weight: .medium, color: Theme.Color.muted)
            }

            // Row 3: the strip above, in words. A row of eleven
            // rectangles cannot say "this lap is mostly corners" by
            // itself — this is the line that decodes it.
            Text(circuit.compositionSummary())
                .font(Theme.Font.body(10.5, weight: .medium))
                .foregroundStyle(Theme.Color.faint)

            // Row 4: weather modifier — one sentence on how today differs
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
