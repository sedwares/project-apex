//
//  DailyChallengeService.swift
//  ProjectApex
//
//  Fetches the official daily from Firestore (Decision 4: the client
//  never self-decides the Daily). Protocol-first so tests mock it and
//  DEBUG can opt into local generation.
//
//  PASS 6: adds `bannedOption` to the document mapping, and a
//  cache-only provider so the yesterday reveal can read the OFFICIAL
//  document it already stored instead of regenerating the challenge
//  locally. Regeneration was a quiet violation of Decision 4 — it works
//  only while the backend never publishes anything the generator
//  wouldn't produce, and re-rolled days (ChallengeGenerator's `nonce`)
//  break exactly that assumption.
//

import Foundation
import FirebaseFirestore
import ProjectApexCore

enum ChallengeLoadError: Error, Equatable {
    case unavailable          // no doc / offline / not yet open
    case updateRequired       // simulationVersion mismatch
    case malformed            // doc exists but won't decode
}

@MainActor
protocol ChallengeProviding {
    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge
}

// MARK: - Shared cache

enum ChallengeCache {
    static func key(_ dateKey: String) -> String { "apex.challengeCache.\(dateKey)" }

    static func store(_ challenge: DailyChallenge, in defaults: UserDefaults = .standard) {
        guard let encoded = try? JSONEncoder().encode(challenge) else { return }
        defaults.set(encoded, forKey: key(challenge.dateKey))
    }

    /// The official document as last seen, or nil. Verifies both the
    /// date and the simulation version — a cached challenge from an
    /// older sim is not this app's challenge.
    static func load(_ dateKey: String, from defaults: UserDefaults = .standard) -> DailyChallenge? {
        guard let data = defaults.data(forKey: key(dateKey)),
              let cached = try? JSONDecoder().decode(DailyChallenge.self, from: data),
              cached.dateKey == dateKey,
              cached.simulationVersion == ResultHasher.simulationVersion
        else { return nil }
        return cached
    }
}

// MARK: - Firestore implementation

@MainActor
final class FirestoreChallengeService: ChallengeProviding {

    private let defaults = UserDefaults.standard

    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("challenges").document(dateKey).getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                throw ChallengeLoadError.unavailable
            }
            guard let challenge = ChallengeDocumentMapper.challenge(from: data) else {
                throw ChallengeLoadError.malformed
            }
            guard challenge.simulationVersion == ResultHasher.simulationVersion else {
                throw ChallengeLoadError.updateRequired
            }
            // R15: remember the official document for offline re-opens
            // and for tomorrow's reveal card.
            ChallengeCache.store(challenge, in: defaults)
            return challenge
        } catch ChallengeLoadError.updateRequired {
            throw ChallengeLoadError.updateRequired   // never mask with cache
        } catch ChallengeLoadError.malformed {
            throw ChallengeLoadError.malformed
        } catch {
            // Network trouble: serve the cached OFFICIAL document if we
            // have this exact day. Still server-published, still
            // deterministic — never locally generated (Decision 4).
            if let cached = ChallengeCache.load(dateKey, from: defaults) {
                DebugLog.log("challenge served from offline cache for \(dateKey)", error)
                return cached
            }
            DebugLog.log("challenge fetch failed for \(dateKey)", error)
            throw ChallengeLoadError.unavailable
        }
    }
}

// MARK: - Cache-only provider (yesterday's reveal)

/// Reads only what the app has already seen from the server. Never
/// generates, never hits the network.
///
/// This is what the reveal card must use. Regenerating yesterday with
/// ChallengeGenerator produces the right answer only when the published
/// document happened to match the generator's canonical draw — which
/// stops being true the first time a day is hand-tuned or re-rolled,
/// and then the card confidently shows the optimal setup for a
/// challenge nobody played.
@MainActor
final class CachedOfficialChallengeService: ChallengeProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge {
        guard let cached = ChallengeCache.load(dateKey, from: defaults) else {
            throw ChallengeLoadError.unavailable
        }
        return cached
    }
}

// MARK: - Document mapping

enum ChallengeDocumentMapper {

    static func challenge(from data: [String: Any]) -> DailyChallenge? {
        guard
            let dateKey = data["dateKey"] as? String,
            let seedString = data["seed"] as? String,
            let seed = UInt64(seedString),
            let weatherRaw = data["weather"] as? String,
            let weather = Weather(rawValue: weatherRaw),
            let budget = (data["budget"] as? Int) ?? (data["budget"] as? NSNumber)?.intValue,
            let simulationVersion = data["simulationVersion"] as? String,
            let minMillis = (data["minPossibleAverageLapMillis"] as? Int)
                ?? (data["minPossibleAverageLapMillis"] as? NSNumber)?.intValue,
            let circuitMap = data["circuit"] as? [String: Any],
            let circuitId = circuitMap["id"] as? String,
            let circuitName = circuitMap["name"] as? String,
            let archetypeRaw = circuitMap["archetype"] as? String,
            let archetype = CircuitArchetype(rawValue: archetypeRaw),
            let sectionRaws = circuitMap["sections"] as? [String]
        else { return nil }

        let sections = sectionRaws.compactMap(TrackSectionType.init(rawValue:))
        guard sections.count == sectionRaws.count, sections.count >= 3 else { return nil }

        // The day's technical regulation. The key MUST be present:
        //   ""            → unrestricted day
        //   a raw value    → that option is banned
        //   absent         → MALFORMED
        //
        // Treating "absent" as "unrestricted" is the tempting choice and
        // it is wrong. apex-publish shipped without writing this field at
        // all; a lenient decoder would have played every published day
        // unregulated, with nothing anywhere reporting a problem — the
        // mechanic simply wouldn't have existed in production. A missing
        // field is a publishing bug and it should be loud.
        //
        // An unrecognised value is malformed for the same reason: quietly
        // dropping a ban the server intended would let the client submit
        // a setup the security rules then reject.
        guard let bannedRaw = data["bannedOption"] as? String else { return nil }
        var banned: EngineeringOptionID?
        if !bannedRaw.isEmpty {
            guard let parsed = EngineeringOptionID(rawValue: bannedRaw) else { return nil }
            banned = parsed
        }

        return DailyChallenge(
            id: "apex-\(dateKey)",
            dateKey: dateKey,
            seed: seed,
            circuit: Circuit(id: circuitId, name: circuitName, archetype: archetype, sections: sections),
            weather: weather,
            budget: budget,
            simulationVersion: simulationVersion,
            minPossibleAverageLapMillis: minMillis,
            bannedOption: banned
        )
    }
}

// MARK: - Local (DEBUG dev fallback — Decision 4, opt-in)

@MainActor
final class LocalChallengeService: ChallengeProviding {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge {
        guard let challenge = ChallengeGenerator.generate(dateKey: dateKey) else {
            throw ChallengeLoadError.malformed
        }
        // Cache what we served, exactly as the Firestore service does.
        //
        // Without this the yesterday-reveal card can never appear while
        // developing on the local fallback: the reveal deliberately reads
        // the cached document rather than regenerating (Decision 4), and
        // in local mode nothing else ever writes the cache. The card
        // would be silently, permanently absent — which looks like a bug
        // in the reveal rather than an empty cache.
        //
        // DEBUG-only so a locally generated challenge can never be
        // mistaken for an official one in a shipping build.
        #if DEBUG
        ChallengeCache.store(challenge, in: defaults)
        #endif
        return challenge
    }
}
