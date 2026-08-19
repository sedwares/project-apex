//
//  LeaderboardView.swift
//  ProjectApex
//
//  Top 50 of the day, percentile-first header, your row highlighted.
//

import SwiftUI
import ProjectApexCore

struct LeaderboardView: View {
    let dateKey: String
    let uid: String?
    let standing: LeaderboardStanding?
    /// R3: injected — this view never constructs Firebase itself.
    let service: LeaderboardServicing

    @State private var rows: [LeaderboardRow] = []
    @State private var failed = false
    @State private var loaded = false

    var body: some View {
        List {
            if let standing {
                Section {
                    VStack(spacing: 6) {
                        headline(for: standing)
                        subline(for: standing)
                        if standing.tieCount > 1 {
                            Text("\(standing.tieCount) engineers share this exact time")
                                .font(Theme.Font.body(11, weight: .regular))
                                .foregroundStyle(Theme.Color.faint)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .listRowBackground(Theme.Color.panel)
                .listRowSeparator(.hidden)
            }

            Section {
                if failed {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                        Text("Couldn't load the board — pull to retry")
                    }
                    .apexLabel(Theme.Color.muted)
                } else if rows.isEmpty && !loaded {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.Color.signal)
                        Text("Loading").apexLabel(Theme.Color.muted)
                    }
                } else if rows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3")
                        Text("Waiting for today's engineers")
                    }
                    .apexLabel(Theme.Color.muted)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Text("#\(index + 1)")
                                .apexData(13, weight: .medium, color: Theme.Color.faint)
                                .frame(width: 40, alignment: .leading)
                            Text(row.displayName)
                                .font(Theme.Font.body(14, weight: row.isYou ? .bold : .regular))
                                .foregroundStyle(row.isYou ? Theme.Color.cream : Theme.Color.muted)
                            if row.isYou {
                                Text("You")
                                    .font(Theme.Font.label(9))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Theme.Color.ink)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.Color.signal)
                            }
                            Spacer(minLength: 8)
                            Text(FixedPoint.formatLapTime(millis: row.averageLapTimeMillis))
                                .apexData(14, weight: row.isYou ? .bold : .regular,
                                          color: row.isYou ? Theme.Color.cream : Theme.Color.muted)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Today's top \(rows.isEmpty ? 50 : rows.count)").apexLabel(Theme.Color.muted)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("Global Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadRows() }
        .refreshable { await loadRows() }
    }

    /// Small-field honesty (matches the debrief's standing card):
    /// a percentile is meaningless — even actively misleading, as with
    /// "Top 100%" for dead last of two — until the field is large
    /// enough for a percentile to mean anything.
    @ViewBuilder
    private func headline(for standing: LeaderboardStanding) -> some View {
        if standing.totalEntries == 1 {
            Text("Rank #1").apexDisplay(30)
        } else if standing.totalEntries < 10 {
            Text("Rank #\(standing.rank) of \(standing.totalEntries)").apexDisplay(30)
        } else {
            Text("Top \(standing.topPercent)% of engineers").apexDisplay(30)
        }
    }

    @ViewBuilder
    private func subline(for standing: LeaderboardStanding) -> some View {
        if standing.totalEntries == 1 {
            sublineText("Only engineer today — you set the benchmark")
        } else if standing.totalEntries < 10 {
            sublineText("Early field — percentiles arrive as more engineers join")
        } else {
            sublineText("Rank #\(standing.rank) of \(standing.totalEntries) engineers")
        }
    }

    private func sublineText(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.body(12.5, weight: .regular))
            .foregroundStyle(Theme.Color.muted)
            .multilineTextAlignment(.center)
    }

    private func loadRows() async {
        failed = false
        do {
            rows = try await service.topEntries(dateKey: dateKey, limit: 50, uid: uid ?? "")
            loaded = true
        } catch {
            DebugLog.log("leaderboard rows failed for \(dateKey)", error)
            failed = true
        }
    }
}
