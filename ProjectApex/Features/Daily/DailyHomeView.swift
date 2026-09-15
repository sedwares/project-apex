//
//  DailyHomeView.swift
//  ProjectApex
//
//  F1 BROADCAST RESTYLE (pass 7):
//  The header is now a timing-tower panel: Carbon Black ground, 4px red
//  left-edge stripe, large day number in the F1 broadcast style, a
//  conditions spec grid, and circuit section bars that replace the icon
//  strip. The streak gets a championship-points card (gold left stripe,
//  large number). Primary CTA is now signal red. The regulation strip
//  runs full red — it is the most important constraint on the screen.
//
//  All business logic and navigation are unchanged from pass 6.
//

import SwiftUI
import ProjectApexCore

struct DailyHomeView: View {
    @State private var coordinator = DailyCoordinator()
    @AppStorage("apex.onboarding.seen") private var onboardingSeen = false

    var body: some View {
        NavigationStack {
            Group {
                switch coordinator.state {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView().tint(Theme.Color.signal)
                        Text("Preparing today's assignment")
                            .apexLabel(Theme.Color.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready(let viewModel):
                    briefContent(viewModel)
                case .unavailable(let message):
                    statusContent(
                        icon: "wifi.exclamationmark",
                        title: "Paddock unreachable",
                        message: message,
                        retry: true
                    )
                case .updateRequired:
                    statusContent(
                        icon: "arrow.down.app",
                        title: "Update required",
                        message: "Today's challenge uses a newer simulation. Update Project Apex to compete.",
                        retry: false
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.ink)
            .navigationTitle("Project Apex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Color.ink, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HowToPlayView()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(callsign: coordinator.displayName)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .task { await coordinator.load() }
        .task {
            let todayKey = DailyCoordinator.todayDateKey()
            Analytics.trackOpen(todayDayNumber: ChallengeSeed.dayNumber(fromDateKey: todayKey))
            let played = UserDefaultsSaveStore().loadRecord(forDateKey: todayKey) != nil
            await NotificationService.shared.refreshSchedule(hasPlayedToday: played)
        }
        .task { await coordinator.loadYesterdayReveal() }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingSeen },
            set: { _ in }
        )) {
            OnboardingView {
                onboardingSeen = true
                Analytics.onboardingCompleted()
            }
        }
    }

    // MARK: - Brief (challenge ready)

    private func briefContent(_ viewModel: DailyViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(viewModel)

                // Regulation: red strip — it changes what you can build,
                // so it must be the first thing read after the header.
                if let banned = viewModel.bannedOption {
                    let option = OptionLibrary.option(banned)
                    Text("Regulation · no \(option.displayName) \(option.category.displayName)")
                        .apexNotice(Theme.Color.signal)
                }

                VStack(spacing: 14) {
                    // Streak: championship-points card, gold left stripe.
                    if viewModel.streak > 0 {
                        streakCard(viewModel.streak)
                    }

                    // Conditions card.
                    specCard(viewModel)

                    // Chief Engineer's pre-race briefing.
                    Text(FeedbackEngine.preRaceBriefing(
                        archetype: viewModel.challenge.circuit.archetype,
                        weather: viewModel.challenge.weather,
                        regulation: viewModel.bannedOption
                    ))
                    .font(Theme.Font.body(14, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                    if let reveal = coordinator.yesterdayReveal {
                        yesterdayRevealCard(reveal)
                    }

                    actionButtons(viewModel)
                }
                .padding(.top, 18)
            }
        }
    }

    // MARK: - F1 Timing Tower Header

    private func header(_ viewModel: DailyViewModel) -> some View {
        HStack(spacing: 0) {
            // 4px red left stripe — timing tower signature.
            Rectangle()
                .fill(Theme.Color.signal)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                // ── Top badge row
                HStack(alignment: .center) {
                    Text("Project Apex")
                        .apexLabel(Theme.Color.cream.opacity(0.42))
                    Spacer()
                    sessionBadge
                }
                .padding(.top, 12)
                .padding(.trailing, 16)

                // ── Day number + circuit name
                HStack(alignment: .bottom, spacing: 12) {
                    if let day = ChallengeSeed.dayNumber(fromDateKey: viewModel.challenge.dateKey) {
                        Text("\(day)")
                            .font(.system(size: 72, weight: .black).width(.condensed))
                            .tracking(-2)
                            .foregroundStyle(Theme.Color.cream)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Race Day")
                            .font(Theme.Font.label(10))
                            .tracking(2.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Color.signal)
                        Text(circuitTitle(viewModel.challenge.circuit.name))
                            .font(.system(size: 20, weight: .heavy).width(.condensed))
                            .foregroundStyle(Theme.Color.cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.bottom, 4)
                }
                .padding(.top, 4)
                .padding(.trailing, 16)

                // ── Conditions spec grid
                HStack(spacing: 0) {
                    gridCell(label: "Weather", value: viewModel.challenge.weather.displayName)
                    Rectangle().fill(Theme.Color.rule).frame(width: 1)
                    gridCell(label: "Budget", value: "\(viewModel.budget) CR")
                    Rectangle().fill(Theme.Color.rule).frame(width: 1)
                    gridCell(label: "Sections", value: "\(viewModel.challenge.circuit.sections.count)")
                }
                .overlay(
                    Rectangle().stroke(Theme.Color.rule, lineWidth: 1)
                )
                .padding(.top, 10)
                .padding(.trailing, 16)

                // ── Circuit profile strip, and what it says in words
                VStack(alignment: .leading, spacing: 6) {
                    CircuitSectionBars(
                        sections: viewModel.challenge.circuit.sections,
                        height: 4
                    )
                    Text(viewModel.challenge.circuit.compositionSummary())
                        .font(Theme.Font.body(11, weight: .medium))
                        .foregroundStyle(Theme.Color.muted)
                }
                .padding(.vertical, 10)
                .padding(.trailing, 16)
            }
            .padding(.leading, 12)
        }
        .background(Theme.Color.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    private var sessionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.Color.gain)
                .frame(width: 5, height: 5)
            Text("Session Open")
                .font(Theme.Font.label(8))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Color.gain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.Color.gain.opacity(0.10))
        .overlay(Rectangle().stroke(Theme.Color.gain.opacity(0.30), lineWidth: 1))
    }

    private func gridCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).apexLabel()
            Text(value)
                .font(.system(size: 14, weight: .heavy).width(.condensed))
                .textCase(.uppercase)
                .foregroundStyle(Theme.Color.cream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Streak card

    private func streakCard(_ streak: Int) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Color.notice)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Streak").apexLabel()
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(streak)")
                        .font(.system(size: 44, weight: .black).width(.condensed))
                        .foregroundStyle(Theme.Color.notice)
                    Text(streak == 1 ? "day" : "days")
                        .apexLabel(Theme.Color.muted)
                }
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Color.panel)
        .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Conditions card

    /// Conditions effect only — layout strip moved into the header.
    private func specCard(_ viewModel: DailyViewModel) -> some View {
        VStack(spacing: 0) {
            briefRow(label: "Conditions",
                     value: weatherEffects(viewModel.challenge.weather).effect)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .apexCard()
        .padding(.horizontal, 20)
    }

    private func briefRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).apexLabel()
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.Font.body(13.5))
                .foregroundStyle(Theme.Color.cream)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Yesterday's reveal

    private struct OptimalRow: Identifiable {
        let id: EngineeringCategoryID
        let category: String
        let option: String
        let yours: String?
    }

    private func optimalRows(_ reveal: DailyCoordinator.YesterdayReveal) -> [OptimalRow] {
        EngineeringCategoryID.allCases.compactMap { category -> OptimalRow? in
            guard let optionID = reveal.optimalSelections[category] else { return nil }
            let yourID = reveal.yourSelections[category]
            let differed = yourID != nil && yourID != optionID
            return OptimalRow(
                id: category,
                category: category.displayName,
                option: OptionLibrary.option(optionID).displayName,
                yours: differed ? OptionLibrary.option(yourID!).displayName : nil
            )
        }
    }

    private func yesterdayRevealCard(_ reveal: DailyCoordinator.YesterdayReveal) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(optimalRows(reveal)) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.category).apexLabel()
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.option)
                                .font(Theme.Font.body(13))
                                .foregroundStyle(Theme.Color.cream)
                                .multilineTextAlignment(.trailing)
                            if let yours = row.yours {
                                Text("you: \(yours)")
                                    .font(Theme.Font.body(11, weight: .regular))
                                    .foregroundStyle(Theme.Color.faint)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Rectangle().fill(Theme.Color.rule).frame(height: 1).padding(.vertical, 6)

                HStack {
                    Text("Optimal average").apexLabel()
                    Spacer()
                    Text(FixedPoint.formatLapTime(millis: reveal.optimalAverageLapMillis))
                        .apexData(13)
                }
                .padding(.vertical, 5)

                HStack {
                    Text("Your gap").apexLabel()
                    Spacer()
                    Text(gapText(reveal.gapMillis))
                        .apexData(13, color: reveal.gapMillis == 0
                            ? Theme.Color.gain : Theme.Color.cream)
                }
                .padding(.vertical, 5)
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open")
                    Text("Yesterday's optimal setup")
                }
                .apexLabel(Theme.Color.session)  // Purple: session record treatment
                Text("Day \(reveal.dayNumber) — you beat \(reveal.beatPercent)% · \(reveal.matchedCount) of \(EngineeringCategoryID.allCases.count) systems matched")
                    .font(Theme.Font.body(12, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
            }
        }
        .tint(Theme.Color.cream)
        .padding(16)
        .apexCard()
        .padding(.horizontal, 20)
    }

    private func gapText(_ millis: Int) -> String {
        if millis == 0 { return "Perfect" }
        return "+\(millis / 1000).\(String(format: "%03d", millis % 1000))s"
    }

    // MARK: - Actions

    private func actionButtons(_ viewModel: DailyViewModel) -> some View {
        VStack(spacing: 12) {
            NavigationLink {
                EngineeringBayView(viewModel: viewModel)
            } label: {
                Text(viewModel.phase == .submitted ? "View debrief" : "Begin assignment")
                    .apexPrimaryButton()
            }
            .buttonStyle(.plain)

            testSessionButtons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Status states

    private func statusContent(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(Theme.Color.signal)
            Text(title).apexDisplay(24)
            Text(message)
                .font(Theme.Font.body(14, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if retry {
                Button {
                    Task { await coordinator.load() }
                } label: {
                    Text("Try again").apexPrimaryButton()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 60)
                .padding(.top, 4)
            }
            Spacer()
            testSessionButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }

    private var testSessionButtons: some View {
        HStack(spacing: 10) {
            NavigationLink {
                TestSessionView(viewModel: .quickRace())
            } label: {
                Text("Quick Race").apexSecondaryButton()
            }
            .buttonStyle(.plain)

            NavigationLink {
                TestSessionView(viewModel: TestSessionViewModel(
                    conditions: .init(archetype: .balanced, weather: .sunny, budget: 100),
                    seed: UInt64(Date().timeIntervalSince1970)
                ))
            } label: {
                Text("Test Lab").apexSecondaryButton()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Presentation helpers

    private func weatherEffects(_ weather: Weather) -> (symbol: String, effect: String) {
        switch weather {
        case .sunny: return ("sun.max", "Clean conditions — pure setup racing")
        case .hot: return ("thermometer.sun", "Cooling and tires taxed on the final lap")
        case .cold: return ("snowflake", "Slow warm-up, less grip early")
        case .rain: return ("cloud.rain", "Grip and braking cut — stability pays")
        case .windy: return ("wind", "Stability and aero efficiency taxed")
        }
    }

    private func circuitTitle(_ name: String) -> String {
        if let range = name.range(of: " — Day ") {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}

#Preview {
    DailyHomeView()
        .preferredColorScheme(.dark)
}
