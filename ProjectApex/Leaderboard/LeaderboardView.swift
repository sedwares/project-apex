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
                    VStack(spacing: 4) {
                        headline(for: standing)
                        subline(for: standing)
                        if standing.tieCount > 1 {
                            Text("\(standing.tieCount) engineers share this exact time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            Section("Today's Top \(rows.isEmpty ? 50 : rows.count)") {
                if failed {
                    Label("Couldn't load the board — pull to retry.", systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if rows.isEmpty && !loaded {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if rows.isEmpty {
                    Label("Waiting for today's engineers…", systemImage: "person.3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack {
                            Text("#\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(row.displayName)
                                .fontWeight(row.isYou ? .bold : .regular)
                            if row.isYou {
                                Text("YOU")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                            Text(FixedPoint.formatLapTime(millis: row.averageLapTimeMillis))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Global Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("RANK #1")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
        } else if standing.totalEntries < 10 {
            Text("RANK #\(standing.rank) OF \(standing.totalEntries)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
        } else {
            Text("TOP \(standing.topPercent)% OF ENGINEERS")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
        }
    }

    @ViewBuilder
    private func subline(for standing: LeaderboardStanding) -> some View {
        if standing.totalEntries == 1 {
            Text("Only engineer today — you set the benchmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if standing.totalEntries < 10 {
            Text("Early field — percentiles arrive as more engineers join")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("Rank #\(standing.rank) of \(standing.totalEntries) engineers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
