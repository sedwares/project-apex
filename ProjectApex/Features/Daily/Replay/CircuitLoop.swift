//
//  CircuitLoop.swift
//  ProjectApex
//
//  The circuit as a driveable curve: a closed loop whose SHAPE comes
//  from the day's actual sections, plus the speed profile that says how
//  fast the car crosses each one.
//
//  ── WHY THIS WAS REBUILT (pass 8) ──────────────────────────────────
//  The old loop was a fixed superellipse. Every circuit in the game —
//  a 2.6-exponent technical track and a flat-out high-speed blast —
//  traced the identical oval, and the eleven typed sections the
//  generator works so hard to produce never reached the screen. The
//  replay was the same picture every day.
//
//  It also drove the car at a constant rate, so a hairpin and the main
//  straight went by at the same speed. A lap had no rhythm, which is
//  most of what makes a lap feel like a lap.
//
//  Both come from the same table now. Each section carries a relative
//  SPEED and a radius MODULATION:
//
//    · arc length  = speed × baseTime  — a long straight eats five
//      times the loop a hairpin does, so the shape reflects where the
//      lap actually is.
//    · time        = baseTime          — and since arc ≠ time, the car
//      must cover the straight's arc faster. The speed variation falls
//      out of the geometry instead of being animated on top of it.
//
//  Modulation pushes straights outward (flattening that side into a
//  run) and pinches hairpins inward. Values are interpolated between
//  section CENTRES with a raised cosine, so the loop is smooth by
//  construction and can never kink at a boundary.
//
//  Closure is guaranteed: this is a radial function of angle, so the
//  curve always closes and never self-intersects while 1 + m > 0.
//
//  Pure value type: no rendering, no state, no SpriteKit.
//

import CoreGraphics
import Foundation
import ProjectApexCore

struct CircuitLoop {

    /// SpriteKit's origin is bottom-left (y up); SwiftUI's is top-left
    /// (y down). Same maths in both would render the loop mirrored and
    /// send the car around the wrong way. Callers declare their axis.
    enum VerticalAxis {
        case up      // SpriteKit / RaceScene
        case down    // SwiftUI Path
    }

    let size: CGSize
    let inset: CGFloat
    let axis: VerticalAxis
    let sections: [TrackSectionType]
    /// Superellipse exponent. 2 is a plain ellipse; higher flattens the
    /// sides toward straights. Set from the archetype so a high-speed
    /// circuit reads long and flat before a single section is applied.
    let exponent: Double

    // Precomputed per-section tables, all normalised to 0...1.
    private let arcStart: [Double]
    private let arcFrac: [Double]
    private let timeStart: [Double]
    private let timeFrac: [Double]
    /// Modulation sampled at each section's arc centre.
    private let centres: [Double]
    private let mods: [Double]

    /// Normalised TIME at which each of the three sectors begins.
    /// Sector 1 always starts at 0.
    let sectorStartTimes: [Double]

    init(size: CGSize,
         sections: [TrackSectionType],
         archetype: CircuitArchetype = .balanced,
         inset: CGFloat = 46,
         axis: VerticalAxis = .up) {
        self.size = size
        self.inset = inset
        self.axis = axis
        self.exponent = Self.exponent(for: archetype)

        // Every table below is built from `safe`, so `sections` must be
        // the same array — arcPosition() indexes the tables by
        // sections.indices and would trap on a length mismatch.
        let safe: [TrackSectionType] = sections.isEmpty ? [.longStraight] : sections
        self.sections = safe
        let arcWeights = safe.map { Self.speed(of: $0) * Double($0.baseTimeMillis) }
        let timeWeights = safe.map { Double($0.baseTimeMillis) }
        let arcTotal = max(arcWeights.reduce(0, +), .leastNonzeroMagnitude)
        let timeTotal = max(timeWeights.reduce(0, +), .leastNonzeroMagnitude)

        var aFrac: [Double] = [], aStart: [Double] = []
        var tFrac: [Double] = [], tStart: [Double] = []
        var aRun = 0.0, tRun = 0.0
        for i in safe.indices {
            let af = arcWeights[i] / arcTotal
            let tf = timeWeights[i] / timeTotal
            aStart.append(aRun); aFrac.append(af); aRun += af
            tStart.append(tRun); tFrac.append(tf); tRun += tf
        }
        self.arcStart = aStart; self.arcFrac = aFrac
        self.timeStart = tStart; self.timeFrac = tFrac
        self.centres = safe.indices.map { aStart[$0] + aFrac[$0] / 2 }
        self.mods = safe.map { Self.modulation(of: $0) }

        // Sector boundaries use the SAME split as Circuit.sectorRanges
        // — thirds, remainder front-loaded — so a gate on screen is the
        // gate the sector times were measured against.
        let n = safe.count
        let base = n / 3, rem = n % 3
        var starts: [Double] = []
        var idx = 0
        for s in 0..<3 {
            starts.append(tStart[min(idx, n - 1)])
            idx += base + (s < rem ? 1 : 0)
        }
        self.sectorStartTimes = starts
    }

    // MARK: - Per-section character

    /// Relative speed, 1.0 being flat out. Combined with `baseTimeMillis`
    /// this sets both how much of the loop a section occupies and how
    /// quickly the car crosses it.
    static func speed(of section: TrackSectionType) -> Double {
        switch section {
        case .longStraight:     return 1.00
        case .finalStraight:    return 0.96
        case .shortStraight:    return 0.76
        case .elevationDrop:    return 0.70
        case .fastCorner:       return 0.68
        case .elevationClimb:   return 0.60
        case .bumpySector:      return 0.56
        case .mediumCorner:     return 0.54
        case .heavyBrakingZone: return 0.46
        case .technicalSector:  return 0.46
        case .slowCorner:       return 0.40
        case .hairpin:          return 0.28
        }
    }

    /// Radius push. Positive bulges the loop outward, flattening that
    /// side into something that reads as a run; negative pinches it in.
    static func modulation(of section: TrackSectionType) -> Double {
        switch section {
        case .longStraight:     return  0.16
        case .finalStraight:    return  0.13
        case .shortStraight:    return  0.05
        case .elevationClimb:   return  0.04
        case .elevationDrop:    return  0.04
        case .fastCorner:       return  0.02
        case .bumpySector:      return -0.02
        case .mediumCorner:     return -0.06
        case .heavyBrakingZone: return -0.10
        case .slowCorner:       return -0.14
        case .technicalSector:  return -0.15
        case .hairpin:          return -0.26
        }
    }

    /// The archetype sets the loop's overall character before any
    /// section touches it: high-speed circuits read long and flat,
    /// technical ones nearly round.
    static func exponent(for archetype: CircuitArchetype) -> Double {
        switch archetype {
        case .highSpeed: return 5.0
        case .balanced:  return 4.0
        case .mountain:  return 3.3
        case .street:    return 3.0
        case .technical: return 2.6
        }
    }

    // MARK: - Geometry

    /// Smooth radius modulation at arc position `t`, interpolated
    /// between section centres so there is no kink at any boundary.
    private func modulation(atArc t: Double) -> Double {
        let n = centres.count
        guard n > 1 else { return mods.first ?? 0 }
        let t = wrap(t)

        var i = n - 1
        for k in 0..<n where centres[k] <= t { i = k }
        if t < centres[0] { i = n - 1 }
        let j = (i + 1) % n

        var span = centres[j] - centres[i]
        if span <= 0 { span += 1 }
        var local = t - centres[i]
        if local < 0 { local += 1 }

        let u = span > 0 ? min(max(local / span, 0), 1) : 0
        let eased = (1 - cos(u * .pi)) / 2
        return mods[i] + (mods[j] - mods[i]) * eased
    }

    /// Point on the loop for arc position `t` in 0...1. t = 0 is
    /// start/finish, and increasing t travels the same visual direction
    /// in both axis conventions.
    func point(at t: Double) -> CGPoint {
        let t = wrap(t)
        let cx = size.width / 2
        let cy = size.height / 2
        let rx = size.width / 2 - inset
        let ry = size.height / 2 - inset

        let a = t * 2 * .pi
        let ca = cos(a), sa = sin(a)
        let ux = pow(abs(ca), 2.0 / exponent) * (ca < 0 ? -1 : 1)
        let uy = pow(abs(sa), 2.0 / exponent) * (sa < 0 ? -1 : 1)
        let m = 1 + modulation(atArc: t)

        let y = axis == .up
            ? cy + CGFloat(uy * m) * ry
            : cy - CGFloat(uy * m) * ry
        return CGPoint(x: cx + CGFloat(ux * m) * rx, y: y)
    }

    /// Facing angle in radians at arc position `t`.
    func heading(at t: Double, epsilon: Double = 0.0015) -> CGFloat {
        let back = point(at: t - epsilon)
        let ahead = point(at: t + epsilon)
        return atan2(ahead.y - back.y, ahead.x - back.x)
    }

    // MARK: - Time to distance

    /// Arc position for a normalised TIME through the lap. This is what
    /// makes the car quick down the straights and slow through the
    /// hairpin: equal slices of time buy unequal slices of track.
    func arcPosition(atLapTime f: Double) -> Double {
        let f = wrap(f)
        for i in sections.indices {
            let t0 = timeStart[i]
            let width = timeFrac[i]
            if f < t0 + width || i == sections.count - 1 {
                let local = width > 0 ? (f - t0) / width : 0
                return arcStart[i] + arcFrac[i] * min(max(local, 0), 1)
            }
        }
        return 0
    }

    /// Index of the section being driven at a normalised lap time.
    func sectionIndex(atLapTime f: Double) -> Int {
        let f = wrap(f)
        for i in sections.indices where f < timeStart[i] + timeFrac[i] {
            return i
        }
        return max(sections.count - 1, 0)
    }

    /// Relative speed right now, 0...1. Drives the trail length and the
    /// speed bar — the car looks fast because it IS covering more track.
    func speed(atLapTime f: Double) -> Double {
        let i = sectionIndex(atLapTime: f)
        guard sections.indices.contains(i) else { return 1 }
        return Self.speed(of: sections[i])
    }

    /// Arc position of each sector gate, for drawing the markers.
    var sectorGateArcs: [Double] {
        sectorStartTimes.map { arcPosition(atLapTime: $0) }
    }

    /// Each section with the stretch of loop it occupies, so the scene
    /// can decorate corners differently from straights.
    var sectionArcs: [(section: TrackSectionType, start: Double, end: Double)] {
        sections.indices.map {
            (section: sections[$0],
             start: arcStart[$0],
             end: arcStart[$0] + arcFrac[$0])
        }
    }

    /// Signed turn rate at `t`. Positive means the track bends LEFT.
    func curvature(at t: Double, epsilon: Double = 0.004) -> CGFloat {
        var delta = heading(at: t + epsilon) - heading(at: t - epsilon)
        while delta >  .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }

    /// A point offset perpendicular to the track, on the INSIDE of the
    /// turn — which is where a kerb goes.
    ///
    /// This used to offset toward the loop's centre, which is only right
    /// on a convex loop. An S-bend turns one way and then the other, so
    /// its second curve has its inside on the opposite edge, and kerbs
    /// laid toward the centre crossed the track to get there. Taking the
    /// side from the local curvature is correct everywhere.
    func apexSidePoint(at t: Double, offset: CGFloat) -> CGPoint {
        let p = point(at: t)
        let normal = heading(at: t) + (curvature(at: t) > 0 ? .pi / 2 : -.pi / 2)
        return CGPoint(x: p.x + cos(normal) * offset,
                       y: p.y + sin(normal) * offset)
    }

    // MARK: - Kerbs

    /// How much of a section's arc carries kerb, or nil for none.
    /// Tighter corner, more kerb — a hairpin is almost all apex, while a
    /// fast corner is taken flat and gets nothing.
    ///
    /// This lives here rather than in the scene because the replay is no
    /// longer the only surface that draws a circuit. Two copies of a
    /// table like this is how the sector thresholds ended up
    /// contradicting the debrief prose.
    static func kerbCoverage(_ section: TrackSectionType) -> Double? {
        switch section {
        case .hairpin:          return 0.66
        case .slowCorner:       return 0.56
        case .technicalSector:  return 0.50
        case .heavyBrakingZone: return 0.46
        case .mediumCorner:     return 0.38
        case .fastCorner, .longStraight, .shortStraight, .finalStraight,
             .elevationClimb, .elevationDrop, .bumpySector:
            return nil
        }
    }

    struct KerbStripe {
        let point: CGPoint
        let heading: CGFloat
        /// Kerbs alternate; this says which colour this one takes.
        let isRed: Bool
    }

    /// Every kerb stripe on the lap, already placed and oriented. The
    /// caller only decides how to paint them.
    func kerbStripes(offset: CGFloat, density: Double = 105) -> [KerbStripe] {
        var stripes: [KerbStripe] = []
        for span in sectionArcs {
            guard let coverage = Self.kerbCoverage(span.section) else { continue }
            let width = span.end - span.start
            let covered = width * coverage
            let from = span.start + (width - covered) / 2
            let count = max(2, Int(covered * density))
            for i in 0..<count {
                let t = from + covered * (Double(i) + 0.5) / Double(count)
                stripes.append(KerbStripe(
                    point: apexSidePoint(at: t, offset: offset),
                    heading: heading(at: t),
                    isRed: i % 2 == 0
                ))
            }
        }
        return stripes
    }

    /// The closed loop as a path, sampled into `steps` segments.
    func path(steps: Int = 320) -> CGPath {
        let path = CGMutablePath()
        for i in 0...steps {
            let pt = point(at: Double(i) / Double(steps))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func wrap(_ t: Double) -> Double {
        let r = t.truncatingRemainder(dividingBy: 1.0)
        return r < 0 ? r + 1 : r
    }
}
