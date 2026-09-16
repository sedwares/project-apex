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
    /// Settle "is this a fresh install, an upgrade, or an account we
    /// must refuse" BEFORE anything else can touch UserDefaults.
    ///
    /// ── WHY THIS IS NOT INSIDE ensureSignedIn ANY MORE ──────────
    /// It was, and that made it a race it could lose. DailyHomeView
    /// attaches several `.task` blocks; one of them calls
    /// `Analytics.trackOpen` SYNCHRONOUSLY before its first await, and
    /// that writes `apex.analytics.firstOpenDayNumber`. The other
    /// reaches this code only through an `await`. So on a genuine
    /// reinstall — keychain session present, UserDefaults empty —
    /// analytics could write first, the detector would find an apex.*
    /// key, call it an upgrade, and keep the identity the reinstall was
    /// supposed to replace. Silently, and only sometimes.
    ///
    /// Called from ProjectApexApp.init(), before any view exists, so no
    /// task can get in front of it. Idempotent: once the marker is set
    /// both branches are no-ops, so ensureSignedIn calling it again
    /// costs nothing and guarantees it happened.
    ///
    /// Returns false when a session that had to be dropped could not
    /// be. Startup must not continue on an identity it rejected.
    @discardableResult
    static func resolveInstallState(defaults: UserDefaults = .standard) -> Bool {
        // Never sign in as an account queued for deletion. Independent
        // of the install marker on purpose — a fact recorded at deletion
        // time, not something inferred from what is missing.
        if let pending = pendingDeletionUID(defaults: defaults),
           let current = Auth.auth().currentUser, current.uid == pending {
            do {
                try Auth.auth().signOut()
                DebugLog.log("dropped the session queued for deletion: \(pending)")
                defaults.removeObject(forKey: pendingDeletionUIDKey)
                defaults.set(true, forKey: installMarker)
            } catch {
                CrashReporting.log("could not drop the deleted account's session", error: error)
                return false
            }
        }

        guard !defaults.bool(forKey: installMarker) else { return true }

        // An absent marker means one of two opposite things: a genuine
        // fresh install, or an upgrade from a build before the marker
        // existed. Deleting an app takes its UserDefaults and leaves the
        // keychain, so any apex.* key proves this install has run before.
        if isUpgradeFromPreMarkerBuild(defaults: defaults) {
            DebugLog.log("upgrade from a pre-marker build — keeping the existing session")
            defaults.set(true, forKey: installMarker)
            return true
        }

        guard let existing = Auth.auth().currentUser else {
            defaults.set(true, forKey: installMarker)
            return true
        }

        // A session outliving its install.
        do {
            try Auth.auth().signOut()
            DebugLog.log("fresh install with a keychain session — signed out \(existing.uid)")
            defaults.set(true, forKey: installMarker)
            return true
        } catch {
            // Not marked done, and the caller must not continue: logging
            // a rejection and then honouring the session anyway is worse
            // than either.
            CrashReporting.log("install-marker sign-out failed", error: error)
            return false
        }
    }

    /// Signs in anonymously (or reuses the session) and ensures the
    /// player profile exists. Returns (uid, callsign).
    static func ensureSignedIn(
        defaults: UserDefaults = .standard
    ) async throws -> (uid: String, displayName: String) {
        // Already done in App.init; repeated here because a guarantee
        // that lives in one call site is not a guarantee.
        guard resolveInstallState(defaults: defaults) else {
            throw BootstrapError.rejectedSessionSurvived
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
