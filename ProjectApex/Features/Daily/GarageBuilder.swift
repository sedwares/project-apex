//
//  GarageBuilder.swift
//  ProjectApex
//
//  The garage: the car on its stage, what decides today, the board of
//  eight systems, three option cards and the pit wall's line.
//
//  ── WHY IT IS SHARED ───────────────────────────────────────────────
//  The Daily bay, Quick Race and the Test Lab all build a car from the
//  same twenty-four options. They used to draw three versions of a list;
//  the garage replaced the bay's, and the lab deserved the same screen.
//  One view, so a fix in one place reaches all of them. Everything that
//  legitimately differs — whether the setup is locked, what is banned,
//  what a pick costs relative to the current one — is a parameter.
//
//  Layout notes and the reasoning behind each piece live with the code
//  below (moved here from EngineeringBayView).
//

import SwiftUI
import ProjectApexCore

struct GarageBuilder: View {
    let selections: [EngineeringCategoryID: EngineeringOptionID]
    let circuit: Circuit
    let weather: Weather
    let budget: Int
    var banned: EngineeringOptionID? = nil
    /// The setup name once all eight are chosen.
    var identityText: String? = nil
    /// False once the setup is locked (a submitted Daily).
    var isEnabled: Bool = true
    /// Cost change if this option replaced the current pick.
    let costDelta: (EngineeringOption) -> Int?
    let onSelect: (EngineeringOptionID) -> Void
    /// The setup actually raced (the Experiment): those cards are marked
    /// RACED, so a sandbox full of changes still shows the departure point.
    var raced: [EngineeringCategoryID: EngineeringOptionID]? = nil

    /// The option just picked, for the pit wall's remark.
    @State private var lastPicked: EngineeringOptionID?
    /// The system whose three options are on screen.
    @State private var activeCategory: EngineeringCategoryID = .engineMode
    /// So the option cards slide the right way between systems.
    @State private var slideForward = true
    /// 3D garage car vs the top-down drawing; one switch for every screen.
    @AppStorage("apex.bay.car3D") private var car3D = true

    private func isBanned(_ id: EngineeringOptionID) -> Bool { id == banned }

    private var demandAxes: [VehicleProfile.Axis] {
        let setup = PlayerSetup(challengeId: "garage", selectedOptions: selections)
        return VehicleProfile.from(setup: setup, circuit: circuit).axes
    }

    var body: some View {
        VStack(spacing: 11) {
            carStage
            demandPanel
            systemGrid
            systemHeading
            optionCards
            pitWallArea
        }
        .onAppear {
            if let open = Self.order.first(where: { selections[$0] == nil }) {
                activeCategory = open
            }
        }
        .onChange(of: selections) { old, new in
            guard isEnabled,
                  let category = SetupCarView.changedCategory(from: old, to: new) else { return }
            lastPicked = new[category]
        }
    }

    // MARK: - Garage pieces

    /// Systems in the order the tabs show them — the library's own
    /// display order, so the tabs read the same as everywhere else.
    static let order: [EngineeringCategoryID] = OptionLibrary.categories.map(\.id)

    /// The car on a lit stage. It never scrolls out of a normal-height
    /// screen while you work the cards below it.
    private var carStage: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(
                colors: [Theme.Color.signal.opacity(0.13), .clear],
                center: .center, startRadius: 4, endRadius: 170
            )
            Group {
                if car3D {
                    SetupCar3DView(selections: selections)
                        .frame(height: 168)
                        // The 2D car carries the pick haptic; the 3D one
                        // needs its own.
                        .sensoryFeedback(.selection, trigger: selections)
                        .accessibilityHidden(true)
                } else {
                    SetupCarView(selections: selections)
                        .frame(height: 160)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            HStack(alignment: .firstTextBaseline) {
                if let identity = identityText {
                    Text(identity)
                        .apexDisplay(14)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Your car").apexLabel(Theme.Color.muted)
                }
                Spacer(minLength: 8)
                Text("\(selections.count)/8 fitted")
                    .apexData(10.5, weight: .medium, color: Theme.Color.muted)
                Button {
                    car3D.toggle()
                } label: {
                    Text(car3D ? "2D" : "3D")
                        .font(Theme.Font.label(9))
                        .tracking(1.0)
                        .foregroundStyle(Theme.Color.cream)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(car3D ? "Show top-down car" : "Show 3D car")
            }
            .padding(10)
        }
        .background(Theme.Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
    }

    /// The four stats that decide today, two by two. About the TRACK,
    /// not the car — the bar is your car, the percentage is the circuit.
    private var demandPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What decides today").apexLabel(Theme.Color.muted)
                Spacer()
                Text("% of this lap").apexLabel(Theme.Color.faint)
            }
            // One row of four: about a third of the height the 2×2 took.
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(demandAxes.enumerated()), id: \.element.name) { rank, axis in
                    DemandAxisRow(axis: axis, rank: rank, barHeight: 3, compact: true, stacked: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// All eight systems at once, as a 4×2 board. A scrolling row of
    /// look-alike tabs showed four at a time and never said there were
    /// eight — players couldn't tell how much car was left to build.
    /// Each system gets its own icon; state reads at a glance:
    /// red outline = on screen, green tick = fitted, dashed = still open.
    private var systemGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 6
        ) {
            ForEach(Self.order, id: \.self) { id in
                systemTile(id)
            }
        }
    }

    private func systemTile(_ id: EngineeringCategoryID) -> some View {
        let isActive = id == activeCategory
        let chosen = selections[id]
        let shape = RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)

        return Button {
            show(id)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: Self.icon(id))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 18)
                    .foregroundStyle(isActive ? Theme.Color.signal
                                     : (chosen == nil ? Theme.Color.faint : Theme.Color.cream))
                Text(Self.shortName(id))
                    .font(Theme.Font.label(8.5))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(isActive ? Theme.Color.cream : Theme.Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(chosen.map { OptionLibrary.option($0).displayName } ?? "Open")
                    .font(Theme.Font.body(10, weight: .semibold))
                    .foregroundStyle(chosen == nil ? Theme.Color.faint : Theme.Color.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .background(isActive ? Theme.Color.signal.opacity(0.12) : Theme.Color.panel)
            .overlay {
                if isActive {
                    shape.stroke(Theme.Color.signal, lineWidth: 2)
                } else if chosen == nil {
                    shape.stroke(Theme.Color.cream.opacity(0.22),
                                 style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    shape.stroke(Theme.Color.rule, lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if chosen != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Color.gain)
                        .padding(3)
                }
            }
            .clipShape(shape)
            .animation(.snappy(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(id.displayName), \(chosen.map { OptionLibrary.option($0).displayName } ?? "not chosen")")
        .accessibilityAddTraits(Self.traits(selected: isActive))
    }

    /// "System 3 of 8 · Brakes", with arrows to step through — says in
    /// words what the board above says in shape.
    private var systemHeading: some View {
        let index = (Self.order.firstIndex(of: activeCategory) ?? 0) + 1
        return HStack(spacing: 10) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 28)
            }
            .disabled(index == 1)
            .accessibilityLabel("Previous system")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index) of \(Self.order.count)").apexLabel(Theme.Color.muted)
                Text(activeCategory.displayName).apexDisplay(17)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("System \(index) of \(Self.order.count), \(activeCategory.displayName)")

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 28)
            }
            .disabled(index == Self.order.count)
            .accessibilityLabel("Next system")
        }
        .foregroundStyle(Theme.Color.cream)
        .buttonStyle(.plain)
    }

    /// The three options for the system on screen.
    private var optionCards: some View {
        let category = OptionLibrary.categories.first { $0.id == activeCategory }
            ?? OptionLibrary.categories[0]
        return HStack(spacing: 8) {
            ForEach(category.options) { option in
                optionCard(option)
            }
        }
        .id(activeCategory)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(x: slideForward ? 28 : -28)),
            removal: .opacity
        ))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50, abs(dx) > abs(value.translation.height) else { return }
                step(dx < 0 ? 1 : -1)
            }
        )
    }

    private func optionCard(_ option: EngineeringOption) -> some View {
        let isSelected = selections[option.category] == option.id
        let isBanned = isBanned(option.id)
        let delta = costDelta(option)
        let enabled = isEnabled && !isBanned

        return Button {
            pick(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(option.displayName)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(isBanned ? Theme.Color.faint
                                     : (isSelected ? Theme.Color.cream : Theme.Color.cream.opacity(0.78)))
                    .strikethrough(isBanned)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if isBanned {
                    Text("Not permitted at this event")
                        .font(Theme.Font.body(10, weight: .regular))
                        .foregroundStyle(Theme.Color.faint)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if let up = option.topUpside {
                            Text(up).foregroundStyle(Theme.Color.gain)
                        }
                        if let down = option.topDownside {
                            Text(down).foregroundStyle(Theme.Color.muted)
                        }
                    }
                    .font(Theme.Font.body(10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(option.cost) cr")
                        .apexData(13, color: isSelected ? Theme.Color.cream : Theme.Color.muted)
                    Spacer(minLength: 0)
                    if !isBanned, !isSelected, let delta {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .apexData(10.5, color: delta > 0 ? Theme.Color.notice : Theme.Color.gain)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if raced?[option.category] == option.id {
                    Text("Raced")
                        .font(Theme.Font.label(7.5))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Color.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: 1))
                        .padding(6)
                }
            }
            .background(isSelected ? Theme.Color.signal.opacity(0.14) : Theme.Color.panel)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                    .stroke(isSelected ? Theme.Color.signal : Theme.Color.rule,
                            lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous))
            .animation(.snappy(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibility(option, isBanned: isBanned))
        .accessibilityAddTraits(Self.traits(selected: isSelected))
    }

    private func cardAccessibility(_ option: EngineeringOption, isBanned: Bool) -> String {
        var parts = [option.displayName]
        if raced?[option.category] == option.id { parts.append("the option you raced") }
        if isBanned { parts.append("not permitted at this event") }
        else {
            if let up = option.topUpside { parts.append(up) }
            if let down = option.topDownside { parts.append(down) }
            parts.append("\(option.cost) credits")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var pitWallArea: some View {
        if let remark = pitWallRemark {
            pitWallLine(remark)
        } else if !isEnabled {
            Text("Setup locked. This is the car you raced.")
                .font(Theme.Font.body(12, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Eight systems, one budget. Pick an option and the car takes shape.")
                .font(Theme.Font.body(12, weight: .regular))
                .foregroundStyle(Theme.Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Garage actions

    /// Fit the part. If it filled an empty system, move on to the next
    /// open one after a beat — long enough to watch the car change.
    private func pick(_ option: EngineeringOption) {
        let wasOpen = selections[option.category] == nil
        onSelect(option.id)
        guard wasOpen, isEnabled,
              let next = nextOpen(after: option.category) else { return }
        let from = activeCategory
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            // The player may already have moved on by hand.
            guard activeCategory == from else { return }
            show(next)
        }
    }

    private func show(_ id: EngineeringCategoryID) {
        guard id != activeCategory else { return }
        let a = Self.order.firstIndex(of: activeCategory) ?? 0
        let b = Self.order.firstIndex(of: id) ?? 0
        slideForward = b > a
        withAnimation(.snappy(duration: 0.28)) { activeCategory = id }
    }

    private func step(_ by: Int) {
        guard let i = Self.order.firstIndex(of: activeCategory) else { return }
        let j = i + by
        guard Self.order.indices.contains(j) else { return }
        show(Self.order[j])
    }

    /// The next system with nothing fitted, wrapping round; nil when
    /// the car is complete.
    private func nextOpen(after id: EngineeringCategoryID) -> EngineeringCategoryID? {
        guard let i = Self.order.firstIndex(of: id) else { return nil }
        let n = Self.order.count
        for k in 1..<n {
            let candidate = Self.order[(i + k) % n]
            if selections[candidate] == nil { return candidate }
        }
        return nil
    }

    /// Explicitly typed: a bare ternary of two option-set literals does
    /// not always infer (see EngineeringOptionRow).
    static func traits(selected: Bool) -> AccessibilityTraits {
        selected ? [.isButton, .isSelected] : [.isButton]
    }

    /// One icon per system, so the eight tiles stop looking alike.
    static func icon(_ id: EngineeringCategoryID) -> String {
        switch id {
        case .engineMode: return "engine.combustion"
        case .tires: return "tirepressure"
        case .aerodynamics: return "wind"
        case .suspension: return "arrow.up.and.down"
        case .gearRatio: return "gearshape.2"
        case .cooling: return "snowflake"
        case .brakes: return "exclamationmark.brakesignal"
        case .reliabilityFocus: return "wrench.and.screwdriver"
        }
    }

    static func shortName(_ id: EngineeringCategoryID) -> String {
        switch id {
        case .engineMode: return "Engine"
        case .tires: return "Tires"
        case .aerodynamics: return "Aero"
        case .suspension: return "Susp."
        case .gearRatio: return "Gearing"
        case .cooling: return "Cooling"
        case .brakes: return "Brakes"
        case .reliabilityFocus: return "Reliab."
        }
    }

    // MARK: - Pit wall

    /// Built only from what is already on screen — demand shares,
    /// weather, budget, the option's own captions. See PitWallRemark:
    /// it never consults the solver, so it can never leak the answer.
    private var pitWallRemark: String? {
        guard isEnabled, let lastPicked else { return nil }
        return PitWallRemark.after(
            picking: lastPicked,
            selections: selections,
            circuit: circuit,
            weather: weather,
            budget: budget,
            banned: banned
        )
    }

    private func pitWallLine(_ remark: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Theme.Color.signal)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pit wall").apexLabel(Theme.Color.signal)
                Text(remark)
                    .font(Theme.Font.body(12.5, weight: .medium))
                    .foregroundStyle(Theme.Color.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(remark)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.22), value: remark)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onChange(of: remark) { _, new in
            AccessibilityNotification.Announcement(new).post()
        }
    }

}
