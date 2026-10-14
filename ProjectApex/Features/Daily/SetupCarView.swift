//
//  SetupCarView.swift
//  ProjectApex
//
//  The car you are building, drawn from the eight choices.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  The Engineering Bay asks for eight decisions and then shows them
//  nowhere together. You scroll a list of twenty-four rows and have to
//  HOLD the other seven in your head while judging the eighth. The one
//  screen in the game that is explicitly about a whole car never showed
//  you one.
//
//  So the car assembles as you choose. Every part starts as a faint
//  outline and fills in when its category is decided, which makes the
//  bay read as construction rather than as a form.
//
//  ── WHAT MAPS, AND WHAT HONESTLY DOESN'T ───────────────────────────
//  Six of the eight have a real top-down analogue:
//
//    aerodynamics → front and rear wing span and chord
//    tires        → sidewall colour, in F1's own convention
//    cooling      → sidepod size, which is what cooling actually costs
//    brakes       → brake duct size at each wheel
//    suspension   → track width, the car's stance
//    engineMode   → exhaust glow
//
//  Gear ratio and reliability focus have none. Rather than invent a
//  shape for them — a picture that lies is worse than no picture — the
//  spec grid underneath names all eight, so nothing is hidden and the
//  drawing never has to pretend.
//
//  Tyre colour is not a house choice: hard/medium/soft is white, yellow
//  and red on every broadcast, so a player who watches already knows
//  what a red sidewall means before reading a word.
//

import SwiftUI
import ProjectApexCore

struct SetupCarView: View {
    let selections: [EngineeringCategoryID: EngineeringOptionID]
    /// Off for a second copy of the car on the same screen (the Bay's
    /// pinned mini car), so one pick never buzzes twice.
    var haptics: Bool = true

    // ── REACTING ───────────────────────────────────────────────────
    // The car used to redraw instantly: tap Low Drag and the wings were
    // simply a different size, with nothing to say a decision had just
    // landed. Now every pick (1) springs the shape to its new size, with
    // a little overshoot so it reads as a part being fitted, (2) flashes
    // the part that changed in signal red, and (3) ticks a haptic. The
    // Bay, the Lab and the Experiment all draw this view, so all three
    // get it; the Debrief shows a finished car and never changes, so it
    // stays still.

    @State private var flashed: EngineeringCategoryID?
    @State private var flashCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: flashCount) { pulse in
            CarCanvas(
                pose: CarPose(selections),
                tyreColour: Self.tyreColour(selections[.tires]),
                highlight: flashed,
                pulse: pulse
            )
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.58),
                       value: selections)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.06)
                CubicKeyframe(0.0, duration: 0.75)
            }
        }
        .onChange(of: selections) { old, new in
            guard let changed = Self.changedCategory(from: old, to: new) else { return }
            flashed = changed
            flashCount += 1
        }
        .sensoryFeedback(.selection, trigger: selections) { _, _ in haptics }
        .accessibilityHidden(true) // SetupSpecGrid beside it says the same in words
    }

    /// The single category a pick changed, or the first in display
    /// order when several moved at once (an Experiment preload).
    static func changedCategory(
        from old: [EngineeringCategoryID: EngineeringOptionID],
        to new: [EngineeringCategoryID: EngineeringOptionID]
    ) -> EngineeringCategoryID? {
        EngineeringCategoryID.allCases.first { old[$0] != new[$0] && new[$0] != nil }
    }

    /// F1's own compound colours. nil until tyres are chosen.
    static func tyreColour(_ chosen: EngineeringOptionID?) -> Color? {
        switch chosen {
        case .tiresHard:   return Theme.Color.cream
        case .tiresMedium: return Theme.Color.notice
        case .tiresSoft:   return Theme.Color.signal
        default:           return nil
        }
    }
}

// MARK: - The animatable shape of the car

/// Everything about the drawing that can move, as one vector SwiftUI
/// can interpolate. Levels are 0 / 0.5 / 1 for the three options;
/// "decided" lanes are 0 (dashed outline) or 1 (filled), so a part
/// fades in as it is fitted rather than popping.
struct CarPose: VectorArithmetic {
    var v = SIMD16<Double>()

    enum Lane: Int {
        case aero, suspension, cooling, brakes, engine
        case aeroOn, coolingOn, brakesOn, engineOn, tyresOn
    }

    subscript(_ lane: Lane) -> Double {
        get { v[lane.rawValue] }
        set { v[lane.rawValue] = newValue }
    }

    init() {}

    init(_ s: [EngineeringCategoryID: EngineeringOptionID]) {
        func level(_ c: EngineeringCategoryID, _ low: EngineeringOptionID, _ high: EngineeringOptionID) -> Double? {
            guard let chosen = s[c] else { return nil }
            return chosen == low ? 0 : (chosen == high ? 1 : 0.5)
        }
        let aero = level(.aerodynamics, .aeroLowDrag, .aeroHighDownforce)
        let susp = level(.suspension, .suspensionSoft, .suspensionStiff)
        let cool = level(.cooling, .coolingLight, .coolingHeavy)
        let brakes = level(.brakes, .brakesConservative, .brakesAggressive)
        let engine = level(.engineMode, .engineEfficient, .enginePower)

        self[.aero] = aero ?? 0.5
        self[.suspension] = susp ?? 0.5
        self[.cooling] = cool ?? 0.5
        self[.brakes] = brakes ?? 0.5
        self[.engine] = engine ?? 0
        self[.aeroOn] = aero == nil ? 0 : 1
        self[.coolingOn] = cool == nil ? 0 : 1
        self[.brakesOn] = brakes == nil ? 0 : 1
        self[.engineOn] = engine == nil ? 0 : 1
        self[.tyresOn] = s[.tires] == nil ? 0 : 1
    }

    static var zero: CarPose { CarPose() }
    static func + (a: CarPose, b: CarPose) -> CarPose { var r = CarPose(); r.v = a.v + b.v; return r }
    static func - (a: CarPose, b: CarPose) -> CarPose { var r = CarPose(); r.v = a.v - b.v; return r }
    mutating func scale(by rhs: Double) { v *= rhs }
    var magnitudeSquared: Double { (v * v).sum() }
}

/// The drawing itself. Animatable, so a spring on `pose` redraws every
/// frame of the transition instead of jumping to the end.
private struct CarCanvas: View, Animatable {
    var pose: CarPose
    let tyreColour: Color?
    let highlight: EngineeringCategoryID?
    let pulse: Double

    var animatableData: CarPose {
        get { pose }
        set { pose = newValue }
    }

    /// The car is drawn in this fixed space and scaled to whatever
    /// frame it is given, so proportions never depend on the device.
    private let designWidth: CGFloat = 132
    private let designHeight: CGFloat = 206

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / designWidth, size.height / designHeight)
            context.transform = CGAffineTransform(
                translationX: (size.width - designWidth * scale) / 2,
                y: (size.height - designHeight * scale) / 2
            ).scaledBy(x: scale, y: scale)
            draw(in: &context, scale: scale)
        }
    }

    private var bodyFill: Color { Theme.Color.cream.opacity(0.92) }
    private var ghost: Color { Theme.Color.cream.opacity(0.16) }

    /// Springs overshoot; a fill opacity must not.
    private func on(_ lane: CarPose.Lane) -> Double { min(1, max(0, pose[lane])) }

    /// Crossfades the dashed outline into the fill as the part is fitted.
    private func paint(_ context: inout GraphicsContext, _ path: Path, decided: Double, fill: Color) {
        if decided < 1 {
            context.stroke(path, with: .color(ghost.opacity(1 - decided)),
                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
        }
        if decided > 0 {
            context.fill(path, with: .color(fill.opacity(decided)))
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, scale: CGFloat) {
        let midX = designWidth / 2
        var parts: [EngineeringCategoryID: [Path]] = [:]

        // ── Wings. Span and chord both grow with downforce, because a
        // bigger wing is the one aerodynamic change anybody can see.
        let a = pose[.aero]
        let frontSpan = 30 + 16 * a
        let frontChord = 9 + 5 * a
        let rearSpan = 26 + 15 * a
        let rearChord = 10 + 5 * a

        let frontWing = Path(CGRect(x: midX - frontSpan, y: 2,
                                    width: frontSpan * 2, height: frontChord))
        let rearWing = Path(CGRect(x: midX - rearSpan, y: designHeight - rearChord - 2,
                                   width: rearSpan * 2, height: rearChord))
        paint(&context, frontWing, decided: on(.aeroOn), fill: bodyFill)
        paint(&context, rearWing, decided: on(.aeroOn), fill: bodyFill)
        parts[.aerodynamics] = [frontWing, rearWing]

        // ── Stance. A stiff car is drawn tucked in, a soft one planted
        // wider. Ride height is invisible from above; track width is the
        // honest top-down proxy for how the car is set up to sit.
        let track = 44 - 5 * pose[.suspension]

        // ── Sidepods. Cooling is bought with bodywork, so heavy cooling
        // is a physically bigger car.
        let c = pose[.cooling]
        let podHalf = 15 + 9 * c
        let podLength = 52 + 12 * c
        let pods = Path(roundedRect: CGRect(x: midX - podHalf, y: 86,
                                            width: podHalf * 2, height: podLength),
                        cornerRadius: 5)
        paint(&context, pods, decided: on(.coolingOn), fill: Theme.Color.cream.opacity(0.82))
        parts[.cooling] = [pods]

        // ── Chassis. Not a choice, so always solid: nose, tub, engine
        // cover. This is the part of the car you do not get to argue
        // with.
        var tub = Path()
        tub.move(to: CGPoint(x: midX - 5, y: 10))
        tub.addLine(to: CGPoint(x: midX + 5, y: 10))
        tub.addLine(to: CGPoint(x: midX + 10, y: 96))
        tub.addLine(to: CGPoint(x: midX + 9, y: 168))
        tub.addLine(to: CGPoint(x: midX - 9, y: 168))
        tub.addLine(to: CGPoint(x: midX - 10, y: 96))
        tub.closeSubpath()
        context.fill(tub, with: .color(bodyFill))

        // Cockpit opening, so the tub reads as a car and not a plank.
        let cockpit = Path(ellipseIn: CGRect(x: midX - 6, y: 74, width: 12, height: 22))
        context.fill(cockpit, with: .color(Theme.Color.ink))

        // Livery stripe — the same red centreline the replay car wears.
        let stripe = Path(CGRect(x: midX - 1.6, y: 12, width: 3.2, height: 154))
        context.fill(stripe, with: .color(Theme.Color.signal))

        // ── Wheels, tyres and brake ducts.
        let ductLength = 8 + 7 * pose[.brakes]
        var tyres: [Path] = []
        var ducts: [Path] = []
        for (y, height) in [(44.0, 38.0), (150.0, 42.0)] {
            for side in [-1.0, 1.0] {
                let x = midX + side * track - 8

                // Brake duct, inboard of the wheel.
                let duct = Path(roundedRect: CGRect(
                    x: midX + side * (track - 16) - 3, y: y + 10,
                    width: 6, height: ductLength), cornerRadius: 1.5)
                paint(&context, duct, decided: on(.brakesOn),
                      fill: Theme.Color.cream.opacity(0.55))
                ducts.append(duct)

                // The tyre itself is always there; only its COMPOUND is
                // a decision, so it is drawn dark and banded in the
                // compound colour once chosen.
                let tyre = Path(roundedRect: CGRect(x: x, y: y, width: 16, height: height),
                                cornerRadius: 3)
                context.fill(tyre, with: .color(Theme.Color.ink.opacity(0.95)))
                context.stroke(tyre, with: .color(Theme.Color.cream.opacity(0.35)),
                               lineWidth: 1)
                tyres.append(tyre)

                if let tyreColour {
                    let band = Path(roundedRect: CGRect(x: x + 2.5, y: y + height * 0.28,
                                                        width: 11, height: 3.4),
                                    cornerRadius: 1.7)
                    context.fill(band, with: .color(tyreColour.opacity(on(.tyresOn))))
                }
            }
        }
        parts[.brakes] = ducts
        parts[.tires] = tyres
        parts[.suspension] = tyres // stance is read through the wheels

        // ── Exhaust. The only sign of engine mode from above, and it
        // should look like heat rather than a part.
        let glow = Path(ellipseIn: CGRect(x: midX - 7, y: designHeight - rearChord - 16,
                                          width: 14, height: 12))
        let heat = on(.engineOn) * (0.25 + 0.55 * min(1, max(0, pose[.engine])))
        if heat > 0 {
            context.fill(glow, with: .color(Theme.Color.signal.opacity(heat)))
        }
        parts[.engineMode] = [glow]

        // ── The part just fitted flashes: a soft red bloom plus a crisp
        // edge, fading out over ~0.8s. Gear ratio and reliability have no
        // shape here, so their flash happens in the spec grid instead.
        // Line widths are in design units, so a car drawn small (the
        // Bay's pinned mini car is ~0.2x) would flash in hairlines. Hold
        // the flash to a readable on-screen width at any size.
        let k = max(1, 0.9 / scale)
        if let highlight, pulse > 0.01, let paths = parts[highlight] {
            for path in paths {
                context.stroke(path, with: .color(Theme.Color.signal.opacity(0.28 * pulse)),
                               lineWidth: 6 * k)
                context.stroke(path, with: .color(Theme.Color.signal.opacity(pulse)),
                               lineWidth: 1.6 * k)
            }
        }
    }
}

/// All eight choices at once, in four columns.
///
/// The drawing above covers six of them. This exists so the other two —
/// gear ratio and reliability focus, which have no shape from above —
/// are not quietly missing, and so the whole setup can be read without
/// scrolling twenty-four rows to remember what you picked.
struct SetupSpecGrid: View {
    let selections: [EngineeringCategoryID: EngineeringOptionID]

    private struct Slot: Identifiable {
        let id: EngineeringCategoryID
        let label: String
    }

    /// Visual categories first, in the order they appear on the car
    /// front to back; the two text-only ones last.
    private static let slots: [Slot] = [
        Slot(id: .aerodynamics,     label: "Aero"),
        Slot(id: .tires,            label: "Tires"),
        Slot(id: .suspension,       label: "Susp"),
        Slot(id: .brakes,           label: "Brakes"),
        Slot(id: .engineMode,       label: "Engine"),
        Slot(id: .cooling,          label: "Cooling"),
        Slot(id: .gearRatio,        label: "Gear"),
        Slot(id: .reliabilityFocus, label: "Reliab")
    ]

    /// The cell for the category just picked, lit red for a moment —
    /// the grid's half of the car's flash, and the ONLY flash gear ratio
    /// and reliability get, since they have no shape on the drawing.
    @State private var flashed: EngineeringCategoryID?

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 9
        ) {
            ForEach(Self.slots) { slot in
                let chosen = selections[slot.id]
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.label)
                        .font(Theme.Font.label(8.5))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Color.faint)
                    Text(chosen.map { OptionLibrary.option($0).displayName } ?? "—")
                        .font(Theme.Font.body(11, weight: .semibold))
                        .foregroundStyle(
                            flashed == slot.id ? Theme.Color.signal
                            : (chosen == nil ? Theme.Color.faint : Theme.Color.cream)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: selections) { old, new in
            guard let changed = SetupCarView.changedCategory(from: old, to: new) else { return }
            flashed = changed
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard flashed == changed else { return }
                withAnimation(.easeOut(duration: 0.4)) { flashed = nil }
            }
        }
    }
}
