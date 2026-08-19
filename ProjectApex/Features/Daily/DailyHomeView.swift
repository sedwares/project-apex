//
//  DailyHomeView.swift
//  ProjectApex
//
//  Renders the DailyCoordinator's lifecycle: loading → brief, or the
//  unavailable / update states. Quick Race and Custom Test are always
//  offered — they work offline by design.
//
//  Styled to the Livery direction (see Theme.swift). One structural
//  change came with the restyle: the day, the circuit and the conditions
//  moved into a single red header band, and the regulation became a
//  full-bleed strip directly beneath it rather than the last row of the
//  spec card. The regulation changes what you can build before you have
//  built anything — on a regulated day it is the most important line on
//  this screen, and as a spec row it read as a footnote.
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
                // Account deletion has to be findable, not buried in the
                // help text — guideline 5.1.1(v).
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
            // Reminders drift out of date whenever the app is opened on a
            // new day without submitting — rebuild from what's saved.
            let played = UserDefaultsSaveStore().loadRecord(forDateKey: todayKey) != nil
            await NotificationService.shared.refreshSchedule(hasPlayedToday: played)
        }
        // Separate task: the exhaustive solve for yesterday must never
        // delay today's brief appearing.
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

    /// Scrolls: the brief carries header, spec card, section strip and
    /// briefing prose before the reveal card is added, which overflows a
    /// small phone. No Spacers — inside a ScrollView they collapse to
    /// nothing.
    private func briefContent(_ viewModel: DailyViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(viewModel)

                if let banned = viewModel.bannedOption {
                    let option = OptionLibrary.option(banned)
                    Text("Regulation · no \(option.displayName) \(option.category.displayName)")
                        .apexNotice(Theme.Color.cream)
                }

                VStack(spacing: 22) {
                    if viewModel.streak > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                            Text("\(viewModel.streak)-day streak")
                        }
                        .apexLabel(Theme.Color.notice)
                    }

                    specCard(viewModel)

                    // Chief Engineer's pre-race briefing (deterministic, Core).
                    Text(FeedbackEngine.preRaceBriefing(
                        archetype: viewModel.challenge.circuit.archetype,
                        weather: viewModel.challenge.weather,
                        regulation: viewModel.bannedOption
                    ))
                    .font(Theme.Font.body(14, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                    // The debrief's lock promises this; here it's delivered.
                    if let reveal = coordinator.yesterdayReveal {
                        yesterdayRevealCard(reveal)
                    }

                    actionButtons(viewModel)
                }
                .padding(.top, 22)
            }
        }
    }

    private func header(_ viewModel: DailyViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayKicker(viewModel))
                .apexLabel(Theme.Color.cream.opacity(0.72))
            Text(circuitTitle(viewModel.challenge.circuit.name))
                .apexDisplay(31)
            HStack(spacing: 16) {
                metaItem(weatherEffects(viewModel.challenge.weather).symbol,
                         viewModel.challenge.weather.displayName)
                metaItem(nil, "\(viewModel.budget) cr")
                metaItem(nil, "\(viewModel.challenge.circuit.sections.count) sections")
            }
            .padding(.top, 3)
        }
        .apexHeaderBand()
    }

    private func metaItem(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .apexLabel(Theme.Color.cream.opacity(0.88))
    }

    /// Two rows, and neither repeats the header.
    ///
    /// The first version had "Track type: Balanced Circuit" directly
    /// under a title reading "Balanced Circuit", and "Budget: 96
    /// credits" under a header already showing "96 CR" — the circuit
    /// name is derived from the archetype, so those two lines could
    /// never disagree. Both are gone. The layout strip moved in here and
    /// got a label, which is the only thing that made it mean anything:
    /// as a row of loose glyphs floating between two cards it read as
    /// decoration.
    private func specCard(_ viewModel: DailyViewModel) -> some View {
        VStack(spacing: 0) {
            briefRow(label: "Conditions",
                     value: weatherEffects(viewModel.challenge.weather).effect)
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Layout").apexLabel()
                Spacer(minLength: 12)
                sectionStrip(viewModel.challenge.circuit)
            }
            .padding(.vertical, 12)
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
        /// The player's pick, only when it differed from optimal.
        /// nil = they matched, so there's nothing to compare.
        let yours: String?
    }

    /// Built outside the view builder deliberately: a wrong member name
    /// here produces a precise error on this line, rather than an
    /// inscrutable ForEach/Binding inference failure in the card body.
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

    /// Collapsed by default: yesterday's answer must never push today's
    /// call to action off the screen.
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
                            // Muted, not red: a different pick isn't
                            // necessarily a costly one — there's no
                            // per-category time attribution to justify
                            // calling it a mistake.
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
                .apexLabel(Theme.Color.signal)
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

    private func dayKicker(_ viewModel: DailyViewModel) -> String {
        if let day = ChallengeSeed.dayNumber(fromDateKey: viewModel.challenge.dateKey) {
            return "Today's assignment — day \(day)"
        }
        return "Today's assignment"
    }

    /// Layout rhythm at a glance — abstract glyphs, not a map (v2 gets
    /// the real track art).
    private func sectionStrip(_ circuit: Circuit) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(circuit.sections.enumerated()), id: \.offset) { _, section in
                Image(systemName: glyph(for: section))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.faint)
            }
        }
    }

    private func glyph(for section: TrackSectionType) -> String {
        switch section {
        case .longStraight, .shortStraight: return "arrow.right"
        case .finalStraight: return "flag.checkered"
        case .heavyBrakingZone: return "octagon"
        case .hairpin: return "arrow.uturn.down"
        case .slowCorner, .mediumCorner: return "arrow.turn.up.right"
        case .fastCorner: return "arrow.up.right"
        case .technicalSector: return "scribble"
        case .elevationClimb: return "arrow.up.forward"
        case .elevationDrop: return "arrow.down.forward"
        case .bumpySector: return "waveform.path"
        }
    }

    private func weatherEffects(_ weather: Weather) -> (symbol: String, effect: String) {
        switch weather {
        case .sunny: return ("sun.max", "Clean conditions — pure setup racing")
        case .hot: return ("thermometer.sun", "Cooling and tires taxed on the final lap")
        case .cold: return ("snowflake", "Slow warm-up, less grip early")
        case .rain: return ("cloud.rain", "Grip and braking cut — stability pays")
        case .windy: return ("wind", "Stability and aero efficiency taxed")
        }
    }

    /// The DAY kicker already shows the day; strip a trailing
    /// "— Day N" from the circuit name so it isn't shown twice.
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
