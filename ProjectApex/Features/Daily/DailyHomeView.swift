//
//  DailyHomeView.swift
//  ProjectApex
//
//  Renders the DailyCoordinator's lifecycle: loading → brief, or the
//  unavailable / update states. Quick Race and Custom Test are always
//  offered — they work offline by design.
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
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Preparing today's assignment…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
            .navigationTitle("Project Apex")
            .navigationBarTitleDisplayMode(.inline)
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

    /// Scrolls: the brief already carries kicker, streak, spec card,
    /// section strip and briefing prose before the reveal card is
    /// added, which overflows a small phone. Spacers are gone —
    /// inside a ScrollView they collapse to nothing.
    private func briefContent(_ viewModel: DailyViewModel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(dayKicker(viewModel))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(1.5)
                    Text(circuitTitle(viewModel.challenge.circuit.name))
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                if viewModel.streak > 0 {
                    Label("\(viewModel.streak)-day streak", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                VStack(spacing: 12) {
                    briefRow(label: "Track type", value: viewModel.challenge.circuit.archetype.displayName)
                    HStack {
                        Text("Weather").foregroundStyle(.secondary)
                        Spacer()
                        Label(viewModel.challenge.weather.displayName,
                              systemImage: weatherEffects(viewModel.challenge.weather).symbol)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    Text(weatherEffects(viewModel.challenge.weather).effect)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    briefRow(label: "Sections", value: "\(viewModel.challenge.circuit.sections.count)")
                    briefRow(label: "Budget", value: "\(viewModel.budget) credits")

                    // The regulation belongs in the spec, not two taps
                    // deep in the Bay. It changes what you can build
                    // before you have built anything, and on a regulated
                    // day it is the most important line on this screen.
                    if let banned = viewModel.bannedOption {
                        let option = OptionLibrary.option(banned)
                        HStack(alignment: .firstTextBaseline) {
                            Text("Regulation").foregroundStyle(.secondary)
                            Spacer()
                            Label {
                                Text("No \(option.displayName) \(option.category.displayName)")
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.trailing)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)

                // Chief Engineer's pre-race briefing (deterministic, Core).
                sectionStrip(viewModel.challenge.circuit)

                Text(FeedbackEngine.preRaceBriefing(
                    archetype: viewModel.challenge.circuit.archetype,
                    weather: viewModel.challenge.weather,
                    regulation: viewModel.bannedOption
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                // The debrief's lock promises this; here it's delivered.
                if let reveal = coordinator.yesterdayReveal {
                    yesterdayRevealCard(reveal)
                }

                actionButtons(viewModel)
            }
        }
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
            VStack(spacing: 10) {
                ForEach(optimalRows(reveal)) { row in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(row.category)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(row.option)
                                                .fontWeight(.medium)
                                                .multilineTextAlignment(.trailing)
                                            // Grey, not red: a different pick isn't
                                            // necessarily a costly one — there's no
                                            // per-category time attribution to justify
                                            // calling it a mistake.
                                            if let yours = row.yours {
                                                Text("you: \(yours)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                    .multilineTextAlignment(.trailing)
                                            }
                                        }
                                    }
                                    .font(.subheadline)
                                }

                Divider().padding(.vertical, 4)

                HStack {
                    Text("Optimal average").foregroundStyle(.secondary)
                    Spacer()
                    Text(FixedPoint.formatLapTime(millis: reveal.optimalAverageLapMillis))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)

                HStack {
                    Text("Your gap").foregroundStyle(.secondary)
                    Spacer()
                    Text(gapText(reveal.gapMillis))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(reveal.gapMillis == 0 ? Color.green : Color.primary)
                }
                .font(.subheadline)
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Yesterday's optimal setup", systemImage: "lock.open")
                    .font(.subheadline.weight(.semibold))
                Text("Day \(reveal.dayNumber) — you beat \(reveal.beatPercent)% · \(reveal.matchedCount) of \(EngineeringCategoryID.allCases.count) systems matched")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    private func gapText(_ millis: Int) -> String {
        if millis == 0 { return "Perfect" }
        return "+\(millis / 1000).\(String(format: "%03d", millis % 1000))s"
    }

    // MARK: - Actions

    private func actionButtons(_ viewModel: DailyViewModel) -> some View {
        VStack(spacing: 10) {
            NavigationLink {
                EngineeringBayView(viewModel: viewModel)
            } label: {
                Text(viewModel.phase == .submitted ? "View Engineering Debrief" : "Begin Assignment")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            testSessionButtons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Status states

    private func statusContent(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if retry {
                Button("Try Again") {
                    Task { await coordinator.load() }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            testSessionButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private var testSessionButtons: some View {
        HStack(spacing: 10) {
            NavigationLink {
                TestSessionView(viewModel: .quickRace())
            } label: {
                Label("Quick Race", systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            NavigationLink {
                TestSessionView(viewModel: TestSessionViewModel(
                    conditions: .init(archetype: .balanced, weather: .sunny, budget: 100),
                    seed: UInt64(Date().timeIntervalSince1970)
                ))
            } label: {
                Label("Test Lab", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Presentation helpers

    private func dayKicker(_ viewModel: DailyViewModel) -> String {
        if let day = ChallengeSeed.dayNumber(fromDateKey: viewModel.challenge.dateKey) {
            return "TODAY'S ASSIGNMENT — DAY \(day)"
        }
        return "TODAY'S ASSIGNMENT"
    }

    /// Layout rhythm at a glance — abstract glyphs, not a map (v2 gets
    /// the real track art).
    private func sectionStrip(_ circuit: Circuit) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(circuit.sections.enumerated()), id: \.offset) { _, section in
                Image(systemName: glyph(for: section))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private func briefRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    DailyHomeView()
}
