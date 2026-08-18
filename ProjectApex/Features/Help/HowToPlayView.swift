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
            Section("The Loop") {
                ForEach(loop, id: \.title) { step in
                    HStack(spacing: 14) {
                        Image(systemName: step.icon)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.headline)
                            Text(step.body).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Building Your Car") {
                bullet("wand.and.stars", "Every option shows a green upside and an orange downside — no hidden math.")
                bullet("dollarsign.circle", "Select anything, even over budget. The total turns red — only Submit is blocked, not the tap.")
                bullet("exclamationmark.triangle.fill", "Most days carry a technical regulation: one option the stewards have outlawed. It's shown on the brief and struck through in the bay.")
            }

            Section("Reading the Debrief") {
                bullet("timer", "Average Lap is official. Lap 3 usually shows wear and heat catching up with aggressive setups.")
                bullet("chart.bar.fill", "Sectors vs neutral car shows exactly where time was gained or lost.")
                bullet("percent", "Possible setups beaten compares you to every car that was legal today — after the budget and the day's regulation rule the rest out.")
                bullet("globe", "Global Standing compares you to other engineers who played today.")
                bullet("lock.fill", "The optimal setup stays hidden until the day closes, so it can't spoil others still playing.")
            }

            Section("Practice Modes") {
                bullet("flask.fill", "Experiment: replay today's exact conditions with a different setup. Unlimited, unofficial.")
                bullet("flag.checkered", "Quick Race: a surprise circuit and weather, right now.")
                bullet("slider.horizontal.3", "Test Lab: pick your own circuit, weather, and budget.")
            }

            Section("Streak") {
                bullet("flame.fill", "Submit on consecutive UTC days to build a streak. Miss a day and it resets.")
            }

            Section("Why the Numbers Never Lie") {
                bullet("checkmark.seal.fill", "Fixed-point deterministic simulation — no randomness. Same setup, same result, on any device, forever.")
            }
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { HowToPlayView() }
}
