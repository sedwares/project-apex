//
//  RaceScene.swift
//  ProjectApex
//
//  The SpriteKit replay: a car tracing the DAY'S OWN circuit while the
//  deterministic telemetry stream drives the HUD. No physics — every
//  value is read from Core. One top-down camera; a visualisation, not a
//  driving game (product scope §15).
//
//  ── v1.2: A FIELD ──────────────────────────────────────────────────
//  Five rival builds race alongside the player (RivalField), every car
//  placed by RaceTimeline from its own simulated sector times. Order is
//  exact; gaps are drawn magnified (see RaceField.swift). The race
//  holds on the grid until `start()` so the start lights can run.
//
//  ── PASS 8 ─────────────────────────────────────────────────────────
//  Three changes, all of them about making a lap feel like a lap.
//
//  The track is now the circuit. CircuitLoop builds its shape from the
//  eleven-or-so typed sections, so a technical street course and a
//  high-speed blast no longer trace the same oval.
//
//  The car's speed varies. Position comes from
//  `arcPosition(atLapTime:)`, which buys unequal track with equal time
//  — flat out down the straight, crawling through the hairpin. The
//  trail behind it lengthens with speed, so the eye reads pace before
//  it reads any number.
//
//  `onSample` is throttled. It used to fire 60 times a second into
//  three separate SwiftUI @State properties, which is ~180 view
//  invalidations per second, each re-evaluating the SpriteView itself.
//  The gauges cannot show more than about 12 Hz of change anyway.
//

import SpriteKit
import UIKit
import ProjectApexCore

final class RaceScene: SKScene {

    struct Config {
        let samples: [TelemetrySample]
        let sections: [TrackSectionType]
        let archetype: CircuitArchetype
        let totalLaps: Int
        let secondsPerLap: Double
        /// Everyone in the race, the player included. Drives every car.
        let field: RaceTimeline
        let playerIndex: Int
        /// Hold on the grid until `start()` — the start lights.
        var waitsForStart: Bool = false
        /// An entrant drawn as a ghost of the player's own car — the
        /// Experiment races the official setup this way.
        var ghostIndex: Int? = nil
    }

    /// Wall seconds per unit of the field's visual clock: the player's
    /// race fills exactly `secondsPerLap × laps`, and everyone else runs
    /// at the same rate, so faster cars really do arrive sooner.
    static func wallPerClock(_ c: Config) -> Double {
        let finish = c.field.finishClock(of: c.playerIndex)
        guard finish > 0 else { return 0 }
        return c.secondsPerLap * Double(max(c.totalLaps, 1)) / finish
    }

    // Callbacks to SwiftUI for HUD + lifecycle.
    var onSample: ((TelemetrySample, Double) -> Void)?
    var onSectorComplete: ((_ lap: Int, _ sector: Int) -> Void)?
    var onLapComplete: ((Int) -> Void)?
    /// Player's position (1-based) and field size, whenever it changes.
    var onPosition: ((Int, Int) -> Void)?
    var onFinished: (() -> Void)?

    private var config: Config!
    private let car = SKNode()
    private let carGlow = SKShapeNode(circleOfRadius: 16)
    private let trail = SKShapeNode()
    private let trackLine = SKShapeNode()
    private let racingLine = SKShapeNode()
    private var started = false
    private var built = false
    private var running = false
    private var startRequested = false

    /// One node per entrant; the player's slot holds `car`.
    private var cars: [SKNode] = []
    /// Lateral lane per entrant, in points across the track, so a close
    /// pack reads as cars side by side rather than one blob.
    private var lanes: [CGFloat] = []
    /// Finishing position per entrant (0 = winner), by when each takes
    /// the flag — used to park them in order after the line.
    private var finishRank: [Int] = []

    private var loop = CircuitLoop(size: .zero, sections: [])
    private var trailPoints: [CGPoint] = []

    // Throttle: the HUD is legible at ~12 Hz, not 60.
    private var sampleAccumulator = 0.0
    private let sampleInterval = 1.0 / 12.0

    // ── The Livery palette. SpriteKit has no access to the SwiftUI
    // colours, so this is the one place they are duplicated — keep in
    // step with Theme.swift by hand.
    private enum Paint {
        static let ink    = SKColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
        static let cream  = SKColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1)
        static let signal = SKColor(red: 0.910, green: 0.067, blue: 0.176, alpha: 1)
        static let notice = SKColor(red: 1.000, green: 0.820, blue: 0.000, alpha: 1)
        static let session = SKColor(red: 0.749, green: 0.000, blue: 1.000, alpha: 1)
    }

    /// One colour per rival, in field order. Chosen to stay clear of the
    /// colours that already MEAN something here — red is you, green is a
    /// gain, gold is a warning, purple is a fastest lap — and to read on
    /// near-black. The classification shows the same colour beside each
    /// name, so a car on track can be matched to its result.
    static let rivalColours: [SKColor] = [
        SKColor(red: 0.33, green: 0.58, blue: 0.98, alpha: 1),   // blue
        SKColor(red: 0.18, green: 0.78, blue: 0.74, alpha: 1),   // teal
        SKColor(red: 0.98, green: 0.62, blue: 0.24, alpha: 1),   // orange
        SKColor(red: 0.60, green: 0.84, blue: 0.30, alpha: 1),   // lime
        SKColor(red: 0.86, green: 0.48, blue: 0.82, alpha: 1)    // pink
    ]

    /// Colour for an entrant, given which entrant is the player.
    static func colour(forEntrant i: Int, player: Int) -> SKColor {
        let r = i < player ? i : i - 1
        return rivalColours[max(r, 0) % rivalColours.count]
    }

    func configure(_ config: Config) { self.config = config }

    override func didMove(to view: SKView) {
        backgroundColor = Paint.ink
        scaleMode = .resizeFill
        guard !started, config != nil else { return }
        started = true
        loop = CircuitLoop(size: size,
                           sections: config.sections,
                           archetype: config.archetype,
                           axis: .up)
        buildBackdrop()
        buildTrack()
        buildKerbs()
        buildCar()
        buildField()
        built = true
        place(atClock: 0)
        if !config.waitsForStart || startRequested { start() }
    }

    /// Lights out. Safe to call before the scene is on screen.
    func start() {
        guard built else { startRequested = true; return }
        guard !running else { return }
        running = true
        runReplay()
    }

    // MARK: - Backdrop

    /// What makes a screen feel like a race broadcast before anything
    /// moves is the SURFACE it is drawn on. A flat black rectangle reads
    /// as an empty view; a faint measured grid reads as a monitor on a
    /// pit wall. Two layers, both static, both built once:
    ///
    ///   · a telemetry grid at 30pt, barely above the background
    ///   · a radial vignette, so the middle of the circuit is the
    ///     brightest thing on screen and the eye goes there first
    ///
    /// Everything here is deliberately near-invisible in isolation. It
    /// is meant to be felt, not read — turn either up and the track
    /// stops being the subject.
    private func buildBackdrop() {
        let grid = CGMutablePath()
        let step: CGFloat = 30
        var x: CGFloat = 0
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        let gridNode = SKShapeNode(path: grid)
        gridNode.strokeColor = Paint.cream.withAlphaComponent(0.035)
        gridNode.lineWidth = 1
        gridNode.zPosition = -10
        addChild(gridNode)

        if let texture = vignetteTexture(size: size) {
            let v = SKSpriteNode(texture: texture, size: size)
            v.position = CGPoint(x: size.width / 2, y: size.height / 2)
            v.zPosition = -9
            v.alpha = 0.9
            addChild(v)
        }
    }

    /// SpriteKit has no radial gradient primitive, so draw one once into
    /// a texture rather than faking it with stacked shapes.
    private func vignetteTexture(size: CGSize) -> SKTexture? {
        guard size.width > 1, size.height > 1 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor.clear.cgColor,
                UIColor.black.withAlphaComponent(0.62).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.30, 1.0]
            ) else { return }
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: mid, startRadius: 0,
                endCenter: mid, endRadius: max(size.width, size.height) * 0.60,
                options: [.drawsAfterEndLocation]
            )
        }
        return SKTexture(image: image)
    }

    // MARK: - Kerbs

    /// Red-and-white kerbs at the APEX of the tightest corners.
    ///
    /// The first version kerbed every corner and braking zone over its
    /// full length, which on a technical circuit meant kerbing most of
    /// the lap. Marking almost everything marks nothing: the stripes
    /// stopped reading as track furniture and started reading as a
    /// dashed lane divider.
    ///
    /// Two corrections. Only the genuinely SLOW corners qualify — a fast
    /// corner is taken flat and does not want a kerb drawing attention
    /// to it — and each gets only the middle of its arc, because a kerb
    /// belongs at the apex rather than running the whole way round. The
    /// result is punctuation, and the eye can now find the hairpin.
    ///
    /// Two nodes total, not one per stripe: each colour accumulates its
    /// rectangles into a single path via addRect(_:transform:), so even
    /// a busy circuit costs two draws.
    private func buildKerbs() {
        let red = CGMutablePath()
        let white = CGMutablePath()
        let stripe = CGRect(x: -4.0, y: -2.0, width: 8.0, height: 4.0)
        var drew = false

        for kerb in loop.kerbStripes(offset: 7.5) {
            let transform = CGAffineTransform(translationX: kerb.point.x, y: kerb.point.y)
                .rotated(by: kerb.heading)
            (kerb.isRed ? red : white).addRect(stripe, transform: transform)
            drew = true
        }
        guard drew else { return }

        for (path, colour) in [(red, Paint.signal), (white, Paint.cream)] {
            let node = SKShapeNode(path: path)
            node.fillColor = colour.withAlphaComponent(0.85)
            node.strokeColor = .clear
            node.zPosition = 3
            addChild(node)
        }
    }

    // MARK: - Track

    private func buildTrack() {
        // The tarmac: a wide, dim ribbon.
        trackLine.path = loop.path()
        trackLine.strokeColor = Paint.cream.withAlphaComponent(0.13)
        trackLine.lineWidth = 16
        trackLine.lineCap = .round
        trackLine.lineJoin = .round
        trackLine.zPosition = 1
        addChild(trackLine)

        // A hairline racing line inside it, so the ribbon reads as a
        // road rather than a drawn shape.
        racingLine.path = loop.path()
        racingLine.strokeColor = Paint.cream.withAlphaComponent(0.06)
        racingLine.lineWidth = 1
        racingLine.zPosition = 2
        addChild(racingLine)

        // Start/finish, checkered — two rows of squares across the
        // track rather than a plain bar. Costs nothing and is the one
        // marking everybody recognises without being told.
        let light = CGMutablePath()
        let dark = CGMutablePath()
        let square: CGFloat = 4.0
        let origin = loop.point(at: 0)
        let facing = loop.heading(at: 0)
        let place = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: facing)
        for row in 0..<2 {
            for col in 0..<4 {
                let along = (CGFloat(row) - 0.5) * square
                let across = (CGFloat(col) - 1.5) * square
                let cell = CGRect(x: along - square / 2, y: across - square / 2,
                                  width: square, height: square)
                ((row + col) % 2 == 0 ? light : dark).addRect(cell, transform: place)
            }
        }
        for (path, colour) in [(light, Paint.cream), (dark, Paint.ink)] {
            let node = SKShapeNode(path: path)
            node.fillColor = colour
            node.strokeColor = .clear
            node.zPosition = 6
            addChild(node)
        }

        // Sector gates. Index 0 IS start/finish, so only draw 2 and 3.
        let gates = loop.sectorGateArcs
        for (i, t) in gates.enumerated() where i > 0 {
            let gate = SKShapeNode(rectOf: CGSize(width: 3, height: 18))
            gate.fillColor = (i == 1 ? Paint.cream : Paint.notice).withAlphaComponent(0.75)
            gate.strokeColor = .clear
            gate.zPosition = 5
            gate.position = loop.point(at: t)
            gate.zRotation = loop.heading(at: t)
            addChild(gate)
        }
    }

    /// A top-down Formula car rather than a chevron.
    ///
    /// ── ON THE COLOUR ──────────────────────────────────────────────
    /// The body is CREAM, not signal red. A red single-seater reads as
    /// Ferrari to anyone who watches the sport, and borrowing another
    /// team's identity is not the association this game wants. Cream is
    /// unclaimed — no constructor owns white — and it has more contrast
    /// against the near-black track than red did.
    ///
    /// The livery is not lost: a signal-red stripe runs the centreline,
    /// the bloom under the car is red, and so is the trail. Red stays
    /// the colour of MOTION here, which is what it means everywhere
    /// else in the app.
    ///
    /// ── ON THE SHAPE ───────────────────────────────────────────────
    /// What makes a car read as Formula from above is not detail, which
    /// is invisible at this size — it is the wide front wing, four
    /// EXPOSED wheels outboard of a narrow body, and a wide rear wing.
    /// Drawn nose-up (+y); RaceScene applies the -pi/2 itself.
    private func buildCar() {
        // Soft bloom under the car, brightened on the fast stuff.
        carGlow.fillColor = Paint.signal.withAlphaComponent(0.20)
        carGlow.strokeColor = .clear
        carGlow.zPosition = 8
        carGlow.position = loop.point(at: 0)
        addChild(carGlow)

        trail.strokeColor = Paint.signal.withAlphaComponent(0.55)
        trail.lineWidth = 4
        trail.lineCap = .round
        trail.zPosition = 9
        addChild(trail)

        // Tyres first, so the bodywork sits over them.
        let tyre = SKColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        let wheels: [(CGPoint, CGSize)] = [
            (CGPoint(x: -7.6, y:  8), CGSize(width: 4.6, height: 8.2)),   // front left
            (CGPoint(x:  7.6, y:  8), CGSize(width: 4.6, height: 8.2)),   // front right
            (CGPoint(x: -8.1, y: -8), CGSize(width: 5.2, height: 9.4)),   // rear left
            (CGPoint(x:  8.1, y: -8), CGSize(width: 5.2, height: 9.4))    // rear right
        ]
        for (centre, size) in wheels {
            let w = SKShapeNode(rectOf: size, cornerRadius: 1.6)
            w.position = centre
            w.fillColor = tyre
            w.strokeColor = Paint.cream.withAlphaComponent(0.45)
            w.lineWidth = 0.8
            w.zPosition = 1
            car.addChild(w)
        }

        // Front wing, nose, sidepods, rear wing — one outline.
        let body = CGMutablePath()
        let hull: [CGPoint] = [
            CGPoint(x: -9.0, y:  16.0), CGPoint(x:  9.0, y:  16.0),   // front wing
            CGPoint(x:  9.0, y:  13.0), CGPoint(x:  3.0, y:  12.0),   // to the nose
            CGPoint(x:  3.5, y:   3.0), CGPoint(x:  5.6, y:   2.0),   // sidepod out
            CGPoint(x:  5.6, y:  -6.0), CGPoint(x:  3.5, y:  -7.0),   // sidepod back
            CGPoint(x:  3.5, y: -13.0), CGPoint(x:  8.0, y: -13.0),   // rear wing
            CGPoint(x:  8.0, y: -16.0), CGPoint(x: -8.0, y: -16.0),
            CGPoint(x: -8.0, y: -13.0), CGPoint(x: -3.5, y: -13.0),
            CGPoint(x: -3.5, y:  -7.0), CGPoint(x: -5.6, y:  -6.0),
            CGPoint(x: -5.6, y:   2.0), CGPoint(x: -3.5, y:   3.0),
            CGPoint(x: -3.0, y:  12.0), CGPoint(x: -9.0, y:  13.0)
        ]
        body.addLines(between: hull)
        body.closeSubpath()

        let shell = SKShapeNode(path: body)
        shell.fillColor = Paint.cream
        shell.strokeColor = Paint.ink.withAlphaComponent(0.55)
        shell.lineWidth = 0.9
        shell.zPosition = 2
        car.addChild(shell)

        // The livery: one red line down the centreline.
        let stripe = SKShapeNode(rectOf: CGSize(width: 2.4, height: 24))
        stripe.position = CGPoint(x: 0, y: 0.5)
        stripe.fillColor = Paint.signal
        stripe.strokeColor = .clear
        stripe.zPosition = 3
        car.addChild(stripe)

        // Drawn at a comfortable size to reason about, then sized to the
        // 16pt track ribbon so the car sits ON the road rather than
        // swallowing it.
        car.setScale(0.72)
        car.zPosition = 10
        car.position = loop.point(at: 0)
        addChild(car)
    }

    // MARK: - The field

    /// Rivals: the same silhouette as the player's car, smaller and in
    /// a dim grey, with no stripe, glow or trail. The eye should always
    /// find YOUR car first; the others are there to be passed.
    private func buildField() {
        let field = config.field
        let byFinish = field.entrants.indices.sorted {
            let a = field.finishClock(of: $0), b = field.finishClock(of: $1)
            return a != b ? a < b : $0 < $1
        }
        finishRank = Array(repeating: 0, count: field.entrants.count)
        for (rank, i) in byFinish.enumerated() { finishRank[i] = rank }
        let rivalLanes: [CGFloat] = [-5.0, 5.0, -2.6, 2.6, -6.4, 6.4]
        var r = 0
        for i in field.entrants.indices {
            if i == config.playerIndex {
                cars.append(car)
                lanes.append(0)
            } else {
                let node = i == config.ghostIndex
                    ? Self.rivalCar(Paint.cream, alpha: 0.38)
                    : Self.rivalCar(Self.colour(forEntrant: i, player: config.playerIndex))
                node.zPosition = 7
                addChild(node)
                cars.append(node)
                lanes.append(rivalLanes[r % rivalLanes.count])
                r += 1
            }
        }
    }

    private static func rivalCar(_ colour: SKColor, alpha: CGFloat = 0.85) -> SKNode {
        let node = SKNode()
        // Solid team colour, but a touch dimmer than the player's cream
        // car so yours still leads the eye.
        let grey = colour.withAlphaComponent(alpha)
        for (x, y) in [(-7.6, 8.0), (7.6, 8.0), (-8.1, -8.0), (8.1, -8.0)] {
            let w = SKShapeNode(rectOf: CGSize(width: 4.8, height: 8.6), cornerRadius: 1.6)
            w.position = CGPoint(x: x, y: y)
            w.fillColor = Paint.ink
            w.strokeColor = grey
            w.lineWidth = 0.8
            node.addChild(w)
        }
        let body = CGMutablePath()
        body.addLines(between: [
            CGPoint(x: -9, y: 16), CGPoint(x: 9, y: 16), CGPoint(x: 9, y: 13),
            CGPoint(x: 3, y: 12), CGPoint(x: 5.6, y: 2), CGPoint(x: 5.6, y: -6),
            CGPoint(x: 3.5, y: -13), CGPoint(x: 8, y: -13), CGPoint(x: 8, y: -16),
            CGPoint(x: -8, y: -16), CGPoint(x: -8, y: -13), CGPoint(x: -3.5, y: -13),
            CGPoint(x: -5.6, y: -6), CGPoint(x: -5.6, y: 2), CGPoint(x: -3, y: 12),
            CGPoint(x: -9, y: 13)
        ])
        body.closeSubpath()
        let shell = SKShapeNode(path: body)
        shell.fillColor = grey
        shell.strokeColor = .clear
        node.addChild(shell)
        node.setScale(0.62)
        return node
    }

    /// Where an entrant is, in lap-time terms, after `g` sectors.
    /// Sector gates come from the circuit, so a car crosses each drawn
    /// gate exactly when its sector time says it does.
    private func lapTime(forSectors g: Double) -> (lap: Int, fraction: Double) {
        let laps = max(config.totalLaps, 1)
        let total = Double(laps * 3)
        let gg = min(max(g, 0), total)
        if gg >= total { return (laps, 1.0) }
        let lapIndex = Int(gg / 3)
        let within = gg - Double(lapIndex * 3)
        let s = min(Int(within), 2)
        let f = within - Double(s)
        let gates = loop.sectorStartTimes
        let a = s < gates.count ? gates[s] : 1.0
        let b = s + 1 < gates.count ? gates[s + 1] : 1.0
        return (lapIndex + 1, a + f * (b - a))
    }

    /// Put every car where the field says it is at `clock`. Returns the
    /// player's sector progress and lap-time fraction for the HUD.
    @discardableResult
    private func place(atClock clock: Double) -> (sectors: Double, fraction: Double) {
        var player = (sectors: 0.0, fraction: 0.0)
        for i in cars.indices {
            let g = config.field.sectorProgress(of: i, at: clock)
            let lt = lapTime(forSectors: g)
            var arc = loop.arcPosition(atLapTime: lt.fraction)

            // After the flag a car rolls on down the straight and stops
            // in finishing order — the winner furthest along — instead
            // of every car parking on the same spot on the line.
            let finish = config.field.finishClock(of: i)
            if clock >= finish {
                let n = cars.count
                let target = 0.028 * Double(n - finishRank[i])
                let lastLap = config.field.lapDurations(of: i).last ?? 1
                let coasted = (clock - finish) / max(lastLap, 1) * 0.6
                arc = (loop.arcPosition(atLapTime: 0) + min(target, coasted))
                    .truncatingRemainder(dividingBy: 1)
            }
            let heading = loop.heading(at: arc)
            var pos = loop.point(at: arc)
            let lane = lanes[i]
            pos.x += -sin(heading) * lane
            pos.y += cos(heading) * lane
            cars[i].position = pos
            // -pi/2: the car is drawn nose-up; heading() is from +x.
            cars[i].zRotation = heading - .pi / 2
            if i == config.playerIndex {
                carGlow.position = pos
                player = (g, lt.fraction)
            }
        }
        return player
    }

    // MARK: - Replay drive

    private func runReplay() {
        let totalLaps = max(config.totalLaps, 1)
        let totalSectors = totalLaps * 3
        let field = config.field
        let me = config.playerIndex
        let perClock = Self.wallPerClock(config)
        guard perClock > 0 else { onFinished?(); return }
        // Run until the LAST car finishes, so the player sees who they
        // beat cross the line behind them.
        let totalWall = field.lastFinishClock * perClock
        let sampleCount = max(config.samples.count, 1)

        var elapsed = 0.0
        var sectorsReported = 0
        var lastPosition = 0

        // Real elapsed time from SpriteKit, never a frame count: a
        // dropped frame must not leave a car short of the line.
        let drive = SKAction.customAction(withDuration: totalWall) { [weak self] _, elapsedTime in
            guard let self else { return }
            let now = min(Double(elapsedTime), totalWall)
            let delta = max(0, now - elapsed)
            elapsed = now
            let clock = now / perClock

            let player = self.place(atClock: clock)

            // Player's sector lines and laps, in order, once each.
            let whole = min(Int(player.sectors), totalSectors)
            while sectorsReported < whole {
                sectorsReported += 1
                let sector = (sectorsReported - 1) % 3
                let lap = (sectorsReported - 1) / 3 + 1
                if sector < 2 {
                    self.onSectorComplete?(lap, sector)
                } else {
                    self.onLapComplete?(lap)
                }
            }

            // Running order.
            let order = field.order(at: clock)
            let position = (order.firstIndex(of: me) ?? 0) + 1
            if position != lastPosition {
                lastPosition = position
                self.onPosition?(position, field.entrants.count)
            }

            // Glow and trail follow the player's speed; once the player
            // has taken the flag they coast to a stop on the line.
            let finished = player.sectors >= Double(totalSectors)
            let speed = finished ? 0.15 : self.loop.speed(atLapTime: player.fraction)
            self.carGlow.setScale(0.75 + speed * 0.65)
            self.carGlow.alpha = 0.45 + speed * 0.55
            self.pushTrail(self.car.position, speed: speed)

            self.sampleAccumulator += delta
            if self.sampleAccumulator >= self.sampleInterval {
                self.sampleAccumulator = 0
                let progress = player.sectors / Double(totalSectors)
                let idx = min(sampleCount - 1, Int(progress * Double(sampleCount)))
                self.onSample?(self.config.samples[idx], speed)
            }
        }

        // A short cool-down after the last car takes the flag, so the
        // field rolls on and settles in finishing order on the straight.
        let lastFlag = field.lastFinishClock
        let coolDown = SKAction.customAction(withDuration: 1.4) { [weak self] _, t in
            self?.place(atClock: lastFlag + Double(t) / perClock)
        }

        run(.sequence([drive, coolDown])) { [weak self] in
            guard let self else { return }
            self.place(atClock: lastFlag + 1.4 / perClock)
            while sectorsReported < totalSectors {
                sectorsReported += 1
                let sector = (sectorsReported - 1) % 3
                let lap = (sectorsReported - 1) / 3 + 1
                if sector < 2 { self.onSectorComplete?(lap, sector) } else { self.onLapComplete?(lap) }
            }
            let order = field.order(at: field.lastFinishClock + 1)
            self.onPosition?((order.firstIndex(of: me) ?? 0) + 1, field.entrants.count)
            self.onFinished?()
        }
    }

    /// Ring buffer of recent positions, redrawn as a fading ribbon.
    /// Capped tight — this runs every frame.
    private func pushTrail(_ point: CGPoint, speed: Double) {
        let maxPoints = Int(6 + speed * 20)
        trailPoints.append(point)
        if trailPoints.count > maxPoints {
            trailPoints.removeFirst(trailPoints.count - maxPoints)
        }
        guard trailPoints.count > 1 else { return }
        let path = CGMutablePath()
        path.move(to: trailPoints[0])
        for p in trailPoints.dropFirst() { path.addLine(to: p) }
        trail.path = path
        trail.alpha = 0.30 + speed * 0.45
    }
}
