//
//  LeaderboardService.swift
//  ProjectApex
//
//  Global leaderboard over Firestore aggregate COUNT queries
//  (Decision 2): rank, percentile, and tie-count computed by counting,
//  never by downloading the field. Submission is create-only and
//  idempotent — the document ID is the uid.
//
//  PASS 6, two changes:
//
//  1. SUBMISSION IS NOW SPLIT ACROSS TWO DOCUMENTS. The public entry
//     carries the name, the times and the hash; the setup goes to a
//     sibling `setups/{uid}` document that nobody can read until the
//     day closes. Previously `selections` sat in the world-readable
//     entry, so anyone could pull the leading player's setup mid-day
//     and copy it. See firestore.rules.
//
//  2. STANDINGS ARE CACHED. `standing()` costs four aggregate queries
//     plus a document read, and the rank barely moves after the first
//     hour — this was the dominant Firestore cost at any real scale.
//     The cache is per (dateKey, uid) with a short TTL and is bypassed
//     by an explicit refresh.
//

import Foundation
import FirebaseFirestore
import ProjectApexCore

struct LeaderboardStanding: Equatable {
    let rank: Int
    let totalEntries: Int
    let tieCount: Int
    /// "Top X%" — percentile-first display per the addendum.
    var topPercent: Int {
        guard totalEntries > 0 else { return 100 }
        return max(1, (rank * 100 + totalEntries - 1) / totalEntries)
    }
}

struct LeaderboardRow: Identifiable, Equatable {
    let id: String            // uid
    let displayName: String
    let averageLapTimeMillis: Int
    let isYou: Bool
}

@MainActor
protocol LeaderboardServicing {
    /// Idempotent: creates the entry if missing, then returns standing.
    func submitAndStand(record: DailyRecord, uid: String, displayName: String) async throws -> LeaderboardStanding
    func standing(dateKey: String, uid: String) async throws -> LeaderboardStanding
    func topEntries(dateKey: String, limit: Int, uid: String) async throws -> [LeaderboardRow]

    /// `force` bypasses the standing cache — wire it to pull-to-refresh
    /// only. Defaulted below, so a service without a cache (every mock,
    /// for instance) conforms without implementing it.
    func standing(dateKey: String, uid: String, force: Bool) async throws -> LeaderboardStanding
}

extension LeaderboardServicing {
    /// Caching is an implementation detail, so the default simply
    /// ignores the hint.
    ///
    /// This stays a protocol REQUIREMENT rather than living only in the
    /// extension, despite having a default: callers hold
    /// `LeaderboardServicing` existentially, and an extension-only
    /// method is statically dispatched — the real cache-bypassing
    /// implementation in FirestoreLeaderboardService would never be
    /// reached and `force` would silently do nothing.
    func standing(dateKey: String, uid: String, force: Bool) async throws -> LeaderboardStanding {
        try await standing(dateKey: dateKey, uid: uid)
    }
}

@MainActor
final class FirestoreLeaderboardService: LeaderboardServicing {

    /// How long a computed standing stays fresh. The field moves fast
    /// in the first minutes of a UTC day and slowly after that; two
    /// minutes keeps it honest without paying five reads per glance.
    static let standingCacheSeconds: TimeInterval = 120

    private struct CachedStanding {
        let standing: LeaderboardStanding
        let at: Date
    }
    private var standingCache: [String: CachedStanding] = [:]

    private var db: Firestore { Firestore.firestore() }

    private func entries(_ dateKey: String) -> CollectionReference {
        db.collection("leaderboards").document(dateKey).collection("entries")
    }

    private func setups(_ dateKey: String) -> CollectionReference {
        db.collection("leaderboards").document(dateKey).collection("setups")
    }

    func submitAndStand(record: DailyRecord, uid: String, displayName: String) async throws -> LeaderboardStanding {
        let entryDoc = entries(record.dateKey).document(uid)

        // Idempotent create: if our row exists, skip straight to standing.
        // R9: two devices racing is harmless — the doc ID is the uid and
        // rules forbid update, so the loser's create is REJECTED by
        // Firestore; we treat that rejection as success-if-entry-exists.
        let existing = try await entryDoc.getDocument()
        if !existing.exists {
            do {
                try await entryDoc.setData([
                    "displayName": displayName,
                    "averageLapTimeMillis": record.result.averageLapTimeMillis,
                    "fastestLapTimeMillis": record.result.fastestLapTimeMillis,
                    "simulationVersion": ResultHasher.simulationVersion,
                    "resultHash": record.result.resultHash,
                    "submittedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                let recheck = try await entryDoc.getDocument()
                guard recheck.exists else { throw error }
                DebugLog.log("submit create rejected but entry exists — treating as success", error)
            }
        }

        // The sealed half. Written separately and best-effort: if this
        // fails the player still has a valid, ranked entry — they just
        // won't appear in the post-close setup archive. Never let it
        // take down a submission.
        let setupDoc = setups(record.dateKey).document(uid)
        if (try? await setupDoc.getDocument())?.exists != true {
            var selections: [String: String] = [:]
            for (category, option) in record.selections {
                selections[category.rawValue] = option.rawValue
            }
            do {
                try await setupDoc.setData([
                    "selections": selections,
                    "totalCost": record.selections.values
                        .map { OptionLibrary.option($0).cost }.reduce(0, +),
                    "submittedAt": FieldValue.serverTimestamp()
                ])
            } catch {
                DebugLog.log("sealed setup write failed for \(record.dateKey)", error)
            }
        }

        return try await standing(dateKey: record.dateKey, uid: uid, force: true)
    }

    /// Cached read — the common path, and the one the debrief hits on
    /// every appearance.
    func standing(dateKey: String, uid: String) async throws -> LeaderboardStanding {
        try await standing(dateKey: dateKey, uid: uid, force: false)
    }

    func standing(dateKey: String, uid: String, force: Bool) async throws -> LeaderboardStanding {
        let key = "\(dateKey)#\(uid)"
        if !force, let cached = standingCache[key],
           Date().timeIntervalSince(cached.at) < Self.standingCacheSeconds {
            return cached.standing
        }

        let collection = entries(dateKey)

        // Own row (for the average + server timestamp).
        let mine = try await collection.document(uid).getDocument()
        guard mine.exists,
              let myAverage = (mine.get("averageLapTimeMillis") as? NSNumber)?.intValue,
              let myTimestamp = mine.get("submittedAt") as? Timestamp
        else { throw ChallengeLoadError.unavailable }

        async let fasterCount = collection
            .whereField("averageLapTimeMillis", isLessThan: myAverage)
            .count.getAggregation(source: .server)
        async let tiesBeforeCount = collection
            .whereField("averageLapTimeMillis", isEqualTo: myAverage)
            .whereField("submittedAt", isLessThan: myTimestamp)
            .count.getAggregation(source: .server)
        async let tiesTotalCount = collection
            .whereField("averageLapTimeMillis", isEqualTo: myAverage)
            .count.getAggregation(source: .server)
        async let totalCount = collection
            .count.getAggregation(source: .server)

        let (faster, tiesBefore, ties, total) = try await (
            fasterCount.count.intValue,
            tiesBeforeCount.count.intValue,
            tiesTotalCount.count.intValue,
            totalCount.count.intValue
        )

        let standing = LeaderboardStanding(
            rank: faster + tiesBefore + 1,
            totalEntries: total,
            tieCount: ties
        )
        standingCache[key] = CachedStanding(standing: standing, at: Date())
        return standing
    }

    func topEntries(dateKey: String, limit: Int, uid: String) async throws -> [LeaderboardRow] {
        let snapshot = try await entries(dateKey)
            .order(by: "averageLapTimeMillis")
            .order(by: "submittedAt")
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.map { doc in
            LeaderboardRow(
                id: doc.documentID,
                displayName: (doc.get("displayName") as? String) ?? "ENG-????",
                averageLapTimeMillis: (doc.get("averageLapTimeMillis") as? NSNumber)?.intValue ?? 0,
                isYou: doc.documentID == uid
            )
        }
    }
}
