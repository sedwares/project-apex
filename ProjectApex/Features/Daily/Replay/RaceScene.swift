//
//  RaceScene.swift
//  ProjectApex
//
//  The SpriteKit replay: a stylized car-chevron tracing an abstract
//  looped ribbon while the telemetry timeline drives its speed feel
//  and the HUD gauges. NO physics here — every value is read from the
//  Core-computed TelemetrySample stream. Product scope (§15): one car,
//  no opponents, one top-down camera, a visualization — not a driving
//  game.
//
//  Geometry lives in CircuitLoop, shared with the home-screen outline
//  so both surfaces trace the identical curve.
//

import SpriteKit
import ProjectApexCore

final class RaceScene: SKScene {

    struct Config {
        let samples: [TelemetrySample]
        let sectionsPerLap: Int
        let totalLaps: Int
        let secondsPerLap: Double
    }

    // Callbacks to SwiftUI for HUD + lifecycle.
    var onSample: ((TelemetrySample) -> Void)?
    var onLapComplete: ((Int) -> Void)?
    var onFinished: (() -> Void)?

    private var config: Config!
    private let car = SKShapeNode()
    private let trackLine = SKShapeNode()
    private var started = false

    /// Built once at didMove, when `size` is final. SpriteKit's origin
    /// is bottom-left, hence .up.
    private var loop = CircuitLoop(size: .zero, axis: .up)

    func configure(_ config: Config) { self.config = config }

    override func didMove(to view: SKView) {
            // Theme.Color.ink. SpriteKit has no access to the SwiftUI
            // palette, so these five constants are the one place the
            // Livery colours are duplicated — keep them in step with
            // Theme.swift by hand.
            backgroundColor = SKColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
            scaleMode = .resizeFill
            guard !started, config != nil else { return }
            started = true
            loop = CircuitLoop(size: size, axis: .up)
            buildTrack()
            buildCar()
            runReplay()
        }

    // MARK: - Track

    private func buildTrack() {
        trackLine.path = loop.path()
        trackLine.strokeColor = SKColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 0.16)
        trackLine.lineWidth = 10
        trackLine.lineCap = .round
        trackLine.lineJoin = .round
        addChild(trackLine)

        // Start/finish.
        let sf = SKShapeNode(rectOf: CGSize(width: 4, height: 22))
        sf.fillColor = SKColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1)   // cream
        sf.strokeColor = .clear
        sf.zPosition = 5
        sf.position = loop.point(at: 0)
        addChild(sf)

        // Sector gates. Three sectors means two interior boundaries —
        // at 1/3 and 2/3 — with start/finish closing the third.
        // Cream and amber rather than blue and purple: sector markers
        // are reference lines, not a third and fourth accent colour.
        let sectorColors: [SKColor] = [
            SKColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1),
            SKColor(red: 1.000, green: 0.820, blue: 0.000, alpha: 1)
        ]
        for (index, t) in [1.0 / 3.0, 2.0 / 3.0].enumerated() {
            let gate = SKShapeNode(rectOf: CGSize(width: 3, height: 16))
            gate.fillColor = sectorColors[index].withAlphaComponent(0.8)
            gate.strokeColor = .clear
            gate.zPosition = 5
            gate.position = loop.point(at: t)
            addChild(gate)
        }
    }

    private func buildCar() {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 11))
        p.addLine(to: CGPoint(x: -7, y: -8))
        p.addLine(to: CGPoint(x: 7, y: -8))
        p.closeSubpath()
        car.path = p
        car.fillColor = SKColor(red: 0.910, green: 0.067, blue: 0.176, alpha: 1)  // signal
        car.strokeColor = SKColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1) // cream
        car.lineWidth = 1.5
        car.zPosition = 10
        car.position = loop.point(at: 0)
        addChild(car)
    }

    // MARK: - Replay drive

    private func runReplay() {
        let totalDuration = config.secondsPerLap * Double(config.totalLaps)
        let sampleCount = max(config.samples.count, 1)
        var elapsed = 0.0
        let tick = 1.0 / 60.0

        let drive = SKAction.customAction(withDuration: totalDuration) { [weak self] _, _ in
            guard let self else { return }
            elapsed += tick
            let runProgress = min(1.0, elapsed / totalDuration)

            // Position along the loop, lapping totalLaps times.
            let loopT = (runProgress * Double(self.config.totalLaps)).truncatingRemainder(dividingBy: 1.0)
            self.car.position = self.loop.point(at: loopT)
            // -pi/2 because the chevron path is drawn nose-up, while
            // heading() measures from the +x axis.
            self.car.zRotation = self.loop.heading(at: loopT) - .pi / 2

            let sIdx = min(sampleCount - 1, Int(runProgress * Double(sampleCount)))
            self.onSample?(self.config.samples[sIdx])
        }

        var laps: [SKAction] = []
        for lap in 1...config.totalLaps {
            laps.append(.wait(forDuration: config.secondsPerLap))
            let n = lap
            laps.append(.run { [weak self] in self?.onLapComplete?(n) })
        }

        run(.group([drive, .sequence(laps)])) { [weak self] in
            self?.onFinished?()
        }
    }
}
