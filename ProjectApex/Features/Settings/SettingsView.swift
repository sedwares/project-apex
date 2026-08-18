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
    var deleter: AccountDeleting = AccountDeletionService()

    @Environment(\.dismiss) private var dismiss
    @AppStorage("apex.onboarding.seen") private var onboardingSeen = false

    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        List {
            Section("Your Engineer") {
                HStack {
                    Text("Callsign").foregroundStyle(.secondary)
                    Spacer()
                    Text(callsign ?? "—")
                        .fontWeight(.medium)
                        .monospaced()
                }
                .font(.subheadline)
                Text("Your callsign is generated from an anonymous ID. Project Apex never asks for your name, email, or contacts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Text("Project Apex asks permission for a daily reminder once you've completed three assignments — never before. You can change it any time in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
            }

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    if isDeleting {
                        HStack { ProgressView(); Text("Deleting…") }
                    } else {
                        Text("Delete my engineer")
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Data")
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
            }

            if let deletionError {
                Section {
                    Text(deletionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    private func delete() async {
        isDeleting = true
        deletionError = nil
        do {
            try await deleter.deleteAccount()
            // Back to a genuinely fresh start: the next launch signs in
            // anonymously as a NEW uid, so onboarding is honest again.
            onboardingSeen = false
            dismiss()
        } catch {
            deletionError = "Couldn't complete deletion: \(error.localizedDescription). Your data is unchanged — please try again."
        }
        isDeleting = false
    }
}
