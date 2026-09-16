//
//  SettingsView.swift
//  ProjectApex
//
//  Exists for one required reason and two useful ones.
//
//  REQUIRED: App Store guideline 5.1.1(v) — an account that can be
//  created in-app must be deletable in-app, and findably so. Anonymous
//  auth still creates a profile with a public callsign and public
//  leaderboard rows, so "we never asked for an email" is not a defence.
//  Burying the control in the help screen would satisfy the letter and
//  fail the spirit; a gear in the toolbar is where people look.
//
//  USEFUL: it's the only place to see your own callsign, and the only
//  honest place to explain what deletion does and doesn't remove.
//

import SwiftUI
import ProjectApexCore

struct SettingsView: View {
    let callsign: String?
    /// Called once deletion is committed, so the screen underneath can
    /// drop the deleted account instead of carrying its uid, callsign
    /// and today's result in memory for the rest of the session.
    var onDeleted: ((AccountDeletionOutcome) -> Void)?
    var deleter: AccountDeleting = AccountDeletionService()

    @Environment(\.dismiss) private var dismiss
    @AppStorage("apex.onboarding.seen") private var onboardingSeen = false

    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Callsign").apexLabel()
                    Spacer()
                    Text(callsign ?? "—").apexData(15, weight: .bold)
                }
                .padding(.vertical, 3)
                Text("Your callsign is generated from an anonymous ID. Project Apex never asks for your name, email, or contacts.")
                    .font(Theme.Font.body(11.5, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
            } header: {
                Text("Your engineer").apexLabel(Theme.Color.muted)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)

            Section {
                Text("Project Apex asks permission for a daily reminder once you've completed three assignments — never before. You can change it any time in iOS Settings.")
                    .font(Theme.Font.body(11.5, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("Open iOS Settings")
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .apexLabel(Theme.Color.cream)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Reminders").apexLabel(Theme.Color.muted)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)

            // REQUIRED. Apple wants a privacy policy reachable from
            // inside the app, not only from the store listing, for any
            // app that collects data — and this one creates a
            // persistent identifier, stores gameplay against it, and
            // reports crashes and usage. Settings had no mention of
            // privacy at all until build 23.
            //
            // The same page serves as the support URL in App Store
            // Connect: Apple rejects a bare mailto:, and the policy page
            // carries the contact address at the bottom.
            Section {
                Link(destination: AppLinks.privacyPolicy) {
                    HStack(spacing: 7) {
                        Text("Privacy policy")
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .apexLabel(Theme.Color.cream)
                }
                Text("What the app collects, what stays on your device, and what deleting your engineer does. Opens in your browser.")
                    .font(Theme.Font.body(11.5, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
            } header: {
                Text("Privacy").apexLabel(Theme.Color.muted)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    if isDeleting {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.Color.signal)
                            Text("Deleting").apexLabel(Theme.Color.muted)
                        }
                    } else {
                        // Signal red, and the ONLY red control in this
                        // screen. "Open iOS Settings" was red too, at the
                        // same size and weight — which made a harmless
                        // navigation link and the one irreversible action
                        // in the app visually identical. Red here has to
                        // mean "this deletes your account" and nothing
                        // else, so the other button went cream and gained
                        // a leaves-the-app glyph.
                        //
                        // Still the brand red rather than a separate
                        // "danger" colour: inventing one for a control
                        // that appears exactly once would add a hue to
                        // the palette to say something the isolation
                        // already says.
                        Text("Delete my engineer").apexLabel(Theme.Color.signal)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            } header: {
                Text("Data").apexLabel(Theme.Color.muted)
            } footer: {
                // Say exactly what survives. Claiming a completed
                // competition will be erased would be a lie — removing a
                // row silently re-ranks everyone who finished behind it.
                Text("""
                Deletes your profile, your saved setups, your streak and your local history, \
                and removes your account permanently.

                Past leaderboard results stay on the board as ENG-DELETED. They record a race \
                other people took part in, and deleting them would change everyone else's \
                position in it.
                """)
                .font(Theme.Font.body(11, weight: .regular))
                .foregroundStyle(Theme.Color.faint)
            }
            .listRowBackground(Theme.Color.panel)

            if let deletionError {
                Section {
                    Text(deletionError)
                        .font(Theme.Font.body(12, weight: .regular))
                        .foregroundStyle(Theme.Color.signal)
                }
                .listRowBackground(Theme.Color.panel)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog(
            "Delete your engineer?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Your streak and history are erased and you'll start again with a new callsign.")
        }
    }

    /// The failure message used to say "Your data is unchanged", which
    /// was false in every case it could actually fire: local records had
    /// already been wiped and the deletion request had already been
    /// queued, so the account was on its way out while the player was
    /// being told nothing had happened.
    ///
    /// The service now only throws BEFORE anything is committed, so the
    /// message is true again — and the two success shapes are told
    /// apart, because "queued" is a real outcome a player deserves to
    /// know about rather than a hidden partial failure.
    private func delete() async {
        isDeleting = true
        deletionError = nil
        do {
            let outcome = try await deleter.deleteAccount()
            // Back to a genuinely fresh start: the next launch signs in
            // anonymously as a NEW uid, so onboarding is honest again.
            onboardingSeen = false
            onDeleted?(outcome)
            dismiss()
        } catch {
            deletionError = "Couldn't start deletion: \(error.localizedDescription). "
                + "Nothing has been deleted — please try again."
        }
        isDeleting = false
    }
}
