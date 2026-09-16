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
    private static let installMarker = "apex.install.seen"

    /// Signs in anonymously (or reuses the session) and ensures the
    /// player profile exists. Returns (uid, callsign).
    static func ensureSignedIn(
        defaults: UserDefaults = .standard
    ) async throws -> (uid: String, displayName: String) {
        if !defaults.bool(forKey: installMarker) {
            if Auth.auth().currentUser != nil {
                // A session outliving its install. Drop it so the line
                // below mints a genuinely new anonymous identity.
                DebugLog.log("fresh install with a keychain session — signing out first")
                try? Auth.auth().signOut()
            }
            defaults.set(true, forKey: installMarker)
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
