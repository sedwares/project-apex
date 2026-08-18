//
//  SimulationReplayView.swift
//  ProjectApex
//
//  The race ceremony, now a real presentation: a SpriteKit scene shows
//  the car lapping an abstract circuit while live telemetry gauges —
//  fed by the deterministic TelemetryTimeline — climb and fall exactly
//  as the sim dictated. Engineer radio fires against the same clock.
//  The scene renders; it never computes. Skippable throughout.
//

import SwiftUI
import SpriteKit
import ProjectApexCore

struct SimulationReplayView: View {
    let result: SimulationResult
    let challenge: DailyChallenge
    let onFinished: () -> Void

    @State private var grip = 0.0
    @State private var heat = 0.0
    @State private var tire = 0.0
    @State private var lapLabel = "LAP 1"
    @State private var radio: String?
    @State private var scene: RaceScene?

    private let secondsPerLap = 2.6
    private let sceneHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 18) {
            header

            // Fixed frame either way, so the layout never shifts when
            // the scene arrives.
            ZStack {
                if let scene {
                    SpriteView(scene: scene).clipped()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: sceneHeight)

            gauges

            Text(radio.map { "“\($0)”" } ?? " ")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
                .frame(height: 20)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: radio)

            Spacer(minLength: 0)

            Button("Skip") { onFinished() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .padding(.top, 24)
        .onAppear(perform: buildScene)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(challenge.circuit.name)
                .font(.headline)
            Text("\(challenge.circuit.archetype.displayName) · \(challenge.weather.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(lapLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .kerning(2)
                .padding(.top, 4)
        }
    }

    private var gauges: some View {
        HStack(spacing: 14) {
            gauge("GRIP", value: grip, tint: .green)
            gauge("HEAT", value: heat, tint: .orange, invert: true)
            gauge("TIRE", value: tire, tint: .blue)
        }
        .padding(.horizontal, 28)
    }

    /// `invert` = higher is worse (heat): amber past 65%, red past 80%,
    /// with a subtle pulse above 85% so danger actually feels dangerous.
    ///
    /// Values are clamped to 0...1 for PRESENTATION ONLY — Core keeps
    /// its raw numbers, which the debrief and leaderboard depend on.
    /// An unclamped value overran its track and printed e.g. "118%".
    private func gauge(_ label: String, value rawValue: Double, tint: Color, invert: Bool = false) -> some View {
        let value = min(max(rawValue, 0), 1)

        let dangerColor: Color = {
            guard invert else { return tint }
            if value > 0.80 { return .red }
            if value > 0.65 { return .orange }
            return tint
        }()
        let pulsing = invert && value > 0.85

        return VStack(spacing: 6) {
            Text("\(label) \(Int(value * 100))%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .kerning(0.5)
            GeometryReader { proxy in
                // RoundedRectangle, not Capsule: a capsule's end caps
                // are half its height, so a 20% fill and a 70% fill
                // read far closer than they are. This is the TIRE/HEAT
                // inconsistency.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(dangerColor)
                        .frame(height: max(2, proxy.size.height * value))
                        .opacity(pulsing ? 0.7 : 1.0)
                        .animation(
                            pulsing
                                ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                : .easeOut(duration: 0.2),
                            value: pulsing
                        )
                }
            }
            .frame(height: 54)
            .animation(.easeOut(duration: 0.2), value: value)
        }
        .frame(maxWidth: .infinity)
    }

    private func buildScene() {
        let sectionsPerLap = challenge.circuit.sections.count
        let samples = TelemetryTimeline.samples(for: result, sectionsPerLap: sectionsPerLap)
        let radioFeed = FeedbackEngine.radioMessages(for: result, weather: challenge.weather)
        var radioIndex = 0
        var lastLap = 0

        // Size roughly matches the on-screen frame; .resizeFill in
        // didMove keeps the loop fitted to whatever it becomes.
        let scene = RaceScene(size: CGSize(width: 390, height: sceneHeight))
        scene.configure(.init(
            samples: samples,
            sectionsPerLap: sectionsPerLap,
            totalLaps: result.lapResults.count,
            secondsPerLap: secondsPerLap
        ))
        scene.onSample = { sample in
            grip = sample.grip
            heat = sample.heat
            tire = sample.tireLife
            if sample.lap != lastLap {
                lastLap = sample.lap
                lapLabel = "LAP \(sample.lap)"
            }
            // Fire radio whose moment has arrived.
            let runFrac = sample.runProgress
            while radioIndex < radioFeed.count {
                let m = radioFeed[radioIndex]
                let mFrac = (Double(m.lap - 1) + m.atFraction) / Double(result.lapResults.count)
                if mFrac <= runFrac {
                    radio = m.text
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    radioIndex += 1
                } else { break }
            }
        }
        scene.onFinished = {
            radio = nil
            lapLabel = "FINISH"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onFinished() }
        }
        self.scene = scene
    }
}
