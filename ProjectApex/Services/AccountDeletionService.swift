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
//    1. Queues a deletion request the backend can act on. NOTHING
//       local is touched before this succeeds — see below.
//    2. Deletes the player profile (best effort; the function repeats it).
//    3. Deletes the Firebase auth user (best effort, same reason).
//    4. Only then clears local records, the streak, reminders and the
//       analytics identity.
//
//  ── WHY THAT ORDER, AND WHY FAILURE IS NOT FAILURE ──────────────
//  It used to clear local data at step 4 of 5 and then delete the auth
//  user, so a throw on the last step wiped the player's history while
//  Settings told them "Your data is unchanged". Both halves were wrong:
//  their local data WAS changed, and their account was already being
//  deleted server-side because the request had been queued first.
//
//  The queue is the point of no return, and it is now the FIRST thing
//  that can fail. Before it lands, nothing has happened and a retry is
//  free. After it lands, deletion is inevitable: the Cloud Function
//  anonymises the leaderboard rows, deletes the setups and the profile,
//  and deletes the auth user — so this client failing at step 2 or 3
//  changes nothing about the outcome, only about who does the work.
//  Those steps are therefore best-effort by design, and the outcome
//  this returns says which of the two happened.
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

/// What actually happened, so the UI can stop guessing.
enum AccountDeletionOutcome: Equatable {
    /// The auth user was deleted from this device too. Nothing is
    /// outstanding beyond the backend's cleanup of leaderboard rows.
    case completed
    /// The request is queued and the backend will finish the job,
    /// including removing the auth user. The account is going away;
    /// this device just could not do the last step itself.
    case queued
}

@MainActor
protocol AccountDeleting {
    func deleteAccount() async throws -> AccountDeletionOutcome
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

    func deleteAccount() async throws -> AccountDeletionOutcome {
        guard let user = Auth.auth().currentUser else { throw DeletionError.notSignedIn }
        let uid = user.uid
        let db = Firestore.firestore()
        let requestRef = db.collection("deletionRequests").document(uid)

        // 1. Queue the request. THE ONLY STEP ALLOWED TO BE FATAL.
        //
        //    Checked-then-created rather than blindly written, because
        //    the rules are create-only (`allow update, delete: if
        //    false`). A setData over an existing request is an UPDATE
        //    and is denied — so a player retrying after a partial
        //    failure used to get a permission error and be told
        //    deletion had failed, when in fact their request was
        //    already queued and would be drained. Reading first turns
        //    that into what it is: already under way.
        let existing = try await requestRef.getDocument()
        if !existing.exists {
            try await requestRef.setData([
                "requestedAt": FieldValue.serverTimestamp()
            ])
        }

        // Record WHICH identity is dying, immediately and explicitly.
        //
        // Everything below is best-effort, including deleting the auth
        // user — so this device may still hold a valid keychain session
        // for an account the backend is erasing. FirebaseBootstrap reads
        // this key before anything else and refuses that uid. Saying so
        // outright replaced inferring it from a missing install marker,
        // which broke as soon as any other apex.* key survived deletion.
        defaults.set(uid, forKey: FirebaseBootstrap.pendingDeletionUIDKey)

        // Past this line the account is going away whatever happens
        // next, so nothing below is allowed to throw.

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

        // 3. Profile. The function deletes it too; doing it here just
        //    makes the common case instant.
        try? await db.collection("players").document(uid).delete()

        // 4. The auth user. Anonymous sessions are usually recent enough
        //    that this succeeds, but `requiresRecentLogin` is real and
        //    used to surface as a scary failure. It is not one: the
        //    function deletes the auth user as well.
        var outcome = AccountDeletionOutcome.completed
        do {
            try await user.delete()
            // The session is genuinely gone, so there is nothing left to
            // refuse. Left in place on failure, which is the whole point.
            defaults.removeObject(forKey: FirebaseBootstrap.pendingDeletionUIDKey)
        } catch {
            DebugLog.log("auth user delete deferred to the backend", error)
            outcome = .queued
        }

        // 5. Local state — records, streak, cached challenges, and the
        //    two things that would otherwise outlive the account: a week
        //    of scheduled reminders, and the analytics identity.
        //
        //    Last, and unconditional once the request is queued. Doing
        //    it earlier is what made the old error message a lie.
        clearLocalData()
        NotificationService.shared.cancelAll()
        Analytics.resetForDeletedAccount()

        return outcome
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

        // The install marker is deliberately LEFT ALONE now.
        //
        // It used to be cleared here, with a comment claiming that made
        // the next launch look like a fresh install and mint a new
        // identity. That stopped being true the moment the upgrade
        // detector arrived: clearing the marker is not enough, because
        // `apex.notifications.didRequestAuthorization` survives this
        // method and the detector counts it as prior use — so the next
        // launch read as an upgrade and restored the dying session.
        //
        // The rejected identity is now named outright in
        // FirebaseBootstrap.pendingDeletionUIDKey, set above. This app
        // has run on this device, and the marker should say so.
    }
}
