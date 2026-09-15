//
//  RaceScene.swift
//  ProjectApex
//
//  The SpriteKit replay: a car tracing the DAY'S OWN circuit while the
//  deterministic telemetry stream drives the HUD. No physics — every
//  value is read from Core. One car, no opponents, one top-down camera.
//  A visualisation, not a driving game (product scope §15).
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
import ProjectApexCore

final class RaceScene: SKScene {

    struct Config {
        let samples: [TelemetrySample]
        let sections: [TrackSectionType]
        let archetype: CircuitArchetype
        let totalLaps: Int
        let secondsPerLap: Double
    }

    // Callbacks to SwiftUI for HUD + lifecycle.
    var onSample: ((TelemetrySample, Double) -> Void)?
    var onSectorComplete: ((_ lap: Int, _ sector: Int) -> Void)?
    var onLapComplete: ((Int) -> Void)?
    var onFinished: (() -> Void)?

    private var config: Config!
    private let car = SKShapeNode()
    private let carGlow = SKShapeNode(circleOfRadius: 16)
    private let trail = SKShapeNode()
    private let trackLine = SKShapeNode()
    private let racingLine = SKShapeNode()
    private var started = false

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
        buildTrack()
        buildCar()
        runReplay()
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

        // Start/finish.
        let sf = SKShapeNode(rectOf: CGSize(width: 5, height: 24))
        sf.fillColor = Paint.cream
        sf.strokeColor = .clear
        sf.zPosition = 5
        sf.position = loop.point(at: 0)
        sf.zRotation = loop.heading(at: 0)
        addChild(sf)

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

        // A stubby arrow — reads as a car at this size where a thin
        // chevron read as a cursor.
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 13))
        p.addLine(to: CGPoint(x: -8, y: -6))
        p.addLine(to: CGPoint(x: 0, y: -2))
        p.addLine(to: CGPoint(x: 8, y: -6))
        p.closeSubpath()
        car.path = p
        car.fillColor = Paint.signal
        car.strokeColor = Paint.cream
        car.lineWidth = 1.5
        car.zPosition = 10
        car.position = loop.point(at: 0)
        addChild(car)
    }

    // MARK: - Replay drive

    private func runReplay() {
        let totalLaps = max(config.totalLaps, 1)
        let totalDuration = config.secondsPerLap * Double(totalLaps)
        let sampleCount = max(config.samples.count, 1)
        let gates = loop.sectorStartTimes

        var elapsed = 0.0
        var lastLapTime = 0.0
        var lap = 1
        var sectorsDone = 0
        let tick = 1.0 / 60.0

        let drive = SKAction.customAction(withDuration: totalDuration) { [weak self] _, _ in
            guard let self else { return }
            elapsed += tick
            let runProgress = min(1.0, elapsed / totalDuration)

            // Where we are within THIS lap, in time.
            let lapTime = (runProgress * Double(totalLaps)).truncatingRemainder(dividingBy: 1.0)

            // Lap rollover: time went backwards.
            if lapTime < lastLapTime {
                self.onLapComplete?(lap)
                lap = min(lap + 1, totalLaps)
                sectorsDone = 0
            }

            // Sector gates, in order, once each per lap.
            while sectorsDone < gates.count - 1 {
                let next = gates[sectorsDone + 1]
                if lapTime >= next && lastLapTime < next {
                    sectorsDone += 1
                    self.onSectorComplete?(lap, sectorsDone - 1)
                } else { break }
            }
            lastLapTime = lapTime

            // Position and facing along the circuit's own geometry.
            let arc = self.loop.arcPosition(atLapTime: lapTime)
            let pos = self.loop.point(at: arc)
            self.car.position = pos
            // -pi/2 because the car path is drawn nose-up while
            // heading() measures from the +x axis.
            self.car.zRotation = self.loop.heading(at: arc) - .pi / 2
            self.carGlow.position = pos

            // Trail length follows speed, so the straights visibly
            // stretch and the hairpin visibly bunches up.
            let speed = self.loop.speed(atLapTime: lapTime)
            self.carGlow.setScale(0.75 + speed * 0.65)
            self.carGlow.alpha = 0.45 + speed * 0.55
            self.pushTrail(pos, speed: speed)

            // Throttled HUD update.
            self.sampleAccumulator += tick
            if self.sampleAccumulator >= self.sampleInterval {
                self.sampleAccumulator = 0
                let idx = min(sampleCount - 1, Int(runProgress * Double(sampleCount)))
                self.onSample?(self.config.samples[idx], speed)
            }
        }

        run(drive) { [weak self] in
            guard let self else { return }
            self.onLapComplete?(totalLaps)
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
