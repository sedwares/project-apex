//
//  SetupCar3DView.swift
//  ProjectApex
//
//  The car you are building, in 3D, on a slowly turning garage floor.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  The top-down drawing proved the idea — the car takes shape as you
//  choose — but it is flat, and players asked for the bay to feel like
//  a garage. This is the same car, the same mapping from choices to
//  parts, built from primitives in SceneKit so every part can still
//  change size when you pick. No model file: nothing to license, and a
//  generic open-wheel car (no real team, no real livery) keeps the
//  "no third-party content" declaration true.
//
//  ── WHAT MAPS ──────────────────────────────────────────────────────
//  Same as SetupCarView, so the two can be compared honestly:
//    aerodynamics → front/rear wing span and chord
//    tires        → compound band colour (white / yellow / red)
//    cooling      → sidepod size
//    brakes       → brake duct size
//    suspension   → track width
//    engineMode   → exhaust glow
//  Gear ratio and reliability have no shape; the system board names them.
//
//  Undecided parts are drawn as wireframe — the 3D version of the
//  drawing's dashed outline — and become solid when fitted. The part you
//  just changed flashes red.
//
//  SceneKit is soft-deprecated by Apple in favour of RealityKit but is
//  fully supported on every iOS this app targets; the car is isolated in
//  this one file so moving it later touches nothing else.
//

import SwiftUI
import SceneKit
import ProjectApexCore

struct SetupCar3DView: UIViewRepresentable {
    let selections: [EngineeringCategoryID: EngineeringOptionID]

    func makeCoordinator() -> CarRig { CarRig() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.isPlaying = true
        view.preferredFramesPerSecond = 60

        // Spin it with a finger; turntable orbit only, kept off the floor.
        view.allowsCameraControl = true
        let control = view.defaultCameraController
        control.interactionMode = .orbitTurntable
        control.inertiaEnabled = true
        control.maximumVerticalAngle = 40
        control.minimumVerticalAngle = 4
        control.target = SCNVector3(0, 0.35, 0)

        context.coordinator.apply(selections, flash: nil, animated: false)
        context.coordinator.setSpinning(!context.environment.accessibilityReduceMotion)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(to: selections)
        context.coordinator.setSpinning(!context.environment.accessibilityReduceMotion)
    }
}

// MARK: - The rig

@MainActor
final class CarRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let car = SCNNode()
    private var last: [EngineeringCategoryID: EngineeringOptionID] = [:]
    private var spinning = false

    // Parts that change
    private let frontWing = SCNBox(width: 1.6, height: 0.05, length: 0.36, chamferRadius: 0.02)
    private let rearWing = SCNBox(width: 1.1, height: 0.06, length: 0.36, chamferRadius: 0.02)
    private let frontWingNode = SCNNode()
    private let rearWingNode = SCNNode()
    private var frontPlates: [SCNNode] = []
    private var rearPlates: [SCNNode] = []

    private let podL = SCNBox(width: 0.38, height: 0.30, length: 1.5, chamferRadius: 0.1)
    private let podR = SCNBox(width: 0.38, height: 0.30, length: 1.5, chamferRadius: 0.1)
    private let podLNode = SCNNode()
    private let podRNode = SCNNode()

    private var wheels: [SCNNode] = []     // order: FL, FR, RL, RR
    private var bands: [SCNNode] = []
    private var ducts: [(node: SCNNode, box: SCNBox)] = []
    private let exhaust = SCNNode()

    // One material per group, so a flash lights up exactly that group.
    private let aeroMat = CarRig.paint()
    private let coolingMat = CarRig.paint()
    private let brakesMat = CarRig.paint(brightness: 0.62)
    private let bandMat = CarRig.paint()
    private let rubberMat = CarRig.paint(UIColor(Theme.Color.ink), roughness: 0.9)
    private let bodyMat = CarRig.paint()
    private let stripeMat = CarRig.paint(UIColor(Theme.Color.signal), roughness: 0.35)
    private let exhaustMat = SCNMaterial()

    init() {
        buildStage()
        buildCar()
    }

    // MARK: Updating

    func update(to selections: [EngineeringCategoryID: EngineeringOptionID]) {
        guard selections != last else { return }
        let changed = SetupCarView.changedCategory(from: last, to: selections)
        apply(selections, flash: changed, animated: true)
    }

    func apply(_ s: [EngineeringCategoryID: EngineeringOptionID],
               flash: EngineeringCategoryID?, animated: Bool) {
        last = s
        let pose = CarPose(s)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.45 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1) // slight overshoot

        // Wings grow with downforce.
        let a = CGFloat(pose[.aero])
        frontWing.width = 1.45 + 0.55 * a
        frontWing.length = 0.30 + 0.14 * a
        rearWing.width = 1.0 + 0.35 * a
        rearWing.length = 0.30 + 0.16 * a
        rearWingNode.position.y = Float(0.82 + 0.10 * a)
        for (i, plate) in frontPlates.enumerated() {
            plate.position.x = Float((i == 0 ? -1 : 1) * frontWing.width / 2)
        }
        for (i, plate) in rearPlates.enumerated() {
            plate.position.x = Float((i == 0 ? -1 : 1) * rearWing.width / 2)
        }

        // Cooling is bodywork: heavy cooling, bigger pods.
        let c = CGFloat(pose[.cooling])
        for (pod, node, side) in [(podL, podLNode, CGFloat(-1)), (podR, podRNode, CGFloat(1))] {
            pod.width = 0.30 + 0.22 * c
            pod.length = 1.35 + 0.35 * c
            node.position.x = Float(side * (0.26 + pod.width / 2))
        }

        // Stance: stiff tucks the wheels in, soft plants them wide.
        let track = Float(0.98 - 0.14 * pose[.suspension])
        for (i, wheel) in wheels.enumerated() {
            wheel.position.x = (i % 2 == 0 ? -1 : 1) * track
        }

        // Brake ducts.
        let b = CGFloat(pose[.brakes])
        for (i, duct) in ducts.enumerated() {
            duct.box.length = 0.14 + 0.16 * b
            duct.node.position.x = (i % 2 == 0 ? -1 : 1) * (track - 0.30)
        }

        // Exhaust glow.
        let heat = pose[.engineOn] > 0.5 ? 0.25 + 0.75 * pose[.engine] : 0
        exhaustMat.emission.contents = UIColor(Theme.Color.signal).withAlphaComponent(CGFloat(heat))
        exhaust.opacity = heat > 0 ? 1 : 0

        SCNTransaction.commit()

        // Fitted vs still open: solid vs wireframe.
        setFitted(aeroMat, pose[.aeroOn] > 0.5)
        setFitted(coolingMat, pose[.coolingOn] > 0.5)
        setFitted(brakesMat, pose[.brakesOn] > 0.5)

        // Tyre compound band — F1's own colours.
        if let colour = SetupCarView.tyreColour(s[.tires]) {
            bandMat.diffuse.contents = UIColor(colour)
            bands.forEach { $0.isHidden = false }
        } else {
            bands.forEach { $0.isHidden = true }
        }

        if let flash { self.flash(flash) }
    }

    func setSpinning(_ on: Bool) {
        guard on != spinning else { return }
        spinning = on
        if on {
            car.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 22)), forKey: "spin")
        } else {
            car.removeAction(forKey: "spin")
        }
    }

    // MARK: Flash

    private func flash(_ category: EngineeringCategoryID) {
        let mats: [SCNMaterial]
        switch category {
        case .aerodynamics: mats = [aeroMat]
        case .cooling: mats = [coolingMat]
        case .brakes: mats = [brakesMat]
        case .tires, .suspension: mats = [bandMat, rubberMat]
        case .engineMode: mats = [exhaustMat]
        case .gearRatio, .reliabilityFocus: mats = [stripeMat]
        }
        let red = UIColor(Theme.Color.signal)
        let lit = mats.filter { $0 !== exhaustMat } // the exhaust already glows
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.06
        for m in lit { m.emission.contents = red }
        SCNTransaction.completionBlock = {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.75
            for m in lit { m.emission.contents = UIColor.black }
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
    }

    private func setFitted(_ m: SCNMaterial, _ fitted: Bool) {
        m.fillMode = fitted ? .fill : .lines
        m.transparency = fitted ? 1 : 0.35
    }

    // MARK: Building

    private static func paint(_ colour: UIColor = UIColor(Theme.Color.cream),
                              brightness: CGFloat = 1, roughness: CGFloat = 0.45) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        m.diffuse.contents = UIColor(red: r * brightness, green: g * brightness, blue: b * brightness, alpha: a)
        m.roughness.contents = roughness
        m.metalness.contents = 0.15
        m.emission.contents = UIColor.black
        return m
    }

    private func node(_ g: SCNGeometry, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        n.castsShadow = true
        return n
    }

    private func buildStage() {
        scene.background.contents = UIColor.clear

        // Camera: three-quarter view from the front left, looking at the car.
        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.wantsHDR = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(-3.9, 2.3, -4.3)
        // Aimed once rather than constrained: a look-at constraint fights
        // the finger-orbit camera controller and makes it judder.
        cameraNode.look(at: SCNVector3(0, 0.35, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Garage floor: dark, faintly reflective.
        let floor = SCNFloor()
        // No reflection: on device it rendered as a speckled ghost car
        // under the real one. The soft shadow grounds it on its own.
        floor.reflectivity = 0
        floor.reflectionFalloffEnd = 2
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor(Theme.Color.panel)
        floorMat.lightingModel = .lambert
        floor.materials = [floorMat]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        // Key light from above with soft shadows.
        let key = SCNLight()
        key.type = .spot
        key.intensity = 1300
        key.spotOuterAngle = 70
        key.castsShadow = true
        key.shadowRadius = 10
        key.shadowSampleCount = 8
        key.shadowColor = UIColor.black.withAlphaComponent(0.6)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-1.5, 6, -2)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        // Red rim light from behind — the house colour on the edges.
        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 650
        rim.color = UIColor(Theme.Color.signal)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(2.5, 1.6, 4)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 280
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        scene.rootNode.addChildNode(car)
    }

    private func buildCar() {
        // Nose points toward -z.

        // Tub.
        car.addChildNode(node(SCNBox(width: 0.50, height: 0.34, length: 2.6, chamferRadius: 0.12),
                              bodyMat, 0, 0.36, 0.1))
        // Nose cone.
        let nose = node(SCNCone(topRadius: 0.07, bottomRadius: 0.21, height: 1.5), bodyMat, 0, 0.30, -1.85)
        nose.eulerAngles.x = -.pi / 2
        car.addChildNode(nose)
        // Engine cover and airbox.
        car.addChildNode(node(SCNBox(width: 0.34, height: 0.34, length: 1.3, chamferRadius: 0.12),
                              bodyMat, 0, 0.62, 0.65))
        // Cockpit opening and helmet.
        car.addChildNode(node(SCNCapsule(capRadius: 0.17, height: 0.62),
                              CarRig.paint(UIColor(Theme.Color.ink)), 0, 0.50, -0.35)
                            .rotated(x: .pi / 2))
        car.addChildNode(node(SCNSphere(radius: 0.14), stripeMat, 0, 0.66, -0.25))
        // Livery stripe along the spine.
        car.addChildNode(node(SCNBox(width: 0.08, height: 0.02, length: 2.4, chamferRadius: 0.01),
                              stripeMat, 0, 0.54, -0.2))

        // Sidepods.
        podLNode.geometry = podL; podL.materials = [coolingMat]; podLNode.position = SCNVector3(-0.45, 0.32, 0.25)
        podRNode.geometry = podR; podR.materials = [coolingMat]; podRNode.position = SCNVector3(0.45, 0.32, 0.25)
        [podLNode, podRNode].forEach { $0.castsShadow = true; car.addChildNode($0) }

        // Front wing + endplates.
        frontWing.materials = [aeroMat]
        frontWingNode.geometry = frontWing
        frontWingNode.position = SCNVector3(0, 0.10, -2.7)
        car.addChildNode(frontWingNode)
        for _ in 0..<2 {
            let plate = node(SCNBox(width: 0.03, height: 0.18, length: 0.40, chamferRadius: 0.01), aeroMat, 0, 0.08, 0)
            frontWingNode.addChildNode(plate)
            frontPlates.append(plate)
        }

        // Rear wing on two pillars + endplates.
        rearWing.materials = [aeroMat]
        rearWingNode.geometry = rearWing
        rearWingNode.position = SCNVector3(0, 0.88, 1.75)
        car.addChildNode(rearWingNode)
        for x: Float in [-0.12, 0.12] {
            car.addChildNode(node(SCNBox(width: 0.04, height: 0.45, length: 0.12, chamferRadius: 0.01),
                                  bodyMat, x, 0.62, 1.70))
        }
        for _ in 0..<2 {
            let plate = node(SCNBox(width: 0.03, height: 0.45, length: 0.48, chamferRadius: 0.01), aeroMat, 0, -0.12, 0)
            rearWingNode.addChildNode(plate)
            rearPlates.append(plate)
        }

        // Wheels, compound bands and brake ducts.
        for (z, radius) in [(Float(-1.55), CGFloat(0.31)), (Float(1.35), CGFloat(0.35))] {
            for side: Float in [-1, 1] {
                let tyre = SCNCylinder(radius: radius, height: 0.36)
                let wheel = node(tyre, rubberMat, side * 0.92, Float(radius), z)
                wheel.eulerAngles.z = .pi / 2
                car.addChildNode(wheel)
                wheels.append(wheel)

                // The band sits on the OUTER sidewall. The wheel is turned
                // 90° about z, so its local +y points to world −x: the
                // outside of a right-hand wheel is local −y.
                let band = node(SCNTorus(ringRadius: radius * 0.72, pipeRadius: 0.028), bandMat, 0, -side * 0.185, 0)
                band.isHidden = true
                wheel.addChildNode(band)
                bands.append(band)

                let box = SCNBox(width: 0.10, height: 0.12, length: 0.22, chamferRadius: 0.02)
                let duct = node(box, brakesMat, side * 0.62, Float(radius), z)
                car.addChildNode(duct)
                ducts.append((duct, box))
            }
        }

        // Exhaust glow at the back.
        exhaustMat.lightingModel = .constant
        exhaustMat.diffuse.contents = UIColor(Theme.Color.signal)
        exhaustMat.emission.contents = UIColor(Theme.Color.signal).withAlphaComponent(0)
        exhaust.geometry = SCNSphere(radius: 0.09)
        exhaust.geometry?.materials = [exhaustMat]
        exhaust.position = SCNVector3(0, 0.55, 1.42)
        exhaust.opacity = 0
        car.addChildNode(exhaust)

        // Sit the whole car slightly forward so it turns about its middle.
        car.pivot = SCNMatrix4MakeTranslation(0, 0, -0.1)
    }
}

private extension SCNNode {
    func rotated(x: Float) -> SCNNode {
        eulerAngles.x = x
        return self
    }
}
