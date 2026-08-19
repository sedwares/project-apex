//
//  OptionLibrary.swift
//  ProjectApexCore
//
//  ═══════════════════════════════════════════════════════════════════
//  THE BALANCE SHEET LIVES HERE. Single source of truth for all 24
//  options: costs and stat effects. Tuning after a failed diversity
//  gate means editing THIS file and re-running validation.
//  Matches ProjectApex-BalanceSheet-v0.1.md — if they disagree, this
//  file wins and the doc gets updated.
//  ═══════════════════════════════════════════════════════════════════
//
//  Cost design (tuning pass 3): cheapest legal setup = 62 cr,
//  all-premium = 135 cr, reference budget = 100 cr.
//
//  ── TUNING PASS 6 (sim-1.1.0) ──────────────────────────────────────
//  Problem found by exhaustive analysis: a single STATIC setup —
//  every middle option plus Stiff suspension, 92 cr — beat 88% of the
//  field on average and finished top-10% on 15 of 30 days. A player
//  who found it could stop engaging with the game entirely.
//
//  Root cause: seven of the eight middle options had NO downside at
//  all. They were pure stat gifts at a modest price, so the middle row
//  was never wrong — exactly what a set-and-forget build needs. The
//  extremes all carried real penalties; the middle carried none.
//
//  Fix: every middle option now pays for its safety somewhere. The
//  middle should be SAFE, not FREE. Each downside is deliberately in
//  an axis its own category doesn't govern, so the choice stays a
//  cross-system trade rather than a within-category one:
//      aeroBalanced        −25 topSpeed
//      brakesBalanced      −25 tireDurability
//      coolingStandard     +30 weight
//      engineBalanced      −25 reliability
//      gearBalanced        −20 grip
//      reliabilityBalanced +35 weight
//      suspensionBalanced  −20 braking
//      tiresMedium         +25 heatGeneration
//
//  Also repriced the two options nobody picked. Over 30 days
//  engineEfficient appeared in 6.5% of top-1% setups (2 winning days)
//  and aeroLowDrag in 12.2% (4 days) — both below any reasonable
//  viability line:
//      engineEfficient  7 → 5 cr, heat −120 → −150, +60 cooling.
//                       Now a genuine substitute for Heavy Cooling,
//                       which is the role Hot weather needed it to play.
//      aeroLowDrag     16 → 13 cr, topSpeed +90 → +110, aero +70 → +85.
//                       Sharper identity so it beats gearLong+aeroBalanced
//                       on its home ground instead of duplicating it.
//
//  Predicted from a 180-day Python port: every one of the 24 options in
//  >=16.3% of top-1% setups, most dominant option winning 54% of days,
//  static-setup exploit down from 88.2% to 63.6%.
//
//  MEASURED IN SWIFT over 540 days (2026-08-19): min top-1% share 17%
//  (engineEfficient), most dominant option 57% (suspensionStiff), static
//  exploit 57%. The port was honest about the shape and about half of
//  the numbers; it was three points optimistic about the top of the win
//  rate distribution, which is why the gate's dominance ceiling was
//  recalibrated from 58 to 65. See BatchValidator.Thresholds.
//
//  ⚠️ IF YOU CHANGE ANYTHING IN THIS FILE, RUN THE DRIFT TEST:
//
//      APEX_DRIFT_BATCH=1 swift test -c release -Xswiftc -enable-testing \
//          --filter testOptionWinRatesHaveNotDrifted
//
//  It pins all 24 options against that 540-day baseline in both
//  directions and fails on any move over 8 points. A cost or effect
//  change here also changes lap times, so it needs a simulationVersion
//  bump and a full republish of every unplayed day.
//

public nonisolated enum OptionLibrary {

    /// Reference budget used by validation and the default challenge.
    /// Individual daily challenges may vary around this value.
    public static let referenceBudget: Int = 100

    // MARK: - All options

    public static let allOptions: [EngineeringOption] = [

        // Engine Mode ───────────────────────────────────────────────
        EngineeringOption(
            id: .engineEfficient, category: .engineMode,
            displayName: "Efficient", cost: 5,
            statEffects: [.power: -40, .topSpeed: -40, .heatGeneration: -150,
                          .cooling: 60, .reliability: 60, .weight: -80]
        ),
        EngineeringOption(
            id: .engineBalanced, category: .engineMode,
            displayName: "Balanced", cost: 13,
            statEffects: [.power: 40, .acceleration: 20, .topSpeed: 30,
                          .heatGeneration: 30, .reliability: -25]
        ),
        EngineeringOption(
            id: .enginePower, category: .engineMode,
            displayName: "Power", cost: 25,
            statEffects: [.power: 100, .acceleration: 50, .topSpeed: 85,
                          .heatGeneration: 230, .reliability: -90]
        ),

        // Tires ─────────────────────────────────────────────────────
        EngineeringOption(
            id: .tiresHard, category: .tires,
            displayName: "Hard", cost: 8,
            statEffects: [.grip: -40, .tireDurability: 200]
        ),
        EngineeringOption(
            id: .tiresMedium, category: .tires,
            displayName: "Medium", cost: 12,
            statEffects: [.grip: 40, .tireDurability: 30, .heatGeneration: 25]
        ),
        EngineeringOption(
            id: .tiresSoft, category: .tires,
            displayName: "Soft", cost: 21,
            statEffects: [.grip: 110, .tireDurability: -180, .heatGeneration: 40]
        ),

        // Aerodynamics ──────────────────────────────────────────────
        EngineeringOption(
            id: .aeroLowDrag, category: .aerodynamics,
            displayName: "Low Drag", cost: 13,
            statEffects: [.topSpeed: 110, .aeroEfficiency: 85, .grip: -40, .stability: -50]
        ),
        EngineeringOption(
            id: .aeroBalanced, category: .aerodynamics,
            displayName: "Balanced", cost: 10,
            statEffects: [.aeroEfficiency: 40, .stability: 20, .topSpeed: -25]
        ),
        EngineeringOption(
            id: .aeroHighDownforce, category: .aerodynamics,
            displayName: "High Downforce", cost: 16,
            statEffects: [.grip: 70, .stability: 70, .topSpeed: -75, .aeroEfficiency: -55]
        ),

        // Suspension ────────────────────────────────────────────────
        EngineeringOption(
            id: .suspensionSoft, category: .suspension,
            displayName: "Soft", cost: 9,
            statEffects: [.grip: 70, .stability: -50]
        ),
        EngineeringOption(
            id: .suspensionBalanced, category: .suspension,
            displayName: "Balanced", cost: 11,
            statEffects: [.grip: 15, .stability: 25, .braking: -20]
        ),
        EngineeringOption(
            id: .suspensionStiff, category: .suspension,
            displayName: "Stiff", cost: 15,
            statEffects: [.stability: 70, .braking: 40, .grip: -30]
        ),

        // Gear Ratio ────────────────────────────────────────────────
        EngineeringOption(
            id: .gearShort, category: .gearRatio,
            displayName: "Short", cost: 10,
            statEffects: [.acceleration: 110, .topSpeed: -90]
        ),
        EngineeringOption(
            id: .gearBalanced, category: .gearRatio,
            displayName: "Balanced", cost: 11,
            statEffects: [.acceleration: 30, .topSpeed: 30, .grip: -20]
        ),
        EngineeringOption(
            id: .gearLong, category: .gearRatio,
            displayName: "Long", cost: 14,
            statEffects: [.topSpeed: 110, .acceleration: -80]
        ),

        // Cooling ───────────────────────────────────────────────────
        EngineeringOption(
            id: .coolingLight, category: .cooling,
            displayName: "Light", cost: 6,
            statEffects: [.weight: -60, .cooling: -120]
        ),
        EngineeringOption(
            id: .coolingStandard, category: .cooling,
            displayName: "Standard", cost: 10,
            statEffects: [.cooling: 50, .weight: 30]
        ),
        EngineeringOption(
            id: .coolingHeavy, category: .cooling,
            displayName: "Heavy", cost: 13,
            statEffects: [.cooling: 180, .weight: 70]
        ),

        // Brakes ────────────────────────────────────────────────────
        EngineeringOption(
            id: .brakesConservative, category: .brakes,
            displayName: "Conservative", cost: 7,
            statEffects: [.braking: -60, .reliability: 50, .tireDurability: 40]
        ),
        EngineeringOption(
            id: .brakesBalanced, category: .brakes,
            displayName: "Balanced", cost: 11,
            statEffects: [.braking: 40, .tireDurability: -25]
        ),
        EngineeringOption(
            id: .brakesAggressive, category: .brakes,
            displayName: "Aggressive", cost: 17,
            statEffects: [.braking: 130, .tireDurability: -60,
                          .heatGeneration: 60, .reliability: -40]
        ),

        // Reliability Focus ─────────────────────────────────────────
        EngineeringOption(
            id: .reliabilityRisky, category: .reliabilityFocus,
            displayName: "Risky", cost: 7,
            statEffects: [.weight: -60, .power: 30, .reliability: -140]
        ),
        EngineeringOption(
            id: .reliabilityBalanced, category: .reliabilityFocus,
            displayName: "Balanced", cost: 10,
            statEffects: [.reliability: 30, .weight: 35]
        ),
        EngineeringOption(
            id: .reliabilitySafe, category: .reliabilityFocus,
            displayName: "Safe", cost: 14,
            statEffects: [.reliability: 160, .weight: 50]
        )
    ]

    // MARK: - Lookups

    /// Options grouped into categories, in fixed display order.
    public static let categories: [EngineeringCategory] = {
        EngineeringCategoryID.allCases
            .sorted()
            .map { categoryID in
                EngineeringCategory(
                    id: categoryID,
                    options: allOptions.filter { $0.category == categoryID }
                )
            }
    }()

    /// O(1) option lookup by ID.
    public static let optionsByID: [EngineeringOptionID: EngineeringOption] = {
        Dictionary(uniqueKeysWithValues: allOptions.map { ($0.id, $0) })
    }()

    public static func option(_ id: EngineeringOptionID) -> EngineeringOption {
        guard let option = optionsByID[id] else {
            fatalError("OptionLibrary missing option for id \(id.rawValue)")
        }
        return option
    }

    /// Options belonging to one category, in display order.
    public static func options(in category: EngineeringCategoryID) -> [EngineeringOption] {
        allOptions.filter { $0.category == category }
    }

    /// Options available in a category once the day's technical
    /// regulation is applied. Never empty: a regulation removes one of
    /// three options, leaving two.
    public static func options(
        in category: EngineeringCategoryID,
        banned: EngineeringOptionID?
    ) -> [EngineeringOption] {
        options(in: category).filter { $0.id != banned }
    }

    /// Minimum possible total cost across all 8 categories.
    public static let minimumTotalCost: Int = minimumTotalCost(banned: nil)

    /// Minimum legal cost once the day's regulation is applied. Banning
    /// the cheapest option in a category raises the floor, so the
    /// publisher must check this against the day's budget.
    public static func minimumTotalCost(banned: EngineeringOptionID?) -> Int {
        EngineeringCategoryID.allCases
            .map { options(in: $0, banned: banned).map(\.cost).min() ?? 0 }
            .reduce(0, +)
    }

    /// Maximum possible total cost across all 8 categories.
    public static let maximumTotalCost: Int = {
        EngineeringCategoryID.allCases
            .map { options(in: $0).map(\.cost).max() ?? 0 }
            .reduce(0, +)
    }()
}
