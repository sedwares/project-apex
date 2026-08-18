//
//  ResultHasher.swift
//  ProjectApexCore
//
//  Reproducible result hash per Phase 0 Addendum §E:
//  SHA256(challengeId + canonicalSetupEncoding + simulationVersion
//         + averageLapTimeMillis + fastestLapTimeMillis)
//  All inputs are integers and stable strings, so the hash is
//  platform-independent. Field separator prevents ambiguity.
//

public nonisolated enum ResultHasher {

    /// Bump whenever simulation math, balance data, or this hash
    /// composition changes. Stored with every leaderboard entry.
    ///
    /// sim-1.1.0 — tuning pass 6. Three changes, all of which move
    /// lap times, so records written under sim-1.0.0 are NOT
    /// comparable and are correctly discarded by the version guards in
    /// DailyViewModel.restoreIfSubmitted and the yesterday reveal:
    ///   • middle options carry real downsides (OptionLibrary)
    ///   • engineEfficient and aeroLowDrag repriced (OptionLibrary)
    ///   • reliability penalty is quadratic, not linear (SimulationEngine)
    /// The daily technical regulation also lands in this version, but
    /// it changes the legal SET rather than the math.
    public static let simulationVersion = "sim-1.1.0"

    public static func hash(
        challengeId: String,
        setup: PlayerSetup,
        averageLapTimeMillis: Int,
        fastestLapTimeMillis: Int
    ) -> String {
        let payload = [
            challengeId,
            CanonicalSetupEncoder.encode(setup),
            simulationVersion,
            String(averageLapTimeMillis),
            String(fastestLapTimeMillis)
        ].joined(separator: "#")
        return SHA256.hexDigest(of: payload)
    }
}
