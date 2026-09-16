//
//  FirebaseBootstrap.swift
//  ProjectApex
//
//  Anonymous auth + player profile. Callsigns (Decision 3): stable
//  ENG-XXXX derived from the uid via the Core SHA256 — no moderation
//  surface in v1.0.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import ProjectApexCore

@MainActor
enum FirebaseBootstrap {

    /// Signs in anonymously (or reuses the session) and ensures the
    /// player profile exists. Returns (uid, callsign).
    /// UserDefaults key proving this install has run before.
    ///
    /// UserDefaults is wiped when the app is deleted. The Firebase Auth
    /// session is NOT — it lives in the iOS Keychain, which survives
    /// deletion and restores on reinstall. So "delete the app and you
    /// get a new identity" was simply not true, and the privacy policy
    /// said it was.
    ///
    /// The mismatch between the two stores is the detector: a Keychain
    /// session with no UserDefaults marker beside it means the app was
    /// deleted and reinstalled, and that session belongs to an install
    /// the player threw away. It is also the dangerous case after an
    /// account deletion — the server-side auth user is gone, so the
    /// restored token authenticates as a uid whose profile and account
    /// no longer exist.
    enum BootstrapError: Error {
        /// A session had to be dropped and could not be. Startup stops
        /// rather than continuing with an identity we already rejected.
        case rejectedSessionSurvived
    }

    static let installMarker = "apex.install.seen"

    /// The uid of an account whose deletion has been queued.
    ///
    /// Written the moment the request lands, and the ONLY thing that
    /// says "never sign in as this again". It exists because the
    /// previous design inferred that from the ABSENCE of the install
    /// marker, and absence is not a statement:
    /// `clearLocalData` removed the marker, but left
    /// `apex.notifications.didRequestAuthorization` behind — and the
    /// upgrade detector counts any apex.* key as prior use, so it read
    /// the next launch as an upgrade and restored the very session the
    /// backend was deleting. Two mechanisms coupled through an implicit
    /// assumption, each correct alone.
    static let pendingDeletionUIDKey = "apex.deletion.pendingUID"

    static func pendingDeletionUID(defaults: UserDefaults) -> String? {
        defaults.string(forKey: pendingDeletionUIDKey)
    }

    /// Whether an absent install marker means UPGRADE rather than fresh
    /// install.
    ///
    /// Deleting an app takes its UserDefaults with it and leaves the
    /// keychain alone, so any apex.* key at all proves this install has
    /// run before — whatever the keychain says. Extracted from
    /// `ensureSignedIn` so the decision can be tested without Firebase,
    /// because getting it wrong signs every existing player out.
    static func isUpgradeFromPreMarkerBuild(defaults: UserDefaults) -> Bool {
        // The marker and the pending-deletion note are bookkeeping, not
        // evidence that anybody has played. Counting them would make the
        // check answer its own question.
        let bookkeeping: Set<String> = [installMarker, pendingDeletionUIDKey]
        return defaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix("apex.") && !bookkeeping.contains(key)
        }
    }

    /// Signs in anonymously (or reuses the session) and ensures the
    /// player profile exists. Returns (uid, callsign).
    static func ensureSignedIn(
        defaults: UserDefaults = .standard
    ) async throws -> (uid: String, displayName: String) {
        // BEFORE anything else: never sign in as an account that is
        // queued for deletion. This is independent of the install
        // marker on purpose — it is a fact recorded at deletion time,
        // not something inferred from what is missing.
        if let pending = pendingDeletionUID(defaults: defaults),
           let current = Auth.auth().currentUser, current.uid == pending {
            do {
                try Auth.auth().signOut()
                DebugLog.log("dropped the session queued for deletion: \(pending)")
                defaults.removeObject(forKey: pendingDeletionUIDKey)
                defaults.set(true, forKey: installMarker)
            } catch {
                CrashReporting.log("could not drop the deleted account's session", error: error)
                throw BootstrapError.rejectedSessionSurvived
            }
        }

        if !defaults.bool(forKey: installMarker) {
            // ── AN ABSENT MARKER IS AMBIGUOUS ────────────────────
            // It means one of two completely different things:
            //
            //   · a genuine fresh install — wipe the inherited session;
            //   · an UPGRADE from a build before this marker existed —
            //     leave the player's identity alone.
            //
            // Build 22 assumed the first and only the first, which would
            // have signed out every existing tester on update: new uid,
            // orphaned leaderboard rows, and — since build 24 — records
            // owned by an account they no longer are. Found in review
            // 2026-09-17 before it reached anybody.
            //
            // The two cases are distinguishable, because deleting an app
            // takes its UserDefaults with it. Any apex.* key at all
            // means this install has run before, whatever the keychain
            // says.
            if Self.isUpgradeFromPreMarkerBuild(defaults: defaults) {
                DebugLog.log("upgrade from a pre-marker build — keeping the existing session")
                defaults.set(true, forKey: installMarker)
            } else if let existing = Auth.auth().currentUser {
                // A session outliving its install: the keychain survives
                // app deletion, UserDefaults does not.
                do {
                    try Auth.auth().signOut()
                    DebugLog.log("fresh install with a keychain session — signed out \(existing.uid)")
                    defaults.set(true, forKey: installMarker)
                } catch {
                    // Not marked done, AND not continued past.
                    //
                    // The first version swallowed this and set the flag
                    // anyway, so one transient failure stranded a player
                    // on a session that should have been dropped. The
                    // second left the flag unset but fell through to use
                    // that session — which then wrote apex.* keys of its
                    // own, so the NEXT launch classified the install as
                    // an upgrade and kept it permanently. Logging a
                    // rejection and then honouring it anyway is worse
                    // than either.
                    CrashReporting.log("install-marker sign-out failed", error: error)
                    throw BootstrapError.rejectedSessionSurvived
                }
            } else {
                defaults.set(true, forKey: installMarker)
            }
        }

        let user: User
        if let current = Auth.auth().currentUser {
            user = current
        } else {
            user = try await Auth.auth().signInAnonymously().user
        }

        // R13 amendment: the stored profile is the source of truth for
        // the display name — never silently rename existing players by
        // recomputing (callsign format changes must not rewrite history).
        let doc = Firestore.firestore().collection("players").document(user.uid)
        if let snapshot = try? await doc.getDocument(),
           snapshot.exists,
           let stored = snapshot.get("displayName") as? String {
            return (user.uid, stored)
        }

        let name = callsign(for: user.uid)
        try? await doc.setData([
            "displayName": name,
            "createdAt": FieldValue.serverTimestamp()
        ])
        return (user.uid, name)
    }

    /// Deterministic engineer callsign: ENG- + 6 digits from SHA256(uid)
    /// (R13: one million combinations).
    static func callsign(for uid: String) -> String {
        let digest = SHA256.digest(of: Array(uid.utf8))
        let digits = digest.prefix(6).map { String($0 % 10) }.joined()
        return "ENG-\(digits)"
    }
}
