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
             body: "Fit all 8 systems in the garage for today's circuit."),
        Step(icon: "lock.fill", title: "Lock",
             body: "Hold to lock your setup. One Daily submission, no undo."),
        Step(icon: "flag.checkered", title: "Race",
             body: "Lights out: 3 laps against five rival teams."),
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
                bullet("square.grid.2x2", "The garage shows all eight systems at once. Tap one to see its three options; dashed tiles are still open. Swipe or use the arrows to move between systems.")
                bullet("wand.and.stars", "Every option shows its main upside in green and its main cost in grey. There is no hidden math, and there is no option without a cost — that is the game.")
                bullet("dot.radiowaves.left.and.right", "The pit wall reacts to every pick, using only what's on screen: the circuit's demands, the weather and your budget. It never gives away the answer.")
                bullet("dollarsign.circle", "Select anything, even over budget. The total turns red — only locking is blocked, not the tap.")
                bullet("exclamationmark.triangle.fill", "Most days carry a technical regulation: one option the stewards have outlawed. It's shown on the brief and struck through in the bay.")
                bullet("chart.bar.xaxis", "\"What decides today\" shows the four systems this circuit rewards most. The bar is your car's level; the percentage is how much of the lap that system is worth.")
            } header: { Text("Building your car").apexLabel(Theme.Color.muted) }

            Section {
                bullet("flag.2.crossed", "You race five rival teams, each with its own philosophy: Low Drag, High Downforce, Endurance, Balanced and All Attack. They follow today's budget and regulation too.")
                bullet("list.number", "Your position updates live. The final classification ranks every car by average lap.")
                bullet("antenna.radiowaves.left.and.right", "Team radio calls out what's working and what isn't — the parts that are winning or losing you time.")
            } header: { Text("Race day").apexLabel(Theme.Color.muted) }

            Section {
                bullet("rosette", "Medals: Gold, Silver or Bronze for landing in the top 1%, 10% or third of every legal setup today. The target lap times are shown in the bay before you lock — times only, never parts.")
                bullet("square.and.arrow.up", "Share your result from the finish line or the debrief. The card shows your position, medal and sectors — never your setup, so it can't spoil anyone's day.")
                bullet("timer", "Average Lap is official. Lap 3 usually shows wear and heat catching up with aggressive setups.")
                bullet("chart.bar.fill", "\"Where the lap went\" compares each of your sectors to the optimal setup for the day. The three numbers add up to your gap.")
                bullet("percent", "Possible setups beaten compares you to every car that was legal today — after the budget and the day's regulation rule the rest out.")
                bullet("globe", "Global Standing compares you to other engineers who played today.")
                bullet("lock.fill", "The optimal setup stays hidden until the day closes, so it can't spoil others still playing.")
            } header: { Text("Reading the debrief").apexLabel(Theme.Color.muted) }

            Section {
                bullet("flask.fill", "Experiment: replay today's exact conditions with a different setup — and watch it race your official car. Unlimited, unofficial.")
                bullet("flag.checkered", "Quick Race: a surprise circuit and weather, right now.")
                bullet("slider.horizontal.3", "Test Lab: pick your own circuit, weather, and budget.")
            } header: { Text("Practice modes").apexLabel(Theme.Color.muted) }

            Section {
                bullet("flame.fill", "Submit on consecutive UTC days to build a streak. Miss a day and it resets.")
                bullet("bell.fill", "Want a nudge? Turn on the daily reminder after a race, and pick its time in Settings.")
            } header: { Text("Streak & reminders").apexLabel(Theme.Color.muted) }

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
