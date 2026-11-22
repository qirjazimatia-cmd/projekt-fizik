import SwiftUI
import SceneKit

// Shkolla Don Bosko në 3D (#104).
// Model i stilizuar, i ndërtuar vetëm me kod (pa skedarë 3D, pa foto në app), sipas fotove të para të kampusit:
//  · ndërtesa 2-katëshe e verdhë me dritare katrore jeshile, bazament jeshil, hyrje me strehë jeshile dhe shkallë,
//    paneli i bardhë i muralit në fasadën anësore;
//  · ndërtesa 4-katëshe e verdhë me dritare jeshile pas lëndinës;
//  · grupi i statujave mbi bazamentin e rrumbullakët prej guri dhe pllaka përkujtimore;
//  · gardhi i zi me shkrimin «DON BOSKO», selvia dhe ullinjtë;
//  · fusha e basketbollit me dy kosha dhe portë futbolli (oratori, ku fëmijët bëjnë sport pasdite);
//  · Kisha e Zojës Ndihmëtare (Google Maps: ~87 m në veri dhe ~24 m në lindje të Oratorit; foto nga Google Maps):
//    kambanorja e lartë e bardhë me trarë në formë A dhe kryq, salla me çati të harkuar të bardhë dhe mure të verdha;
//  · oratori: fusha e madhe me bar dhe porta, fusha me dhè, fusha me bar sintetik dhe rrjeta të larta,
//    fusha e basketbollit me pllaka gjashtëkëndore dhe stola blu, ndërtesa bezhë me shkallë dhe ballkone, shtigje me pemë.
// Vendosja e ndërtesave është përafërsisht, jo nga planimetria: përmirësohet kur të vijnë foto nga sipër.

#if os(macOS)
private typealias PlatformColor = NSColor
private typealias PlatformFont = NSFont
#else
private typealias PlatformColor = UIColor
private typealias PlatformFont = UIFont
#endif

private extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Vendet ku kalon kamera.
enum SchoolSpot: String, CaseIterable, Identifiable {
    case overview = "Pamja e plotë"
    case main = "Ndërtesa kryesore"
    case entrance = "Hyrja"
    case statue = "Statuja"
    case gate = "Porta"
    case court = "Basketbolli"
    case field = "Oratori · fushat"
    case church = "Kisha"
    case beige = "Ndërtesa bezhë"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "map"
        case .main: return "building.2"
        case .entrance: return "door.left.hand.open"
        case .statue: return "figure.2.and.child.holdinghands"
        case .gate: return "signpost.right"
        case .court: return "basketball"
        case .church: return "building.columns"
        case .field: return "soccerball"
        case .beige: return "building"
        }
    }
    /// Pozicioni i kamerës dhe pika ku shikon (metra).
    var camera: (eye: SCNVector3, target: SCNVector3) {
        switch self {
        case .overview: return (SCNVector3(-90.0, 95.0, 105.0), SCNVector3(0.0, 0.0, -45.0))
        case .main: return (SCNVector3(-30.0, 12.0, 36.0), SCNVector3(-8.0, 4.0, -2.0))
        case .entrance: return (SCNVector3(-6.0, 4.0, 18.0), SCNVector3(-8.0, 3.0, 6.0))
        case .statue: return (SCNVector3(30.0, 5.0, 26.0), SCNVector3(22.0, 2.0, 12.0))
        case .gate: return (SCNVector3(4.0, 3.0, 52.0), SCNVector3(4.0, 1.5, 34.0))
        case .court: return (SCNVector3(48.0, 16.0, -8.0), SCNVector3(26.0, 0.0, -24.0))
        case .church: return (SCNVector3(10.0, 14.0, -60.0), SCNVector3(50.0, 12.0, -113.0))
        case .field: return (SCNVector3(-30.0, 34.0, -20.0), SCNVector3(-20.0, 0.0, -75.0))
        case .beige: return (SCNVector3(-52.0, 8.0, 28.0), SCNVector3(-58.0, 4.0, 6.0))
        }
    }
}

struct School3DView: View {
    @State private var scene = SchoolScene.make()
    @State private var spot: SchoolSpot = .overview
    @State private var night = false
    var body: some View {
        VStack(spacing: 0) {
            SceneView(scene: scene, pointOfView: scene.rootNode.childNode(withName: "camera", recursively: false),
                      options: [.allowsCameraControl])
                .accessibilityLabel("Modeli 3D i shkollës Don Bosko. Rrotulloje me gisht.")
                .frame(minHeight: 320)
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SchoolSpot.allCases) { place in
                            Button { go(place) } label: {
                                Label(place.rawValue, systemImage: place.symbol).font(.callout)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(place == spot ? Color.lagoon.opacity(0.25) : Color.primary.opacity(0.06)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Toggle(isOn: $night) { Label("Natë", systemImage: "moon.stars") }
                        .fixedSize()
                    Spacer()
                    Text("Model ilustrues nga fotot e shkollës; jo në shkallë të saktë.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .navigationTitle("Shkolla në 3D")
        .onChange(of: night) { SchoolScene.setNight($0, in: scene) }
    }
    private func go(_ place: SchoolSpot) {
        spot = place
        guard let camera = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.2
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        camera.position = place.camera.eye
        camera.look(at: place.camera.target)
        SCNTransaction.commit()
    }
}

enum SchoolScene {
    // Ngjyrat nga fotot.
    private static let ochre = PlatformColor(hex: 0xE9B23C)
    private static let green = PlatformColor(hex: 0x3E8E3A)
    private static let darkGreen = PlatformColor(hex: 0x2F6B2C)
    private static let lawn = PlatformColor(hex: 0x6FA845)
    private static let paving = PlatformColor(hex: 0xC9C4BA)
    private static let stone = PlatformColor(hex: 0x8C7F6E)
    private static let bronze = PlatformColor(hex: 0x6B5A3E)
    private static let glass = PlatformColor(hex: 0x9FC3D1)

    static func make() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = PlatformColor(hex: 0xBFD9EE)
        let root = scene.rootNode

        // Kamera
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.zFar = 600
        camera.camera?.fieldOfView = 50
        camera.position = SchoolSpot.overview.camera.eye
        camera.look(at: SchoolSpot.overview.camera.target)
        root.addChildNode(camera)

        // Dritat
        let sun = SCNNode(); sun.name = "sun"
        sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 1100
        sun.light?.castsShadow = true; sun.light?.shadowRadius = 4; sun.light?.shadowMode = .deferred
        sun.light?.shadowColor = PlatformColor(white: 0, alpha: 0.35)
        sun.eulerAngles = SCNVector3(-0.9, -0.6, 0.0)
        root.addChildNode(sun)
        let ambient = SCNNode(); ambient.name = "ambient"
        ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 420
        root.addChildNode(ambient)

        // Toka: lëndina dhe shtigjet
        root.addChildNode(box(190, 0.2, 200, lawn, at: (0, -0.1, -40)))
        root.addChildNode(box(150, 0.05, 8, paving, at: (0, 0.03, 40)))      // trotuari para gardhit
        root.addChildNode(box(10, 0.05, 30, paving, at: (-8, 0.03, 22)))      // shtegu te hyrja
        root.addChildNode(box(50, 0.05, 6, paving, at: (14, 0.03, 4)))        // shtegu para ndërtesës së dytë

        root.addChildNode(mainBuilding(at: (-8, 0, -2)))
        root.addChildNode(tallBuilding(at: (26, 0, -2)))
        root.addChildNode(statue(at: (22, 0, 14)))
        root.addChildNode(fence(z: 34))
        root.addChildNode(court(at: (26, 0, -26)))
        root.addChildNode(box(8, 0.05, 70, paving, at: (40, 0.03, -70)))     // shtegu drejt kishës
        root.addChildNode(church(at: (50, 0, -113)))
        root.addChildNode(grassField(at: (0, 0, -80)))
        root.addChildNode(dirtField(at: (-58, 0, -78)))
        root.addChildNode(turfField(at: (-52, 0, -36)))
        root.addChildNode(beigeBuilding(at: (-58, 0, 2)))
        for z in stride(from: -18.0, through: 22.0, by: 8.0) { root.addChildNode(smallTree(at: (-40, 0, z))) }   // shtegu me pemë
        root.addChildNode(compass(at: (-70, 0, 30)))

        // Pemët: selvia pranë portës, ullinj dhe pemë të vogla në lëndinë
        root.addChildNode(cypress(at: (14, 0, 30), height: 13))
        for p in [(-34.0, 26.0), (-22.0, 28.0), (32.0, 28.0), (40.0, 18.0), (8.0, 20.0)] {
            root.addChildNode(olive(at: (p.0, 0, p.1)))
        }
        for p in [(-40.0, 10.0), (-40.0, -12.0), (44.0, 6.0)] { root.addChildNode(smallTree(at: (p.0, 0, p.1))) }

        // Etiketat
        root.addChildNode(label("Ndërtesa kryesore", at: (-8, 11.5, -2)))
        root.addChildNode(label("Ndërtesa me 4 kate", at: (26, 17.5, -2)))
        root.addChildNode(label("Statuja", at: (22, 7, 14)))
        root.addChildNode(label("Basketbolli", at: (26, 6, -26)))
        root.addChildNode(label("Kisha e Zojës Ndihmëtare", at: (50, 33, -113)))
        root.addChildNode(label("Oratori · fusha me bar", at: (0, 5, -80)))
        root.addChildNode(label("Fusha me dhè", at: (-58, 4, -78)))
        root.addChildNode(label("Fusha sintetike", at: (-52, 8, -36)))
        root.addChildNode(label("Ndërtesa bezhë", at: (-58, 11, 2)))

        setNight(false, in: scene)
        return scene
    }

    /// Ditë/natë: qielli, dielli dhe dritaret që ndriçojnë.
    static func setNight(_ night: Bool, in scene: SCNScene) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.8
        scene.background.contents = night ? PlatformColor(hex: 0x0E1A33) : PlatformColor(hex: 0xBFD9EE)
        scene.rootNode.childNode(withName: "sun", recursively: false)?.light?.intensity = night ? 60 : 1100
        scene.rootNode.childNode(withName: "ambient", recursively: false)?.light?.intensity = night ? 160 : 420
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "window" {
                node.geometry?.firstMaterial?.emission.contents = night ? PlatformColor(hex: 0xFFD98A) : PlatformColor.black
            }
            if node.name == "lamp" { node.light?.intensity = night ? 900 : 0 }
        }
        SCNTransaction.commit()
    }

    // MARK: Ndërtesat

    /// Ndërtesa 2-katëshe (foto 1): 44 × 12 m, lartësia 8 m.
    private static func mainBuilding(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        let w = 44.0, d = 12.0, h = 8.0
        node.addChildNode(box(w, h, d, ochre, at: (0, h / 2, 0)))
        node.addChildNode(box(w + 0.2, 0.7, d + 0.2, green, at: (0, 0.35, 0)))          // bazamenti jeshil
        node.addChildNode(box(w + 0.4, 0.3, d + 0.4, PlatformColor(hex: 0xD9A22F), at: (0, h + 0.15, 0)))  // korniza e çatisë
        // Dritaret katrore me kornizë jeshile në të dy katet, në fasadën e përparme dhe të pasme.
        for floor in 0..<2 {
            let y = 2.4 + Double(floor) * 3.4
            for i in 0..<12 {
                let x = -19.5 + Double(i) * 3.6
                if floor == 0 && abs(x - 0) < 4 { continue }   // vendi i hyrjes
                node.addChildNode(window(at: (x, y, d / 2 + 0.05), size: 1.7))
                node.addChildNode(window(at: (x, y, -d / 2 - 0.05), size: 1.7, back: true))
            }
        }
        // Hyrja: portal i bardhë, dyer xhami, strehë jeshile, shkallë dhe parmak.
        node.addChildNode(box(7, 3.6, 0.3, PlatformColor(hex: 0xF2F1EC), at: (0, 2.3, d / 2 + 0.15)))
        let doors = box(5.6, 2.8, 0.1, glass, at: (0, 2.0, d / 2 + 0.32)); doors.name = "window"
        doors.geometry?.firstMaterial?.transparency = 0.85
        node.addChildNode(doors)
        node.addChildNode(box(9, 0.35, 3.2, green, at: (0, 4.3, d / 2 + 1.6)))
        for step in 0..<5 {
            let s = Double(step)
            node.addChildNode(box(7 - s * 0.2, 0.18, 4.2 - s * 0.6, PlatformColor(hex: 0xE4E1DA), at: (0, 0.09 + s * 0.18, d / 2 + 2.3 + s * 0.3)))
        }
        for side in [-3.8, 3.8] {
            node.addChildNode(box(0.06, 1.0, 4.4, PlatformColor(hex: 0x3A3A3A), at: (side, 1.4, d / 2 + 2.6)))
        }
        // Paneli i bardhë i muralit në fasadën anësore (vendi i portretit).
        let mural = box(0.1, 5.2, 4.2, PlatformColor(hex: 0xF7F6F2), at: (-w / 2 - 0.06, 4.6, 0))
        node.addChildNode(mural)
        node.addChildNode(box(0.12, 5.6, 0.25, green, at: (-w / 2 - 0.07, 4.6, 2.2)))
        node.addChildNode(box(0.12, 5.6, 0.25, green, at: (-w / 2 - 0.07, 4.6, -2.2)))
        // Dritaret anësore në skaj (si në foto).
        node.addChildNode(window(at: (-w / 2 - 0.05, 2.4, 4.3), size: 1.4, side: true))
        node.addChildNode(window(at: (-w / 2 - 0.05, 5.8, 4.3), size: 1.4, side: true))
        // Llamba e hyrjes (natën)
        let lamp = SCNNode(); lamp.name = "lamp"
        lamp.light = SCNLight(); lamp.light?.type = .omni; lamp.light?.color = PlatformColor(hex: 0xFFD98A)
        lamp.light?.attenuationEndDistance = 14; lamp.light?.intensity = 0
        lamp.position = SCNVector3(0.0, 4.0, d / 2 + 2.5)
        node.addChildNode(lamp)
        return node
    }

    /// Ndërtesa 4-katëshe (foto 3): 30 × 12 m, lartësia 14 m.
    private static func tallBuilding(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        let w = 30.0, d = 12.0, h = 14.0
        node.addChildNode(box(w, h, d, ochre, at: (0, h / 2, 0)))
        node.addChildNode(box(w + 0.2, 0.6, d + 0.2, PlatformColor(hex: 0xEDEAE2), at: (0, 0.3, 0)))
        node.addChildNode(box(w + 0.4, 0.3, d + 0.4, PlatformColor(hex: 0xD9A22F), at: (0, h + 0.15, 0)))
        for floor in 0..<4 {
            let y = 2.0 + Double(floor) * 3.3
            for i in 0..<8 {
                let x = -12.6 + Double(i) * 3.6
                node.addChildNode(window(at: (x, y, d / 2 + 0.05), size: 1.6))
                node.addChildNode(window(at: (x, y, -d / 2 - 0.05), size: 1.6, back: true))
            }
        }
        // Shkallët dhe rampa me parmak (pas statujës).
        node.addChildNode(box(5, 0.6, 3, PlatformColor(hex: 0xE4E1DA), at: (-9, 0.3, d / 2 + 1.5)))
        node.addChildNode(box(9, 0.08, 0.06, PlatformColor(hex: 0x3A3A3A), at: (-3, 1.3, d / 2 + 2.6)))
        return node
    }

    private static func window(at p: (Double, Double, Double), size: Double, back: Bool = false, side: Bool = false) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        if side { node.eulerAngles = SCNVector3(0.0, Double.pi / 2, 0.0) }
        if back { node.eulerAngles = SCNVector3(0.0, Double.pi, 0.0) }
        node.addChildNode(box(size + 0.5, size + 0.5, 0.12, green, at: (0, 0, 0)))                // korniza jeshile
        let pane = box(size, size, 0.14, PlatformColor(hex: 0x4B5D66), at: (0, 0, 0.02)); pane.name = "window"
        node.addChildNode(pane)
        return node
    }

    // MARK: Oborri

    /// Statuja (foto 3): bazament i rrumbullakët me dy nivele prej guri, katër figura bronzi dhe pllaka.
    private static func statue(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(cylinder(2.8, 0.5, stone, at: (0, 0.25, 0)))
        node.addChildNode(cylinder(2.0, 0.5, PlatformColor(hex: 0x9A8C79), at: (0, 0.75, 0)))
        let figures: [(Double, Double, Double)] = [(-0.9, 0.2, 2.0), (-0.2, -0.3, 1.8), (0.5, 0.2, 1.9), (1.1, -0.1, 1.4)]
        for f in figures {
            let figure = SCNNode(); figure.position = SCNVector3(f.0, 1.0, f.1)
            figure.addChildNode(capsule(0.28, f.2, bronze, at: (0, f.2 / 2, 0)))
            figure.addChildNode(sphere(0.2, bronze, at: (0, f.2 + 0.12, 0)))
            node.addChildNode(figure)
        }
        let plaque = box(1.6, 0.25, 1.0, PlatformColor(hex: 0xEDEBE6), at: (-5, 0.12, 2.5))
        plaque.eulerAngles = SCNVector3(0.0, 0.3, 0.0)
        node.addChildNode(plaque)
        node.addChildNode(shrub(at: (4.2, 0, 2.0)))
        return node
    }

    /// Gardhi i zi me shufra dhe shkrimi i bardhë «DON BOSKO» (foto 2).
    private static func fence(z: Double) -> SCNNode {
        let node = SCNNode()
        let length = 120.0
        node.addChildNode(box(length, 0.08, 0.08, PlatformColor(hex: 0x1E1E1E), at: (0, 2.4, z)))
        node.addChildNode(box(length, 0.08, 0.08, PlatformColor(hex: 0x1E1E1E), at: (0, 0.3, z)))
        var x = -length / 2
        while x <= length / 2 {
            node.addChildNode(box(0.05, 2.5, 0.05, PlatformColor(hex: 0x1E1E1E), at: (x, 1.25, z)))
            x += 0.6
        }
        let text = SCNText(string: "DON BOSKO", extrusionDepth: 0.15)
        text.font = PlatformFont.systemFont(ofSize: 1.6, weight: .heavy)
        text.flatness = 0.05
        text.firstMaterial?.diffuse.contents = PlatformColor.white
        text.firstMaterial?.emission.contents = PlatformColor(white: 0.35, alpha: 1)
        let letters = SCNNode(geometry: text)
        let (minB, maxB) = letters.boundingBox
        letters.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, minB.y, 0)
        letters.position = SCNVector3(4.0, 0.6, z + 0.15)
        node.addChildNode(letters)
        return node
    }

    /// Fusha e basketbollit (foto 5): beton gri, vija të bardha, dy kosha dhe një portë e vogël.
    private static func court(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(box(28, 0.1, 15, PlatformColor(hex: 0x9C8A8E), at: (0, 0.05, 0)))   // pllaka gjashtëkëndore
        for x in [-8.0, 0.0, 8.0] { node.addChildNode(box(4, 0.45, 0.6, PlatformColor(hex: 0x3B55A0), at: (x, 0.45, 9.0))) }   // stolat blu
        let white = PlatformColor(white: 0.95, alpha: 1)
        for line in [(0.0, 7.4, 28.0, 0.1), (0.0, -7.4, 28.0, 0.1)] { node.addChildNode(box(line.2, 0.02, line.3, white, at: (line.0, 0.11, line.1))) }
        for line in [(13.9, 0.0), (-13.9, 0.0), (0.0, 0.0)] { node.addChildNode(box(0.1, 0.02, 15, white, at: (line.0, 0.11, line.1))) }
        node.addChildNode(cylinder(1.8, 0.02, white, at: (0, 0.11, 0)))
        node.addChildNode(cylinder(1.7, 0.03, PlatformColor(hex: 0x9C8A8E), at: (0, 0.12, 0)))
        for side in [-1.0, 1.0] {
            let pole = box(0.18, 3.6, 0.18, PlatformColor(hex: 0x3B55A0), at: (side * 14.6, 1.8, 0))
            node.addChildNode(pole)
            node.addChildNode(box(0.1, 1.05, 1.8, PlatformColor(hex: 0xF1F1F1), at: (side * 13.7, 3.4, 0)))
            node.addChildNode(box(1.0, 0.12, 0.12, PlatformColor(hex: 0x3B55A0), at: (side * 14.15, 3.4, 0)))
            let ring = SCNTorus(ringRadius: 0.23, pipeRadius: 0.02)
            ring.firstMaterial?.diffuse.contents = PlatformColor(hex: 0xD3542B)
            let rim = SCNNode(geometry: ring); rim.position = SCNVector3(side * 13.35, 3.05, 0.0)
            node.addChildNode(rim)
        }
        // Porta e vogël e futbollit në anë të fushës.
        let goal = SCNNode(); goal.position = SCNVector3(0.0, 0.0, -9.5)
        goal.addChildNode(box(0.1, 2.0, 0.1, white, at: (-1.5, 1.0, 0)))
        goal.addChildNode(box(0.1, 2.0, 0.1, white, at: (1.5, 1.0, 0)))
        goal.addChildNode(box(3.1, 0.1, 0.1, white, at: (0, 2.0, 0)))
        node.addChildNode(goal)
        return node
    }

    /// Kisha e Zojës Ndihmëtare (sipas fotove): salla me mure të verdha dhe çati të harkuar të bardhë,
    /// dhe pranë saj kambanorja e lartë prej trarësh të bardhë që bashkohen në majë, me kryq.
    private static func church(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        let cream = PlatformColor(hex: 0xF3EFE6)
        node.addChildNode(box(26, 7, 18, PlatformColor(hex: 0xE8C46A), at: (0, 3.5, 0)))
        let vault = SCNCylinder(radius: 9.2, height: 26.4); vault.materials = [material(cream)]
        let roof = SCNNode(geometry: vault); roof.position = SCNVector3(0.0, 7.0, 0.0)
        roof.eulerAngles = SCNVector3(0.0, 0.0, Double.pi / 2)
        node.addChildNode(roof)
        for i in 0..<6 { node.addChildNode(window(at: (-10 + Double(i) * 4, 3.2, 9.05), size: 1.2)) }
        // Kambanorja: dy korniza në formë A, njëra pingul me tjetrën, që takohen në majë.
        let spire = SCNNode(); spire.position = SCNVector3(-18.0, 0.0, 6.0)
        let h = 26.0
        for x in [-4.5, -2.0, 2.0, 4.5] {
            let length = (x * x + h * h).squareRoot()
            let beamNode = box(0.45, length, 0.45, cream, at: (x / 2, h / 2, 0))
            beamNode.eulerAngles = SCNVector3(0.0, 0.0, atan2(x, h))
            spire.addChildNode(beamNode)
        }
        for z in [-3.0, 3.0] {
            let length = (z * z + h * h).squareRoot()
            let beamNode = box(0.45, length, 0.45, cream, at: (0, h / 2, z / 2))
            beamNode.eulerAngles = SCNVector3(-atan2(z, h), 0.0, 0.0)
            spire.addChildNode(beamNode)
        }
        spire.addChildNode(box(0.25, 3.0, 0.25, cream, at: (0, h + 1.5, 0)))      // kryqi
        spire.addChildNode(box(1.6, 0.25, 0.25, cream, at: (0, h + 2.1, 0)))
        node.addChildNode(spire)
        node.addChildNode(box(32, 0.1, 26, paving, at: (-3, 0.06, 2)))
        return node
    }

    /// Fusha e madhe me bar e oratorit, me dy porta.
    private static func grassField(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(box(60, 0.06, 36, PlatformColor(hex: 0x7DB54E), at: (0, 0.03, 0)))
        for x in [-29.0, 29.0] { node.addChildNode(goal(at: (x, 0, 0), width: 5, height: 2.2, alongZ: true)) }
        return node
    }

    /// Fusha me dhè (lojë futbolli pa bar).
    private static func dirtField(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(box(44, 0.06, 28, PlatformColor(hex: 0xC9AE86), at: (0, 0.03, 0)))
        for x in [-21.0, 21.0] { node.addChildNode(goal(at: (x, 0, 0), width: 3, height: 2, alongZ: true)) }
        return node
    }

    /// Fusha me bar sintetik, e rrethuar me rrjeta të larta.
    private static func turfField(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(box(36, 0.08, 20, PlatformColor(hex: 0x3F8F45), at: (0, 0.04, 0)))
        let net = PlatformColor(white: 0.2, alpha: 1)
        for (w, d, x, z) in [(36.0, 0.04, 0.0, 10.0), (36.0, 0.04, 0.0, -10.0), (0.04, 20.0, 18.0, 0.0), (0.04, 20.0, -18.0, 0.0)] {
            let mesh = box(w, 6, d, net, at: (x, 3, z)); mesh.opacity = 0.18
            node.addChildNode(mesh)
        }
        for x in stride(from: -18.0, through: 18.0, by: 6.0) {
            for z in [-10.0, 10.0] { node.addChildNode(box(0.12, 6.2, 0.12, net, at: (x, 3.1, z))) }
        }
        for x in [-17.0, 17.0] { node.addChildNode(goal(at: (x, 0, 0), width: 3, height: 2, alongZ: true)) }
        return node
    }

    /// Ndërtesa bezhë me dy kate, shkallë të gjera dhe ballkone (foto nga Google Maps).
    private static func beigeBuilding(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        let beige = PlatformColor(hex: 0xE6D7B4)
        node.addChildNode(box(24, 8, 12, beige, at: (0, 4, 0)))
        node.addChildNode(box(24.4, 0.4, 12.4, PlatformColor(hex: 0xD3C39E), at: (0, 8.2, 0)))
        for floor in 0..<2 {
            for i in 0..<6 {
                let x = -10.0 + Double(i) * 4
                if floor == 0 && abs(x) < 3 { continue }
                let pane = box(1.6, 1.8, 0.14, PlatformColor(hex: 0x4B5D66), at: (x, 2.2 + Double(floor) * 3.4, 6.05)); pane.name = "window"
                node.addChildNode(pane)
                if floor == 1 { node.addChildNode(box(2.4, 0.15, 1.0, PlatformColor(hex: 0xD3C39E), at: (x, 4.7, 6.5))) }   // ballkoni
            }
        }
        node.addChildNode(box(3.2, 2.8, 0.14, PlatformColor(hex: 0x3A3A3A), at: (0, 1.6, 6.05)))   // dera
        for step in 0..<4 {
            let s = Double(step)
            node.addChildNode(box(8 - s * 0.8, 0.2, 3.6 - s * 0.6, PlatformColor(hex: 0xDAD6CC), at: (0, 0.1 + s * 0.2, 7.8 + s * 0.3)))
        }
        return node
    }

    private static func goal(at p: (Double, Double, Double), width: Double, height: Double, alongZ: Bool) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        if alongZ { node.eulerAngles = SCNVector3(0.0, Double.pi / 2, 0.0) }
        let white = PlatformColor(white: 0.96, alpha: 1)
        node.addChildNode(box(0.12, height, 0.12, white, at: (-width / 2, height / 2, 0)))
        node.addChildNode(box(0.12, height, 0.12, white, at: (width / 2, height / 2, 0)))
        node.addChildNode(box(width + 0.12, 0.12, 0.12, white, at: (0, height, 0)))
        return node
    }

    /// Shigjeta e veriut (Veriu = −z).
    private static func compass(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(cylinder(3, 0.1, PlatformColor(white: 0.95, alpha: 1), at: (0, 0.06, 0)))
        let arrow = SCNCone(topRadius: 0, bottomRadius: 0.8, height: 3.2)
        arrow.firstMaterial?.diffuse.contents = PlatformColor(hex: 0xC0392B)
        let tip = SCNNode(geometry: arrow); tip.position = SCNVector3(0.0, 0.3, -0.6); tip.eulerAngles = SCNVector3(-Double.pi / 2, 0.0, 0.0)
        node.addChildNode(tip)
        node.addChildNode(label("V", at: (0, 1.0, -3.6)))
        return node
    }

    // MARK: Pemët

    private static func cypress(at p: (Double, Double, Double), height: Double) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(cylinder(0.25, 1.2, PlatformColor(hex: 0x5A4632), at: (0, 0.6, 0)))
        let cone = SCNCone(topRadius: 0.1, bottomRadius: 1.4, height: CGFloat(height))
        cone.firstMaterial?.diffuse.contents = PlatformColor(hex: 0x24452A)
        let top = SCNNode(geometry: cone); top.position = SCNVector3(0.0, 1.0 + height / 2, 0.0)
        node.addChildNode(top)
        return node
    }

    private static func olive(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(cylinder(0.3, 2.2, PlatformColor(hex: 0x6B5843), at: (0, 1.1, 0)))
        node.addChildNode(sphere(2.4, PlatformColor(hex: 0x7F9469), at: (0, 3.6, 0)))
        node.addChildNode(sphere(1.6, PlatformColor(hex: 0x8DA277), at: (1.2, 4.2, 0.6)))
        return node
    }

    private static func smallTree(at p: (Double, Double, Double)) -> SCNNode {
        let node = SCNNode(); node.position = SCNVector3(p.0, p.1, p.2)
        node.addChildNode(cylinder(0.15, 1.6, PlatformColor(hex: 0x6B5843), at: (0, 0.8, 0)))
        node.addChildNode(sphere(1.2, darkGreen, at: (0, 2.4, 0)))
        return node
    }

    private static func shrub(at p: (Double, Double, Double)) -> SCNNode {
        sphere(0.7, PlatformColor(hex: 0x3F7A34), at: (p.0, 0.6, p.2))
    }

    // MARK: Ndihmëse

    private static func material(_ color: PlatformColor) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .physicallyBased; m.roughness.contents = 0.85
        return m
    }
    private static func box(_ w: Double, _ h: Double, _ d: Double, _ color: PlatformColor, at p: (Double, Double, Double)) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        return node
    }
    private static func cylinder(_ r: Double, _ h: Double, _ color: PlatformColor, at p: (Double, Double, Double)) -> SCNNode {
        let geometry = SCNCylinder(radius: CGFloat(r), height: CGFloat(h)); geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        return node
    }
    private static func sphere(_ r: Double, _ color: PlatformColor, at p: (Double, Double, Double)) -> SCNNode {
        let geometry = SCNSphere(radius: CGFloat(r)); geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        return node
    }
    private static func capsule(_ r: Double, _ h: Double, _ color: PlatformColor, at p: (Double, Double, Double)) -> SCNNode {
        let geometry = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(h)); geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        return node
    }
    /// Etiketë që kthehet gjithmonë nga kamera.
    private static func label(_ text: String, at p: (Double, Double, Double)) -> SCNNode {
        let geometry = SCNText(string: text, extrusionDepth: 0.02)
        geometry.font = PlatformFont.systemFont(ofSize: 1.2, weight: .semibold)
        geometry.flatness = 0.1
        geometry.firstMaterial?.diffuse.contents = PlatformColor.white
        geometry.firstMaterial?.emission.contents = PlatformColor(white: 0.8, alpha: 1)
        geometry.firstMaterial?.readsFromDepthBuffer = false
        let textNode = SCNNode(geometry: geometry)
        let (minB, maxB) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, minB.y, 0)
        let holder = SCNNode(); holder.position = SCNVector3(p.0, p.1, p.2)
        holder.constraints = [SCNBillboardConstraint()]
        holder.renderingOrder = 10
        holder.addChildNode(textNode)
        return holder
    }
}
