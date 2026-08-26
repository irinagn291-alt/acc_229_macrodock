import SceneKit
import SwiftUI
import UIKit

/// Role in MVVM-C: SceneKit harbour view. Crate nodes come from live hold stock and answer hit-tests.
struct HarborSceneCanvas: UIViewRepresentable {
    var crates: [HoldCrate]
    var onSelectBarcode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectBarcode: onSelectBarcode)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = TidePalette.uiColor("mdk_background")
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        view.scene = HarborSceneBuilder.makeScene(crates: crates)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSelectBarcode = onSelectBarcode
        context.coordinator.view = view
        HarborSceneBuilder.rebuildCrates(in: view.scene, crates: crates)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelectBarcode: (String) -> Void
        weak var view: SCNView?

        init(onSelectBarcode: @escaping (String) -> Void) {
            self.onSelectBarcode = onSelectBarcode
        }

        @objc
        func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            guard let name = hits.first?.node.name, name.hasPrefix("crate.") else { return }
            let barcode = String(name.dropFirst("crate.".count))
            onSelectBarcode(barcode)
        }
    }
}

enum HarborSceneBuilder {
    static func makeScene(crates: [HoldCrate]) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = TidePalette.uiColor("mdk_background")

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 48
        camera.position = SCNVector3(0, 7.2, 11.5)
        camera.eulerAngles = SCNVector3(-0.55, 0, 0)
        scene.rootNode.addChildNode(camera)

        let water = SCNNode(geometry: SCNPlane(width: 40, height: 40))
        water.geometry?.firstMaterial?.diffuse.contents = TidePalette.uiColor("mdk_surface")
        water.eulerAngles.x = -.pi / 2
        water.position = SCNVector3(0, -0.4, 0)
        scene.rootNode.addChildNode(water)

        let dock = SCNNode(geometry: SCNBox(width: 10, height: 0.35, length: 6, chamferRadius: 0))
        dock.geometry?.firstMaterial?.diffuse.contents = TidePalette.uiColor("mdk_ink")
        dock.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(dock)

        let bollardLeft = bollard()
        bollardLeft.position = SCNVector3(-4.2, 0.45, 2.2)
        scene.rootNode.addChildNode(bollardLeft)
        let bollardRight = bollard()
        bollardRight.position = SCNVector3(4.2, 0.45, 2.2)
        scene.rootNode.addChildNode(bollardRight)

        rebuildCrates(in: scene, crates: crates)
        return scene
    }

    static func rebuildCrates(in scene: SCNScene?, crates: [HoldCrate]) {
        guard let root = scene?.rootNode else { return }
        root.childNodes.filter { $0.name?.hasPrefix("crate.") == true }.forEach { $0.removeFromParentNode() }
        for (index, crate) in crates.prefix(12).enumerated() {
            let column = index % 4
            let row = index / 4
            let height = CGFloat(max(0.35, min(2.4, crate.grams / 220)))
            let box = SCNBox(width: 1.1, height: height, length: 1.1, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = crate.isLow
                ? TidePalette.uiColor("mdk_accent")
                : TidePalette.uiColor("mdk_muted")
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.name = "crate.\(crate.barcode)"
            node.position = SCNVector3(
                Float(column) * 2.0 - 3.0,
                Float(height / 2) + 0.2,
                Float(row) * -1.8
            )
            root.addChildNode(node)
        }
    }

    private static func bollard() -> SCNNode {
        let node = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 0.7))
        node.geometry?.firstMaterial?.diffuse.contents = TidePalette.uiColor("mdk_accent")
        return node
    }
}
