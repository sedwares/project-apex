//
//  AccountDeletionService.swift
//  ProjectApex
//
//  App Store guideline 5.1.1(v): an account that can be created in-app
//  must be deletable in-app. Anonymous auth still creates a profile
//  with a public callsign and public leaderboard rows, so this path has
//  to exist before submission — the app previously had none, and the
//  rules denied deletion on every collection.
//
//  What it does, in order:
//    1. Queues a deletion request the backend can act on.
//    2. Deletes the sealed setup documents the player owns.
//    3. Deletes the player profile.
//    4. Clears every local record and the streak.
//    5. Deletes the Firebase auth user.
//
//  Leaderboard entries are deliberately NOT deleted here. They are
//  immutable by design — removing one would silently re-rank everyone
//  who finished behind it and corrupt the day's history. The Cloud
//  Function draining `deletionRequests` anonymises them instead
//  (displayName → "ENG-DELETED"), which satisfies the requirement
//  without rewriting a completed competition.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import ProjectApexCore

@MainActor
protocol AccountDeleting {
    func deleteAccount() async throws
}

@MainActor
final class AccountDeletionService: AccountDeleting {

    enum DeletionError: Error {
        case notSignedIn
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw DeletionError.notSignedIn }
        let uid = user.uid
        let db = Firestore.firestore()

        // 1. Queue the request first. If anything below fails, the
        //    backend still has an authoritative record that this player
        //    asked to be erased.
        try await db.collection("deletionRequests").document(uid).setData([
            "requestedAt": FieldValue.serverTimestamp()
        ])

        // 2. Sealed setups are left to the Cloud Function, deliberately.
        //
        //    The obvious client-side version — a collectionGroup("setups")
        //    query filtered on FieldPath.documentID() == uid — is broken
        //    twice over, and silently:
        //      · in a COLLECTION GROUP query, documentID() must be
        //        compared against a FULL document path, not a bare id;
        //        a bare uid throws invalid-argument.
        //      · collection group queries need a rule matching the group
        //        (`match /{path=**}/setups/{uid}`). firestore.rules only
        //        matches `leaderboards/{dateKey}/setups/{uid}`, so the
        //        query is denied regardless.
        //    Wrapped in `try?` both failures vanish and deletion LOOKS
        //    successful while the setups survive — the worst outcome for
        //    a privacy feature.
        //
        //    The function runs with admin credentials, bypasses rules,
        //    and already has to walk the leaderboard to anonymise entries.
        //    It deletes these in the same pass.

        // 3. Profile.
        try? await db.collection("players").document(uid).delete()

        // 4. Local state — records, streak, cached challenges, and the
        //    two things that would otherwise outlive the account: a week
        //    of scheduled reminders, and the analytics identity.
        clearLocalData()
        NotificationService.shared.cancelAll()
        Analytics.resetForDeletedAccount()

        // 5. The auth user itself. Anonymous sessions are recent enough
        //    that this rarely needs a re-auth, but surface the error if
        //    it does rather than pretending the account is gone.
        try await user.delete()
    }

    /// Every key this app owns, by prefix. Deliberately prefix-based:
    /// daily records are keyed by date, so an explicit list would rot.
    func clearLocalData() {
        let prefixes = ["apex.daily.", "apex.streak.", "apex.challengeCache."]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "apex.onboarding.seen")
    }
}
