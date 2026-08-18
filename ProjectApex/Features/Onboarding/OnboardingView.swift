//
//  OnboardingView.swift
//  ProjectApex
//
//  First-launch only (§26): set the fantasy, explain the loop, get out
//  of the way. Three beats, no tutorial gauntlet — the Daily teaches
//  the rest better than any walkthrough could.
//

import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void
    @State private var page = 0

    private struct Beat {
        let icon: String
        let title: String
        let body: String
    }

    private let beats: [Beat] = [
        Beat(
            icon: "wrench.and.screwdriver.fill",
            title: "You're the Chief Engineer",
            body: "You don't drive the car — you design it. Eight decisions, one budget, and a circuit that punishes the wrong trade-offs."
        ),
        Beat(
            icon: "calendar.badge.clock",
            title: "One challenge. One submission.",
            body: "Every engineer in the world gets the same circuit, the same weather, the same budget — every day. Lock your setup, watch the laps, live with it."
        ),
        Beat(
            icon: "chart.line.uptrend.xyaxis",
            title: "Lose like an engineer",
            body: "The debrief tells you exactly where the time went — and what to try tomorrow. The best setups aren't guessed. They're learned."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(beats.enumerated()), id: \.offset) { index, beat in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: beat.icon)
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                        Text(beat.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(beat.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < beats.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinished()
                }
            } label: {
                Text(page < beats.count - 1 ? "Next" : "Enter the Paddock")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
