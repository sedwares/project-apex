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
//  ── v1.2: A RACE ───────────────────────────────────────────────────
//  Players said the replay "didn't feel like a race". Now: five start
//  lights, then five rival builds on track with you; a big position
//  that flashes on every overtake; one radio line per lap naming your
//  parts; and a classification at the flag. The pace dropped from 3.1s
//  to 4.5s a lap so all of it can be followed. Hierarchy on purpose:
//  your car (bright) → your position (big) → the radio (one line).
//  Everything else is secondary.
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
    /// The Experiment passes the OFFICIAL result here: it joins the race
    /// as a faded ghost of your own car, so a test setup is watched
    /// against the one you actually locked.
    var ghost: SimulationResult? = nil
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

    // Race
    @State private var timeline: RaceTimeline?
    /// Wall seconds each of the PLAYER's laps takes on screen. Not equal:
    /// a quicker lap really is quicker to watch.
    @State private var lapWall: [Double] = []
    @State private var position = 0
    @State private var fieldSize = 0
    @State private var positionTone: Color = Theme.Color.cream
    @State private var lightsOn = 0
    @State private var lightsOut = false
    @State private var ghostIndex: Int?
    /// YOU have taken the flag. The race itself runs on until the last
    /// rival crosses, so `finished` comes later — and the lap board used
    /// to wait for it, leaving Lap 3 blank with your car parked on the line.
    @State private var playerFinished = false

    private let secondsPerLap = 4.5
    private let sceneHeight: CGFloat = CircuitLoop.replayBandHeight

    private var totalLaps: Int { max(result.lapResults.count, 1) }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60).clipped()
                }
                if !lightsOut {
                    startLights
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: sceneHeight)
            .animation(.easeOut(duration: 0.15), value: lightsOut)

            timingTower
                .padding(.top, 14)

            gauges
                .padding(.top, 16)

            Group {
                if finished, timeline != nil {
                    classificationBoard
                } else {
                    lapBoard
                }
            }
            .padding(.top, 18)

            ZStack {
                if let radio {
                    Text("“\(radio)”")
                        .font(Theme.Font.body(13, weight: .regular).italic())
                        .foregroundStyle(Theme.Color.muted)
                        .multilineTextAlignment(.center)
                        .id(radio)
                        // The old line leaves at once; only the new one
                        // fades in. A symmetric crossfade drew both lines
                        // on top of each other for a quarter second —
                        // unreadable, and it is what a screenshot catches.
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
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
        .task { await runStartLights() }
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
            // Position first, big; lap underneath, small. The one number
            // that changes on an overtake is the one to watch.
            VStack(alignment: .trailing, spacing: 1) {
                Text(position > 0 ? "P\(position)" : "GRID")
                    .apexData(26, weight: .bold, color: positionTone)
                    .contentTransition(.identity)
                    .animation(.easeOut(duration: 0.35), value: positionTone)
                Text("LAP \(lap)/\(totalLaps)" + (fieldSize > 0 ? " · \(fieldSize) CARS" : ""))
                    .font(Theme.Font.label(9))
                    .tracking(1.3)
                    .foregroundStyle(Theme.Color.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(position > 0
                                ? "Position \(position) of \(fieldSize), lap \(lap) of \(totalLaps)"
                                : "On the grid")
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
        // At the flag the clock becomes your AVERAGE lap — the number
        // the classification below ranks by. It used to freeze on Lap 3,
        // which on a car that fades (heat, wear, risky reliability) read
        // several seconds slower than the average the Quick Race screen
        // and the board's gaps were built from.
        if finished { return result.averageLapTimeMillis }
        if playerFinished { return target }
        let elapsed = date.timeIntervalSince(lapStartedAt)
        let thisLap = lapWall.indices.contains(lap - 1) ? lapWall[lap - 1] : secondsPerLap
        let fraction = lightsOut ? min(max(elapsed / max(thisLap, 0.01), 0), 1) : 0
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
                if finished, let last = result.lapResults.last {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Avg lap").apexLabel(Theme.Color.cream)
                        Text("Last lap " + FixedPoint.formatLapTime(millis: last.timeMillis))
                            .apexData(11, weight: .medium, color: Theme.Color.muted)
                            .monospacedDigit()
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("SPEED").apexLabel(Theme.Color.faint)
                        speedBar
                    }
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
                    // Post the new split, never morph into it: the box
                    // animates on `cell.millis`, and an interpolated Text
                    // drew last lap's time and this lap's on top of each
                    // other — the same bug the lap board fixed with .identity.
                    .contentTransition(.identity)
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

    private func isComplete(_ n: Int) -> Bool { finished || playerFinished || n < lap }

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
        let isCurrent = n == lap && !finished && !playerFinished
        let isFastest = done && n == fastestCompletedLap && totalLaps > 1
        let millis = result.lapResults.indices.contains(n - 1)
            ? result.lapResults[n - 1].timeMillis : 0
        let stripe: Color = isFastest ? Theme.Color.session
            : (isCurrent ? Theme.Color.signal : Theme.Color.rule)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(stripe)
                .frame(width: 3)
                .animation(.easeOut(duration: 0.3), value: stripe)
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
                        .transition(.opacity)
                }
                // .identity, not the default interpolation: SwiftUI
                // otherwise MORPHS the placeholder into the time, and a
                // dash crossfading over digits renders as a line struck
                // through the lap time. A timing board should post a
                // time, not dissolve into one.
                if done {
                    Text(FixedPoint.formatLapTime(millis: millis))
                        .apexData(14, weight: .bold,
                                  color: isFastest ? Theme.Color.session : Theme.Color.cream)
                        .monospacedDigit()
                        .contentTransition(.identity)
                } else {
                    Text("—")
                        .apexData(14, weight: .bold, color: Theme.Color.faint)
                        .contentTransition(.identity)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.Color.panel)
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
            // On the grid there is no reading yet. Zero grip and zero
            // tire scored as "trouble" and painted the car red before it
            // had moved.
            if !lightsOut { return Theme.Color.faint }
            if severity > 0.80 { return Theme.Color.signal }
            if severity > 0.65 { return Theme.Color.notice }
            return Theme.Color.cream
        }()

        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(label).apexLabel(Theme.Color.muted)
                Spacer(minLength: 2)
                // Snap, don't interpolate. At 12 Hz a morphing
                // percentage renders both readings at once and the
                // digits overlap into nonsense.
                Text(lightsOut ? "\(Int(value * 100))%" : "—")
                    .apexData(11, weight: .bold, color: tone)
                    .monospacedDigit()
                    .contentTransition(.identity)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.cream.opacity(0.10))
                    Rectangle()
                        .fill(tone)
                        .frame(width: max(2, proxy.size.width * value))
                        .animation(.easeOut(duration: 0.18), value: value)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Start lights

    /// Five reds, one by one, then out. Two seconds everyone who has
    /// watched a race recognises before anything moves.
    private var startLights: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { i in
                VStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(i < lightsOn ? Theme.Color.signal : Theme.Color.cream.opacity(0.10))
                            .frame(width: 18, height: 18)
                            .shadow(color: i < lightsOn ? Theme.Color.signal.opacity(0.8) : .clear,
                                    radius: 8)
                    }
                }
                .padding(6)
                .background(Theme.Color.ink.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .animation(.easeOut(duration: 0.08), value: lightsOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lightsOn == 0 ? "On the grid" : "\(lightsOn) of 5 start lights")
    }

    private func runStartLights() async {
        try? await Task.sleep(for: .milliseconds(500))
        for i in 1...5 {
            guard !Task.isCancelled else { return }
            lightsOn = i
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(for: .milliseconds(550))
        }
        // The hold before lights out — fixed, so every race is the same
        // and the game stays deterministic end to end.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        lightsOut = true
        lapStartedAt = Date()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        scene?.start()
    }

    // MARK: - Classification

    /// At the flag the lap board gives way to the result of the RACE:
    /// six rows, by real average lap — the same number the leaderboard
    /// ranks. Rival setups are never shown, only their philosophy.
    private var classificationBoard: some View {
        let field = timeline!
        let rows = field.classification
        let leader = field.entrants[rows[0]].averageLapMillis

        return VStack(spacing: 0) {
            HStack {
                Text("Classification").apexLabel(Theme.Color.faint)
                Spacer()
                Text("Avg lap").apexLabel(Theme.Color.faint)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)

            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.element) { place, index in
                    let entrant = field.entrants[index]
                    let gap = entrant.averageLapMillis - leader
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(entrant.isPlayer ? Theme.Color.signal : Theme.Color.rule)
                            .frame(width: 3)
                        HStack(spacing: 10) {
                            Text("P\(place + 1)")
                                .apexData(13, weight: .bold,
                                          color: entrant.isPlayer ? Theme.Color.cream : Theme.Color.muted)
                                .frame(width: 30, alignment: .leading)
                            // Same colour as the car on track.
                            Circle()
                                .fill(entrant.isPlayer
                                      ? Theme.Color.signal
                                      : (index == ghostIndex
                                         ? Theme.Color.cream.opacity(0.45)
                                         : Color(uiColor: RaceScene.colour(forEntrant: index, player: 0))))
                                .frame(width: 8, height: 8)
                            Text(entrant.isPlayer ? "YOU" : entrant.name)
                                .font(entrant.isPlayer ? Theme.Font.display(15) : Theme.Font.body(13))
                                .foregroundStyle(entrant.isPlayer ? Theme.Color.cream : Theme.Color.muted)
                            Spacer(minLength: 8)
                            Text(place == 0
                                 ? FixedPoint.formatLapTime(millis: entrant.averageLapMillis)
                                 : "+" + secondsText(gap))
                                .apexData(13, weight: .bold,
                                          color: entrant.isPlayer ? Theme.Color.cream : Theme.Color.muted)
                                .monospacedDigit()
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                    }
                    .background(entrant.isPlayer ? Theme.Color.signal.opacity(0.12) : Theme.Color.panel)
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .transition(.opacity)
    }

    // MARK: - Scene wiring

    private func buildScene() {
        lapStartedAt = Date()
        let sections = challenge.circuit.sections
        let samples = TelemetryTimeline.samples(for: result, sectionsPerLap: sections.count)
        let radioFeed = FeedbackEngine.radioMessages(for: result, weather: challenge.weather)
        var radioIndex = 0

        // The field: you plus five rival builds, all simulated on today's
        // circuit under today's rules.
        let you = RaceEntrant(id: "you", name: "You", isPlayer: true, result: result)
        var entrants = [you] + RivalField.rivals(for: challenge)
        if let ghost {
            entrants.append(RaceEntrant(id: "official", name: "Official car", isPlayer: false, result: ghost))
            ghostIndex = entrants.count - 1
        }
        let field = RaceTimeline(entrants: entrants)
        timeline = field
        fieldSize = field.entrants.count

        var config = RaceScene.Config(
            samples: samples,
            sections: sections,
            archetype: challenge.circuit.archetype,
            totalLaps: totalLaps,
            secondsPerLap: secondsPerLap,
            field: field,
            playerIndex: 0
        )
        config.waitsForStart = true
        config.ghostIndex = ghostIndex
        let perClock = RaceScene.wallPerClock(config)
        lapWall = field.lapDurations(of: 0).map { $0 * perClock }

        let scene = RaceScene(size: CGSize(width: 390, height: sceneHeight))
        scene.configure(config)

        scene.onPosition = { newPosition, size in
            let old = position
            position = newPosition
            fieldSize = size
            guard old > 0, newPosition != old else { return }
            // Gained a place: green and a crisp tick. Lost one: red, soft.
            let gained = newPosition < old
            positionTone = gained ? Theme.Color.gain : Theme.Color.signal
            UIImpactFeedbackGenerator(style: gained ? .rigid : .soft).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                positionTone = Theme.Color.cream
            }
        }

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
            } else {
                playerFinished = true
            }
        }

        scene.onFinished = {
            radio = nil
            finished = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // NO auto-advance. This used to dismiss itself 1.1s after the
            // flag, which meant Continue appeared and was gone before it
            // could be pressed — and, worse, the lap board is full at
            // exactly that moment. The board is the point of the
            // ceremony; snatching it away one beat after it completes
            // wastes the only screen that tells the whole run's story.
            // The player leaves when the player is ready.
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
