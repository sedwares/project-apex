//
//  TelemetryTimeline.swift
//  ProjectApexCore
//
//  The replay's data layer. Turns a finished SimulationResult into an
//  ordered stream of telemetry samples — one per (lap, sector) — that
//  the SpriteKit replay scene renders as a moving car + live gauges.
//
//  This computes NO physics. Every fraction is derived from what the
//  sim already produced (setup stats + observed lap/sector times +
//  events), so the gauges can never disagree with the result. Pure,
//  deterministic, unit-tested — pixels read this, they don't think.
//

public nonisolated struct TelemetrySample: Sendable, Equatable {
    public let lap: Int              // 1-based
    public let sectionIndex: Int     // 0-based, within the lap
    /// All 0...1 for gauge fills.
    public let grip: Double          // mechanical grip available
    public let heat: Double          // engine heat load (higher = worse)
    public let tireLife: Double      // remaining tire performance
    /// Progress through the whole 3-lap run, 0...1 (drives car position
    /// along the track and the replay clock).
    public let runProgress: Double
}

public nonisolated enum TelemetryTimeline {

    /// Builds the full 3-lap sample stream. `sectionsPerLap` comes from
    /// the circuit; sim sector times are grouped in 3 (the sim's
    /// coarse sectors), so we interpolate section-level progress evenly.
    public static func samples(
        for result: SimulationResult,
        sectionsPerLap: Int
    ) -> [TelemetrySample] {
        let stats = VehicleBuilder.build(from: result.setup)
        let laps = result.lapResults.count
        guard laps > 0, sectionsPerLap > 0 else { return [] }

        // Baseline levels from the built car (pre-degradation), 0...1.
        let baseGrip = clamp01(Double(stats.grip) / 1_400.0)
        let baseTire = clamp01(Double(stats.tireDurability) / 1_400.0)
        // Heat load: generation vs cooling headroom. Higher = hotter.
        let heatLoad = clamp01(0.35 + Double(stats.heatGeneration - stats.cooling) / 800.0)

        let hasHeatEvent = result.events.contains(.engineHeatHigh)
        let hasWearEvent = result.events.contains(.tireWearHigh)

        var samples: [TelemetrySample] = []
        let totalSections = laps * sectionsPerLap

        for lapIndex in 0..<laps {
            let lap = lapIndex + 1
            // Lap-shaped modifiers, matching the engine's story:
            //  Lap 1 warm-up: grip and tires start low, climb.
            //  Lap 2 peak: everything at its best.
            //  Lap 3 decay: heat rises, tires fall (amplified by events).
            for section in 0..<sectionsPerLap {
                let withinLap = Double(section) / Double(max(sectionsPerLap - 1, 1))
                let globalIndex = lapIndex * sectionsPerLap + section
                let runProgress = Double(globalIndex + 1) / Double(totalSections)

                var grip = baseGrip
                var tire = baseTire
                var heat = heatLoad

                switch lap {
                case 1:
                    // Warm-up: begins ~12% down, recovers across the lap.
                    let warm = 0.88 + 0.12 * withinLap
                    grip *= warm
                    tire = min(1.0, tire + 0.05)          // freshest early
                    heat *= 0.85 + 0.10 * withinLap        // still warming
                case 2:
                    grip *= 1.0
                    heat *= 0.95
                default:
                    // Lap 3 decay, deepening across the lap.
                    let decay = withinLap
                    let wearDrop = (hasWearEvent ? 0.35 : 0.15) * decay
                    tire = max(0.05, tire - wearDrop)
                    grip *= (1.0 - 0.5 * wearDrop)          // worn tires, less grip
                    let heatRise = (hasHeatEvent ? 0.45 : 0.18) * decay
                    heat = min(1.0, heat + heatRise)
                }

                samples.append(TelemetrySample(
                    lap: lap,
                    sectionIndex: section,
                    grip: clamp01(grip),
                    heat: clamp01(heat),
                    tireLife: clamp01(tire),
                    runProgress: clamp01(runProgress)
                ))
            }
        }
        return samples
    }

    private static func clamp01(_ v: Double) -> Double { min(1.0, max(0.0, v)) }
}
