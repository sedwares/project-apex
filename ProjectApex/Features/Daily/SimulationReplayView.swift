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
                .font(Theme.Font.body(13, weight: .regular).italic())
                .foregroundStyle(Theme.Color.muted)
                .frame(height: 20)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: radio)

            Spacer(minLength: 0)

            Button { onFinished() } label: {
                Text("Skip").apexLabel(Theme.Color.muted)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.ink)
        .onAppear(perform: buildScene)
    }

    private var header: some View {
        VStack(spacing: 5) {
            Text(challenge.circuit.name).apexDisplay(20)
            Text("\(challenge.circuit.archetype.displayName) · \(challenge.weather.displayName)")
                .font(Theme.Font.body(12.5, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
            Text(lapLabel)
                .apexLabel(Theme.Color.signal)
                .padding(.top, 5)
        }
    }

    private var gauges: some View {
        HStack(spacing: 14) {
            gauge("Grip", value: grip)
            gauge("Heat", value: heat, invert: true)
            gauge("Tire", value: tire)
        }
        .padding(.horizontal, 28)
    }

    /// ONE RULE FOR ALL THREE GAUGES: cream is fine, amber is a warning,
    /// red is trouble.
    ///
    /// These used to be green, orange and blue — three arbitrary hues
    /// that told you which gauge you were looking at (something the
    /// label already does) and nothing about whether it was going well.
    /// Grip at 12% and grip at 95% were the same green. Now the colour
    /// carries the only thing worth carrying, and `invert` just decides
    /// which end of the range is the bad one.
    ///
    /// `invert` = higher is worse (heat). Otherwise lower is worse.
    ///
    /// Values are clamped to 0...1 for PRESENTATION ONLY — Core keeps
    /// its raw numbers, which the debrief and leaderboard depend on.
    /// An unclamped value overran its track and printed e.g. "118%".
    private func gauge(_ label: String, value rawValue: Double, invert: Bool = false) -> some View {
        let value = min(max(rawValue, 0), 1)
        // Distance into the bad end, 0 (fine) to 1 (as bad as it gets).
        let severity = invert ? value : 1 - value

        let dangerColor: Color = {
            if severity > 0.80 { return Theme.Color.signal }
            if severity > 0.65 { return Theme.Color.notice }
            return Theme.Color.cream
        }()
        let pulsing = severity > 0.85

        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(label).apexLabel(Theme.Color.muted)
                Text("\(Int(value * 100))%")
                    .apexData(11, weight: .bold, color: dangerColor)
            }
            GeometryReader { proxy in
                // RoundedRectangle, not Capsule: a capsule's end caps
                // are half its height, so a 20% fill and a 70% fill
                // read far closer than they are. This is the TIRE/HEAT
                // inconsistency.
                // Heat fills from the TOP down; grip and tire from the
                // bottom up. With all three sharing one palette, a low
                // cream bar and a high cream bar both read "fine" — and
                // they are both fine, the colour says so — but heat
                // rising from the floor still looks like progress toward
                // something good. Filling downward makes it look like
                // what it is: something closing in on you.
                ZStack(alignment: invert ? .top : .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.cream.opacity(0.10))
                    RoundedRectangle(cornerRadius: 3)
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
