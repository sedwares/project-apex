//
//  LockInSequence.swift
//  ProjectApex
//
//  What happens between "Setup locked" and lights out.
//
//  It used to be nothing: submit, and the replay slid up. Now the car
//  you just built sits on screen for a beat under a LOCKED stamp, then
//  leaves the garage — accelerates up and off the top edge — and the
//  race begins. About 1.2 seconds, tap anywhere to skip, and skipped
//  entirely under Reduce Motion.
//
//  It runs INSIDE the replay's full-screen cover and hands over to
//  SimulationReplayView in place. Chaining two presentations (an intro
//  cover, then the replay cover) is the pattern that leaves stray
//  layers on screen; one cover with an internal stage switch cannot.
//

import SwiftUI
import ProjectApexCore

struct LockInSequence: View {
    let selections: [EngineeringCategoryID: EngineeringOptionID]
    let result: SimulationResult
    let challenge: DailyChallenge
    let onFinished: () -> Void

    private enum Stage { case garage, race }

    @State private var stage: Stage = .garage
    @State private var stamped = false
    @State private var rolling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Color.ink.ignoresSafeArea()

            switch stage {
            case .garage:
                garage
                    .transition(.opacity)
            case .race:
                SimulationReplayView(result: result, challenge: challenge, dailyShare: true, onFinished: onFinished)
                    .transition(.opacity)
            }
        }
        .task { await run() }
    }

    // MARK: - Garage

    private var garage: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 6) {
                Text(dayLine).apexLabel(Theme.Color.muted)
                Text("Setup locked")
                    .apexDisplay(34, color: Theme.Color.cream)
                    .textCase(.uppercase)
            }
            .scaleEffect(stamped ? 1 : 1.35)
            .opacity(stamped ? 1 : 0)

            ZStack {
                // Heat haze under the car as it pulls away.
                LinearGradient(colors: [Theme.Color.signal.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 40, height: 140)
                    .offset(y: 120)
                    .opacity(rolling ? 1 : 0)

                SetupCarView(selections: selections)
                    .frame(height: 250)
            }
            .offset(y: rolling ? -1_000 : 0)
            .scaleEffect(rolling ? 0.86 : 1)

            Text(result.setupIdentity.displayText)
                .font(Theme.Font.body(13, weight: .semibold))
                .foregroundStyle(Theme.Color.muted)
                .opacity(stamped && !rolling ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .contentShape(Rectangle())
        .onTapGesture { goRacing() }
        .sensoryFeedback(.impact(weight: .medium), trigger: rolling) { _, new in new }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup locked. \(result.setupIdentity.displayText).")
    }

    private var dayLine: String {
        let archetype = challenge.circuit.archetype.displayName
        if let day = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey) {
            return "Day \(day) · \(archetype)"
        }
        return archetype
    }

    // MARK: - Timing

    private func run() async {
        if reduceMotion {
            stage = .race
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { stamped = true }

        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, stage == .garage else { return }
        withAnimation(.easeIn(duration: 0.55)) { rolling = true }

        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }
        goRacing()
    }

    private func goRacing() {
        guard stage == .garage else { return }
        withAnimation(.easeInOut(duration: 0.25)) { stage = .race }
    }
}
