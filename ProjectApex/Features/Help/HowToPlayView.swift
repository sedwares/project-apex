//
//  HowToPlayView.swift
//  ProjectApex
//
//  Restructured per review: scannable icon-led cards over prose
//  bullets. The 5-step loop up top answers "how do I play in 10
//  seconds"; supporting detail sections follow for anyone who wants
//  the full rules. No art dependency — SF Symbols only.
//

import SwiftUI

struct HowToPlayView: View {

    private struct Step {
        let icon: String
        let title: String
        let body: String
    }

    private let loop: [Step] = [
        Step(icon: "wrench.and.screwdriver.fill", title: "Build",
             body: "Choose 8 engineering systems for today's circuit."),
        Step(icon: "lock.fill", title: "Lock",
             body: "One Daily submission. No undo."),
        Step(icon: "flag.checkered", title: "Watch",
             body: "Your setup runs a deterministic 3-lap simulation."),
        Step(icon: "chart.line.uptrend.xyaxis", title: "Learn",
             body: "The debrief shows exactly where you gained or lost time."),
        Step(icon: "flask.fill", title: "Experiment",
             body: "Try alternatives — your official result never changes.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(loop, id: \.title) { step in
                    HStack(spacing: 14) {
                        Image(systemName: step.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Color.signal)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).apexDisplay(17)
                            Text(step.body)
                                .font(Theme.Font.body(12, weight: .regular))
                                .foregroundStyle(Theme.Color.muted)
                        }
                    }
                    .padding(.vertical, 5)
                }
            } header: { Text("The loop").apexLabel(Theme.Color.muted) }

            Section {
                bullet("wand.and.stars", "Every option shows its main upside in green and its main cost in grey. There is no hidden math, and there is no option without a cost — that is the game.")
                bullet("dollarsign.circle", "Select anything, even over budget. The total turns red — only Submit is blocked, not the tap.")
                bullet("exclamationmark.triangle.fill", "Most days carry a technical regulation: one option the stewards have outlawed. It's shown on the brief and struck through in the bay.")
                bullet("chart.bar.xaxis", "\"What decides today\" shows the four systems this circuit rewards most. The bar is your car's level; the percentage is how much of the lap that system is worth.")
            } header: { Text("Building your car").apexLabel(Theme.Color.muted) }

            Section {
                bullet("timer", "Average Lap is official. Lap 3 usually shows wear and heat catching up with aggressive setups.")
                bullet("chart.bar.fill", "\"Where the lap went\" compares each of your sectors to the optimal setup for the day. The three numbers add up to your gap.")
                bullet("percent", "Possible setups beaten compares you to every car that was legal today — after the budget and the day's regulation rule the rest out.")
                bullet("globe", "Global Standing compares you to other engineers who played today.")
                bullet("lock.fill", "The optimal setup stays hidden until the day closes, so it can't spoil others still playing.")
            } header: { Text("Reading the debrief").apexLabel(Theme.Color.muted) }

            Section {
                bullet("flask.fill", "Experiment: replay today's exact conditions with a different setup. Unlimited, unofficial.")
                bullet("flag.checkered", "Quick Race: a surprise circuit and weather, right now.")
                bullet("slider.horizontal.3", "Test Lab: pick your own circuit, weather, and budget.")
            } header: { Text("Practice modes").apexLabel(Theme.Color.muted) }

            Section {
                bullet("flame.fill", "Submit on consecutive UTC days to build a streak. Miss a day and it resets.")
            } header: { Text("Streak").apexLabel(Theme.Color.muted) }

            Section {
                bullet("checkmark.seal.fill", "Fixed-point deterministic simulation — no randomness. Same setup, same result, on any device, forever.")
            } header: { Text("Why the numbers never lie").apexLabel(Theme.Color.muted) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .listRowBackground(Theme.Color.panel)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.faint)
                .frame(width: 18)
            Text(text)
                .font(Theme.Font.body(13, weight: .regular))
                .foregroundStyle(Theme.Color.cream)
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.Color.panel)
        .listRowSeparatorTint(Theme.Color.rule)
    }
}

#Preview {
    NavigationStack { HowToPlayView() }
        .preferredColorScheme(.dark)
}
