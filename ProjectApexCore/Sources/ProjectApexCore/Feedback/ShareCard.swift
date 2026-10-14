//
//  ShareCard.swift
//  ProjectApexCore
//
//  The day's result as something worth sending: day, circuit, finishing
//  position against the five rivals, medal, a coloured block per
//  sector, and the gap to the optimum.
//
//  ── THE ONE RULE: NO SPOILERS ──────────────────────────────────────
//  The setup is the puzzle answer, so the card never names a part, an
//  option, or even the setup's identity — only how it went. Everyone
//  can post theirs on the day without giving anything away. A test
//  pins this.
//
//  Sector blocks follow the timing-screen colours the replay already
//  uses: purple = matched or beat the optimum, green = within 350ms a
//  lap, yellow = within 850ms, red = beyond.
//

public nonisolated struct ShareCard: Sendable, Equatable {

    public static let appURL = "https://apps.apple.com/app/id6796399483"

    public let dayNumber: Int?
    public let circuitName: String
    public let weatherName: String
    /// 1-based finishing position against the rival field.
    public let position: Int
    public let fieldSize: Int
    public let medal: Medal?
    /// One per sector; empty until the day's targets are known.
    public let sectorTiers: [SectorTier]
    /// Average lap given up to the optimum; nil until targets are known.
    public let gapToBestMillis: Int?
    public let averageLapMillis: Int

    public init(
        dayNumber: Int?, circuitName: String, weatherName: String,
        position: Int, fieldSize: Int, medal: Medal?,
        sectorTiers: [SectorTier], gapToBestMillis: Int?, averageLapMillis: Int
    ) {
        self.dayNumber = dayNumber
        self.circuitName = circuitName
        self.weatherName = weatherName
        self.position = position
        self.fieldSize = fieldSize
        self.medal = medal
        self.sectorTiers = sectorTiers
        self.gapToBestMillis = gapToBestMillis
        self.averageLapMillis = averageLapMillis
    }

    /// Builds the card. `rivals` is RivalField.rivals(for:) — passed in
    /// so a caller that already simulated them doesn't pay twice.
    public static func make(
        result: SimulationResult,
        challenge: DailyChallenge,
        targets: DayTargets?,
        rivals: [RaceEntrant]
    ) -> ShareCard {
        // Same rule as RaceTimeline.classification with the player at
        // index 0: ties go to the player.
        let ahead = rivals.filter { $0.averageLapMillis < result.averageLapTimeMillis }.count

        var tiers: [SectorTier] = []
        var gap: Int?
        if let targets {
            if let lost = FeedbackEngine.sectorsLostToOptimal(
                result: result,
                optimalSectorTotalsMillis: targets.optimalSectorTotalsMillis
            ) {
                tiers = lost.map { SectorTier.of(deltaMillis: $0) }
            }
            gap = max(0, result.averageLapTimeMillis - targets.bestAverageLapMillis)
        }

        return ShareCard(
            dayNumber: ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey),
            circuitName: challenge.circuit.archetype.displayName,
            weatherName: challenge.weather.displayName,
            position: ahead + 1,
            fieldSize: rivals.count + 1,
            medal: targets?.medal(forAverageLapMillis: result.averageLapTimeMillis),
            sectorTiers: tiers,
            gapToBestMillis: gap,
            averageLapMillis: result.averageLapTimeMillis
        )
    }

    // MARK: - Words

    public var title: String {
        dayNumber.map { "PROJECT APEX · Day \($0)" } ?? "PROJECT APEX"
    }

    public var positionText: String { "P\(position) of \(fieldSize)" }

    public var medalText: String {
        medal.map { "\($0.emoji) \($0.label)" } ?? "No medal"
    }

    public var sectorBlocks: String {
        sectorTiers.map(Self.emoji(for:)).joined()
    }

    /// "+0.840s to optimal", "Optimal".
    public var gapText: String? {
        guard let gap = gapToBestMillis else { return nil }
        if gap == 0 { return "Optimal setup" }
        return "+\(Self.seconds(gap))s to optimal"
    }

    /// The group-chat version. Same facts as the image.
    public var text: String {
        var lines = [title, "\(circuitName) · \(weatherName)"]
        lines.append("🏁 \(positionText)   \(medalText)")
        if !sectorTiers.isEmpty {
            var line = sectorBlocks
            if let gap = gapText { line += "   " + gap }
            lines.append(line)
        }
        lines.append(Self.appURL)
        return lines.joined(separator: "\n")
    }

    public static func emoji(for tier: SectorTier) -> String {
        switch tier {
        case .ahead, .optimal: return "🟪"
        case .onPace, .close:  return "🟩"
        case .offPace:         return "🟨"
        case .weak:            return "🟥"
        }
    }

    /// 840 → "0.840"
    static func seconds(_ millis: Int) -> String {
        let ms = abs(millis) % 1000
        let pad = ms < 10 ? "00" : (ms < 100 ? "0" : "")
        return "\(abs(millis) / 1000).\(pad)\(ms)"
    }
}
