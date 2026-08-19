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
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: beat.icon)
                            .font(.system(size: 52))
                            .foregroundStyle(Theme.Color.signal)
                        Text("Beat \(index + 1) of \(beats.count)")
                            .apexLabel(Theme.Color.faint)
                        Text(beat.title)
                            .apexDisplay(30)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Text(beat.body)
                            .font(Theme.Font.body(15, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, 34)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            // indexDisplayMode .never: the dots were the system's blue
            // capsule on a black pill, the last piece of stock chrome on
            // the first screen anyone sees. The beat counter above each
            // page says the same thing in the app's own voice.
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button {
                if page < beats.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinished()
                }
            } label: {
                Text(page < beats.count - 1 ? "Next" : "Enter the paddock")
                    .apexPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.ink)
        .interactiveDismissDisabled()
    }
}

#Preview {
    OnboardingView(onFinished: {})
        .preferredColorScheme(.dark)
}
