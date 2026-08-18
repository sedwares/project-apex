//
//  CircuitLoop.swift
//  ProjectApex
//
//  The one true circuit curve. The SpriteKit replay track and the
//  home-screen circuit outline are both drawn from this type, so a
//  ghost on the home loop sits on exactly the geometry it traces in
//  the replay. Pure value type: no rendering, no state, no SpriteKit.
//

import CoreGraphics

struct CircuitLoop {

    /// SpriteKit's origin is bottom-left (y up); SwiftUI's is top-left
    /// (y down). Same maths in both would render the loop mirrored and
    /// send the ghost around the wrong way. Callers declare their axis.
    enum VerticalAxis {
        case up      // SpriteKit / RaceScene
        case down    // SwiftUI Path / home outline
    }

    /// The box the loop is inscribed in.
    let size: CGSize
    /// Margin between the loop's extremes and the box edge.
    let inset: CGFloat
    /// Superellipse exponent. 2 is a plain ellipse; higher flattens the
    /// sides toward straights. 4 reads as a race loop.
    let exponent: Double
    let axis: VerticalAxis

    init(size: CGSize,
         inset: CGFloat = 44,
         exponent: Double = 4,
         axis: VerticalAxis = .up) {
        self.size = size
        self.inset = inset
        self.exponent = exponent
        self.axis = axis
    }

    /// Point on the loop for `t` in 0...1. t = 0 is start/finish (the
    /// right-hand extreme) in both axis conventions, and increasing t
    /// travels the same visual direction in both.
    func point(at t: Double) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        let rx = size.width / 2 - inset
        let ry = size.height / 2 - inset

        let a = t * 2 * .pi
        let ca = cos(a), sa = sin(a)
        let ux = pow(abs(ca), 2.0 / exponent) * (ca < 0 ? -1 : 1)
        let uy = pow(abs(sa), 2.0 / exponent) * (sa < 0 ? -1 : 1)

        let y = axis == .up
            ? cy + CGFloat(uy) * ry
            : cy - CGFloat(uy) * ry

        return CGPoint(x: cx + CGFloat(ux) * rx, y: y)
    }

    /// Facing angle in radians at `t`, for orienting a car node.
    func heading(at t: Double, epsilon: Double = 0.001) -> CGFloat {
        let back = point(at: t - epsilon)
        let ahead = point(at: t + epsilon)
        return atan2(ahead.y - back.y, ahead.x - back.x)
    }

    /// The closed loop as a path, sampled into `steps` segments.
    func path(steps: Int = 240) -> CGPath {
        let path = CGMutablePath()
        for i in 0...steps {
            let pt = point(at: Double(i) / Double(steps))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
