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
    static func ensureSignedIn() async throws -> (uid: String, displayName: String) {
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
