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
            draw(in: &context)
        }
    }

    // MARK: - Reading the setup

    /// 0 for the first option, 0.5 for the middle, 1 for the last —
    /// or nil when the category has not been decided yet.
    private func level(
        _ category: EngineeringCategoryID,
        _ low: EngineeringOptionID,
        _ mid: EngineeringOptionID,
        _ high: EngineeringOptionID
    ) -> Double? {
        guard let chosen = selections[category] else { return nil }
        switch chosen {
        case low:  return 0
        case high: return 1
        default:   return 0.5
        }
    }

    private var aero: Double? {
        level(.aerodynamics, .aeroLowDrag, .aeroBalanced, .aeroHighDownforce)
    }
    private var suspension: Double? {
        level(.suspension, .suspensionSoft, .suspensionBalanced, .suspensionStiff)
    }
    private var cooling: Double? {
        level(.cooling, .coolingLight, .coolingStandard, .coolingHeavy)
    }
    private var brakes: Double? {
        level(.brakes, .brakesConservative, .brakesBalanced, .brakesAggressive)
    }
    private var engine: Double? {
        level(.engineMode, .engineEfficient, .engineBalanced, .enginePower)
    }

    /// F1's own compound colours. nil until tyres are chosen.
    private var tyreColour: Color? {
        switch selections[.tires] {
        case .tiresHard:   return Theme.Color.cream
        case .tiresMedium: return Theme.Color.notice
        case .tiresSoft:   return Theme.Color.signal
        default:           return nil
        }
    }

    private var bodyFill: Color { Theme.Color.cream.opacity(0.92) }
    private var ghost: Color { Theme.Color.cream.opacity(0.16) }

    /// Filled once decided, a faint outline until then.
    private func paint(_ context: inout GraphicsContext, _ path: Path, decided: Bool, fill: Color) {
        if decided {
            context.fill(path, with: .color(fill))
        } else {
            context.stroke(path, with: .color(ghost),
                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext) {
        let midX = designWidth / 2

        // ── Wings. Span and chord both grow with downforce, because a
        // bigger wing is the one aerodynamic change anybody can see.
        let a = aero ?? 0.5
        let frontSpan = 30 + 16 * a
        let frontChord = 9 + 5 * a
        let rearSpan = 26 + 15 * a
        let rearChord = 10 + 5 * a

        let frontWing = Path(CGRect(x: midX - frontSpan, y: 2,
                                    width: frontSpan * 2, height: frontChord))
        paint(&context, frontWing, decided: aero != nil, fill: bodyFill)

        let rearWing = Path(CGRect(x: midX - rearSpan, y: designHeight - rearChord - 2,
                                   width: rearSpan * 2, height: rearChord))
        paint(&context, rearWing, decided: aero != nil, fill: bodyFill)

        // ── Stance. A stiff car is drawn tucked in, a soft one planted
        // wider. Ride height is invisible from above; track width is the
        // honest top-down proxy for how the car is set up to sit.
        let s = suspension ?? 0.5
        let track = 44 - 5 * s

        // ── Sidepods. Cooling is bought with bodywork, so heavy cooling
        // is a physically bigger car.
        let c = cooling ?? 0.5
        let podHalf = 15 + 9 * c
        let podLength = 52 + 12 * c
        let pods = Path(roundedRect: CGRect(x: midX - podHalf, y: 86,
                                            width: podHalf * 2, height: podLength),
                        cornerRadius: 5)
        paint(&context, pods, decided: cooling != nil, fill: Theme.Color.cream.opacity(0.82))

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
        let b = brakes ?? 0.5
        let ductLength = 8 + 7 * b
        for (y, height) in [(44.0, 38.0), (150.0, 42.0)] {
            for side in [-1.0, 1.0] {
                let x = midX + side * track - 8

                // Brake duct, inboard of the wheel.
                let duct = Path(roundedRect: CGRect(
                    x: midX + side * (track - 16) - 3, y: y + 10,
                    width: 6, height: ductLength), cornerRadius: 1.5)
                paint(&context, duct, decided: brakes != nil,
                      fill: Theme.Color.cream.opacity(0.55))

                // The tyre itself is always there; only its COMPOUND is
                // a decision, so it is drawn dark and banded in the
                // compound colour once chosen.
                let tyre = Path(roundedRect: CGRect(x: x, y: y, width: 16, height: height),
                                cornerRadius: 3)
                context.fill(tyre, with: .color(Theme.Color.ink.opacity(0.95)))
                context.stroke(tyre, with: .color(Theme.Color.cream.opacity(0.35)),
                               lineWidth: 1)

                if let tyreColour {
                    let band = Path(roundedRect: CGRect(x: x + 2.5, y: y + height * 0.28,
                                                        width: 11, height: 3.4),
                                    cornerRadius: 1.7)
                    context.fill(band, with: .color(tyreColour))
                }
            }
        }

        // ── Exhaust. The only sign of engine mode from above, and it
        // should look like heat rather than a part.
        if let engine {
            let glow = Path(ellipseIn: CGRect(x: midX - 7, y: designHeight - rearChord - 16,
                                              width: 14, height: 12))
            context.fill(glow, with: .color(Theme.Color.signal.opacity(0.25 + 0.55 * engine)))
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
                        .foregroundStyle(chosen == nil ? Theme.Color.faint : Theme.Color.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
