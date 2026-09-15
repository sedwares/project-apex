//
//  SimulationReplayView.swift
//  ProjectApex
//
//  The race ceremony as a broadcast. The scene renders the day's own
//  circuit; the timing tower beside it reports the lap exactly as F1
//  television would — a running clock, three sector boxes, purple for a
//  session best, green for an improvement. Every number comes from the
//  deterministic result. The view renders; it never computes.
//
//  ── PASS 8 ─────────────────────────────────────────────────────────
//  The screen had the data for a timing tower and showed none of it.
//  `LapResult.sectorTimesMillis` has been there all along; the HUD was
//  three abstract gauges and a lap label. Sector splits are the single
//  most recognisable thing about a motorsport broadcast, and they were
//  one array access away.
//
//  `onSample` also fired 60×/second into three separate @State
//  properties — roughly 180 SwiftUI invalidations a second, each one
//  re-evaluating this view and the SpriteView inside it. The scene now
//  throttles to 12 Hz and hands over one value struct.
//

import SwiftUI
import SpriteKit
import ProjectApexCore

struct SimulationReplayView: View {
    let result: SimulationResult
    let challenge: DailyChallenge
    let onFinished: () -> Void

    /// One struct, one invalidation per update.
    private struct Readout {
        var grip = 0.0
        var heat = 0.0
        var tire = 0.0
        var speed = 0.0
    }

    private struct SectorCell {
        var millis: Int?
        var tone: Tone = .pending
        enum Tone { case pending, session, gain, neutral }
    }

    @State private var readout = Readout()
    @State private var lap = 1
    @State private var sectors: [SectorCell] = Array(repeating: SectorCell(), count: 3)
    @State private var bestSector: [Int] = Array(repeating: .max, count: 3)
    @State private var previousSector: [Int] = Array(repeating: .max, count: 3)
    @State private var bestLapMillis = Int.max
    /// When the CURRENT lap started, in wall time. The clock is computed
    /// from this rather than from telemetry samples.
    @State private var lapStartedAt = Date()
    /// Which lap the sector cells on screen belong to, so a completed
    /// lap's S3 survives long enough to be read.
    @State private var sectorsLap = 1
    @State private var radio: String?
    @State private var scene: RaceScene?
    @State private var finished = false

    private let secondsPerLap = 3.1
    private let sceneHeight: CGFloat = 290

    private var totalLaps: Int { max(result.lapResults.count, 1) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60).clipped()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: sceneHeight)

            timingTower
                .padding(.top, 14)

            gauges
                .padding(.top, 16)

            lapBoard
                .padding(.top, 18)

            ZStack {
                if let radio {
                    Text("“\(radio)”")
                        .font(Theme.Font.body(13, weight: .regular).italic())
                        .foregroundStyle(Theme.Color.muted)
                        .multilineTextAlignment(.center)
                        .id(radio)
                        .transition(.opacity)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.25), value: radio)

            Spacer(minLength: 0)

            Button { onFinished() } label: {
                Text(finished ? "Continue" : "Skip")
                    .apexLabel(finished ? Theme.Color.signal : Theme.Color.muted)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.ink)
        .onAppear(perform: buildScene)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Rectangle()
                .fill(Theme.Color.signal)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.circuit.archetype.displayName).apexDisplay(17)
                Text(challenge.weather.displayName.uppercased())
                    .font(Theme.Font.label(9.5))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Color.muted)
            }
            .padding(.leading, 10)
            Spacer(minLength: 12)
            Text("LAP \(lap)/\(totalLaps)")
                .apexData(15, weight: .bold, color: Theme.Color.cream)
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    // MARK: - Timing tower

    /// The running clock sweeps this lap's REAL time.
    ///
    /// It used to be driven by `sample.runProgress`, which is a
    /// QUANTISED value — Core emits one telemetry sample per track
    /// section, delivered at 12 Hz — so the clock inherited those steps
    /// and visibly jumped rather than ran. Worse, a sample landing near
    /// a lap boundary made `(runProgress × laps) mod 1` collapse to
    /// zero, so the clock read 0:00.000 with two sectors already posted.
    ///
    /// Playback is deterministic: lap N takes exactly its own
    /// `timeMillis`, played over `secondsPerLap` of wall time. So the
    /// clock needs no telemetry at all — just when this lap began.
    private func clockMillis(at date: Date) -> Int {
        let target = result.lapResults.indices.contains(lap - 1)
            ? result.lapResults[lap - 1].timeMillis
            : 0
        if finished { return target }
        let elapsed = date.timeIntervalSince(lapStartedAt)
        let fraction = min(max(elapsed / secondsPerLap, 0), 1)
        return Int(Double(target) * fraction)
    }

    private var timingTower: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: finished)) { ctx in
                    Text(FixedPoint.formatLapTime(millis: clockMillis(at: ctx.date)))
                        .apexData(34, weight: .bold)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("SPEED").apexLabel(Theme.Color.faint)
                    speedBar
                }
            }

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in sectorBox(i) }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    private var speedBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Color.cream.opacity(0.10))
                Rectangle()
                    .fill(readout.speed > 0.85 ? Theme.Color.session : Theme.Color.cream)
                    .frame(width: proxy.size.width * readout.speed)
            }
        }
        .frame(width: 96, height: 5)
        .animation(.easeOut(duration: 0.12), value: readout.speed)
    }

    /// Purple for a session best, green for quicker than last lap,
    /// cream otherwise — the broadcast convention, and the same palette
    /// the debrief already uses for sectors.
    private func sectorBox(_ index: Int) -> some View {
        let cell = sectors[index]
        let tone: Color = {
            switch cell.tone {
            case .session: return Theme.Color.session
            case .gain:    return Theme.Color.gain
            case .neutral: return Theme.Color.cream
            case .pending: return Theme.Color.cream.opacity(0.18)
            }
        }()
        return VStack(spacing: 4) {
            Rectangle().fill(tone).frame(height: 3)
            HStack(spacing: 5) {
                Text("S\(index + 1)").apexLabel(Theme.Color.faint)
                Spacer(minLength: 2)
                Text(cell.millis.map { secondsText($0) } ?? "—")
                    .apexData(12, weight: .bold,
                              color: cell.tone == .pending ? Theme.Color.faint : tone)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 7)
        .padding(.top, 5)
        .background(Theme.Color.panel)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: cell.millis)
    }

    private func secondsText(_ millis: Int) -> String {
        let a = abs(millis)
        return "\(a / 1000).\(String(format: "%03d", a % 1000))"
    }

    // MARK: - Lap board

    /// The run so far, one row per lap, filling in as each is completed.
    ///
    /// It lives here because the lower half of this screen was empty —
    /// the timing tower reports the CURRENT lap and nothing reported the
    /// run. A broadcast always shows both, and the board gives the
    /// replay somewhere to arrive: it is full exactly when the race
    /// ends. The wording matches the debrief's own lap roles, so the
    /// screen the player lands on next reads as a continuation rather
    /// than a different account of the same three laps.
    private var lapBoard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("This run").apexLabel(Theme.Color.faint)
                Spacer()
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            VStack(spacing: 1) {
                ForEach(1...totalLaps, id: \.self) { n in lapRow(n) }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    private func isComplete(_ n: Int) -> Bool { finished || n < lap }

    /// Fastest lap SO FAR. Reading it from the finished result would
    /// print the answer before the car has driven it.
    private var fastestCompletedLap: Int? {
        let done = (1...totalLaps).filter(isComplete)
        guard !done.isEmpty else { return nil }
        return done.min { a, b in
            result.lapResults[a - 1].timeMillis < result.lapResults[b - 1].timeMillis
        }
    }

    private func lapRow(_ n: Int) -> some View {
        let done = isComplete(n)
        let isCurrent = n == lap && !finished
        let isFastest = done && n == fastestCompletedLap && totalLaps > 1
        let millis = result.lapResults.indices.contains(n - 1)
            ? result.lapResults[n - 1].timeMillis : 0
        let stripe: Color = isFastest ? Theme.Color.session
            : (isCurrent ? Theme.Color.signal : Theme.Color.rule)

        return HStack(spacing: 0) {
            Rectangle().fill(stripe).frame(width: 3)
            HStack(spacing: 8) {
                Text("Lap \(n)")
                    .font(Theme.Font.body(13.5))
                    .foregroundStyle(done || isCurrent ? Theme.Color.cream : Theme.Color.faint)
                Text(lapRole(n))
                    .font(Theme.Font.body(11, weight: .regular))
                    .foregroundStyle(Theme.Color.faint)
                Spacer(minLength: 8)
                if isFastest {
                    Text("FL")
                        .font(Theme.Font.label(9))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Color.session)
                }
                if done {
                    Text(FixedPoint.formatLapTime(millis: millis))
                        .apexData(14, weight: .bold,
                                  color: isFastest ? Theme.Color.session : Theme.Color.cream)
                        .monospacedDigit()
                } else {
                    Text("—").apexData(14, weight: .bold, color: Theme.Color.faint)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.Color.panel)
        .animation(.easeOut(duration: 0.25), value: done)
    }

    /// Same words the debrief uses for the same three laps.
    private func lapRole(_ n: Int) -> String {
        switch n {
        case 1: return "warmup"
        case 2: return "peak"
        default: return "wear & heat"
        }
    }

    // MARK: - Gauges

    private var gauges: some View {
        HStack(spacing: 10) {
            gauge("Grip", value: readout.grip)
            gauge("Heat", value: readout.heat, invert: true)
            gauge("Tire", value: readout.tire)
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    /// ONE RULE FOR ALL THREE: cream is fine, gold is a warning, red is
    /// trouble. `invert` = higher is worse (heat). Values are clamped
    /// for PRESENTATION ONLY — Core keeps its raw numbers, which the
    /// debrief and leaderboard depend on.
    private func gauge(_ label: String, value rawValue: Double, invert: Bool = false) -> some View {
        let value = min(max(rawValue, 0), 1)
        let severity = invert ? value : 1 - value
        let tone: Color = {
            if severity > 0.80 { return Theme.Color.signal }
            if severity > 0.65 { return Theme.Color.notice }
            return Theme.Color.cream
        }()

        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(label).apexLabel(Theme.Color.muted)
                Spacer(minLength: 2)
                Text("\(Int(value * 100))%")
                    .apexData(11, weight: .bold, color: tone)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.cream.opacity(0.10))
                    Rectangle()
                        .fill(tone)
                        .frame(width: max(2, proxy.size.width * value))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: value)
    }

    // MARK: - Scene wiring

    private func buildScene() {
        lapStartedAt = Date()
        let sections = challenge.circuit.sections
        let samples = TelemetryTimeline.samples(for: result, sectionsPerLap: sections.count)
        let radioFeed = FeedbackEngine.radioMessages(for: result, weather: challenge.weather)
        var radioIndex = 0

        let scene = RaceScene(size: CGSize(width: 390, height: sceneHeight))
        scene.configure(.init(
            samples: samples,
            sections: sections,
            archetype: challenge.circuit.archetype,
            totalLaps: totalLaps,
            secondsPerLap: secondsPerLap
        ))

        scene.onSample = { sample, speed in
            var next = Readout()
            next.grip = sample.grip
            next.heat = sample.heat
            next.tire = sample.tireLife
            next.speed = speed
            readout = next

            // Fire any radio message whose moment has arrived.
            while radioIndex < radioFeed.count {
                let m = radioFeed[radioIndex]
                let at = (Double(m.lap - 1) + m.atFraction) / Double(totalLaps)
                if at <= sample.runProgress {
                    radio = m.text
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    radioIndex += 1
                } else { break }
            }
        }

        scene.onSectorComplete = { lapNumber, sector in
            recordSector(lap: lapNumber, sector: sector)
        }

        scene.onLapComplete = { completed in
            // Sector 3 closes at the line, so it lands here rather than
            // on a gate crossing.
            recordSector(lap: completed, sector: 2)
            if result.lapResults.indices.contains(completed - 1) {
                let t = result.lapResults[completed - 1].timeMillis
                if t < bestLapMillis {
                    bestLapMillis = t
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }
            if completed < totalLaps {
                lap = completed + 1
                lapStartedAt = Date()
            }
        }

        scene.onFinished = {
            radio = nil
            finished = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onFinished() }
        }

        self.scene = scene
    }

    private func recordSector(lap lapNumber: Int, sector: Int) {
        guard result.lapResults.indices.contains(lapNumber - 1),
              sectors.indices.contains(sector) else { return }

        // First split of a new lap: retire the previous lap's cells now,
        // not when that lap ended. S3 was previously written and wiped
        // in the same frame, so it never appeared at all.
        if lapNumber != sectorsLap {
            previousSector = (0..<3).map { sectors[$0].millis ?? Int.max }
            sectors = Array(repeating: SectorCell(), count: 3)
            sectorsLap = lapNumber
        }
        let times = result.lapResults[lapNumber - 1].sectorTimesMillis
        guard times.indices.contains(sector) else { return }
        let t = times[sector]

        let tone: SectorCell.Tone
        if t < bestSector[sector] {
            bestSector[sector] = t
            tone = .session
        } else if t < previousSector[sector] {
            tone = .gain
        } else {
            tone = .neutral
        }
        sectors[sector] = SectorCell(millis: t, tone: tone)
    }
}
