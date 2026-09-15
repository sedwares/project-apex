//
//  SectorTier.swift
//  ProjectApexCore
//
//  How good a sector was, measured against the optimal setup.
//
//  ── WHY THIS EXISTS ────────────────────────────────────────────────
//  These thresholds used to live in RaceDebriefView as a private
//  `tierLabel(delta:)`, while FeedbackEngine.strengths() independently
//  decided which sector to call "your strongest". Two places, one
//  quantity, no shared definition — so they were free to contradict
//  each other, and on 2026-08-19 they did:
//
//      "Sector 1 was your strongest — only 0.957s off the optimal car"
//
//  printed directly above
//
//      SECTOR 1 — WEAK  +0.957s
//
//  Both were internally correct. The prose named the sector closest to
//  optimal; the chart classed 957ms as Weak. They were measuring the
//  same number and disagreeing about it one line apart.
//
//  It only fires when EVERY sector is in a bad tier, so "strongest"
//  degenerates to "least bad" — and the word "only" makes it worse by
//  implying the gap is small.
//
//  Putting the thresholds here makes the contradiction structurally
//  impossible: the chart and the prose now read from the same source.
//  Core owns the boundaries and the words; the app layer owns the
//  colours, because the palette is not Core's business.
//

public nonisolated enum SectorTier: Sendable, Equatable, CaseIterable {
    /// Quicker than the optimal setup through this sector. Possible
    /// because the optimum minimises the AVERAGE lap, not each sector.
    case ahead
    /// Matched the optimal setup exactly.
    case optimal
    /// Within 80ms.
    case onPace
    /// Within 350ms.
    case close
    /// Within 850ms.
    case offPace
    /// Further than that.
    case weak

    /// Signed delta in milliseconds, player minus optimal, per lap.
    public static func of(deltaMillis: Int) -> SectorTier {
        switch deltaMillis {
        case ..<0:   return .ahead
        case 0:      return .optimal
        case ..<80:  return .onPace
        case ..<350: return .close
        case ..<850: return .offPace
        default:     return .weak
        }
    }

    public var label: String {
        switch self {
        case .ahead:   return "Ahead"
        case .optimal: return "Optimal"
        case .onPace:  return "On pace"
        case .close:   return "Close"
        case .offPace: return "Off pace"
        case .weak:    return "Weak"
        }
    }

    /// Whether a sector in this tier can honestly be called a strength.
    ///
    /// This is the whole point of the type. `strengths()` asks this
    /// before claiming a sector was "your strongest" — if the best
    /// sector on the lap is still Off pace or Weak, the honest sentence
    /// is that it held up best, not that it was good.
    public var isCreditable: Bool {
        switch self {
        case .ahead, .optimal, .onPace, .close: return true
        case .offPace, .weak: return false
        }
    }
}
