import SceneKit
import SharedComponents
import SharedData
import SwiftUI

extension IslandPhonePreview {
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onCollapsed = onCollapsed
        if context.coordinator.material != nil, context.coordinator.builtThickness == pose.thickness {
            if let phone = view.scene?.rootNode.childNode(withName: "previewPhone", recursively: false) {
                pose.apply(to: phone)
            }
            context.coordinator.update(state: state, expanded: expanded, animated: !reduceMotion)
            return
        }
        context.coordinator.builtThickness = pose.thickness
        let scene = SCNScene()
        let root = SCNNode()
        root.name = "previewPhone"
        scene.rootNode.addChildNode(root)
        let studio = IslandPreviewTexture.make(width: 1024, height: 512) { context in
            let colors = [UIColor(white: 0.12, alpha: 1).cgColor, UIColor(white: 0.95, alpha: 1).cgColor, UIColor(white: 0.25, alpha: 1).cgColor, UIColor.white.cgColor, UIColor(white: 0.08, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.22, 0.40, 0.62, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 150), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.5
        let brushedMetal = IslandPreviewTexture.make(width: 256, height: 4096) { context in
            UIColor(white: 0.65, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 4096))
            for row in 0..<4096 {
                let value = 0.63 + 0.025 * (sin(Double(row) * 127.1) * 0.5 + 0.5)
                UIColor(white: value, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row, width: 256, height: 1))
            }
        }
        let brushedNormal = IslandPreviewTexture.make(width: 128, height: 2048) { context in
            for row in 0..<2048 {
                let grain = sin(Double(row) * 91.7) * 0.10
                UIColor(red: 0.5, green: 0.5 + grain, blue: 1, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row, width: 128, height: 1))
            }
        }
        func shell(width: CGFloat, height: CGFloat, radius: CGFloat, depth: CGFloat, color: UIColor, z: Float) {
            let path = UIBezierPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: radius)
            path.flatness = 0.001
            let shape = SCNShape(path: path, extrusionDepth: depth)
            shape.chamferRadius = 0.025
            shape.firstMaterial?.diffuse.contents = color
            shape.firstMaterial?.lightingModel = .physicallyBased
            if depth > 0.1 {
                shape.firstMaterial?.diffuse.contents = brushedMetal
                shape.firstMaterial?.normal.contents = brushedNormal
                shape.firstMaterial?.normal.intensity = 0.65
            }
            shape.firstMaterial?.metalness.contents = 0.9
            shape.firstMaterial?.roughness.contents = depth > 0.1 ? 0.34 : 0.22
            let node = SCNNode(geometry: shape)
            node.position.z = z
            root.addChildNode(node)
        }
        // Add thickness behind the fixed front face; keep screen alignment intact.
        let bodyDepth = CGFloat(pose.thickness)
        let bodyCenterZ: Float = 0.07 - Float(bodyDepth) / 2
        let sideKeyZ = bodyCenterZ + 0.04
        shell(width: 4.16, height: 8.88, radius: 0.57, depth: bodyDepth,
              color: UIColor(white: 0.34, alpha: 1), z: bodyCenterZ)
        // A narrow polished front chamfer catches the studio strip separately
        // from the rougher brushed rail; both are actual extruded surfaces.
        shell(width: 4.17, height: 8.89, radius: 0.575, depth: 0.045,
              color: UIColor(white: 0.82, alpha: 1), z: 0.10)
        shell(width: 4.1, height: 8.82, radius: 0.55, depth: 0.025, color: .black, z: 0.145)
        // Flush insulating band across the rail above the mute key.
        let antenna = SCNPlane(width: bodyDepth - 0.04, height: 0.045)
        antenna.cornerRadius = 0.012
        antenna.firstMaterial?.diffuse.contents = UIColor(white: 0.30, alpha: 1)
        antenna.firstMaterial?.lightingModel = .constant
        let antennaNode = SCNNode(geometry: antenna)
        antennaNode.eulerAngles.y = -.pi / 2
        antennaNode.position = SCNVector3(-2.083, 3.10, bodyCenterZ)
        root.addChildNode(antennaNode)
        // Recessed dark gasket plus a rounded metal cap, seated in the side rail.
        for (y, height): (Float, CGFloat) in [(2.7, 0.25), (1.85, 0.56), (0.95, 0.56)] {
            // The gasket needs its own capsule outline: a thin SCNBox clamps
            // chamferRadius to its thickness and leaves square-looking ends.
            let socketOutline = UIBezierPath(roundedRect: CGRect(x: -0.0775, y: -(height + 0.035) / 2,
                width: 0.155, height: height + 0.035), cornerRadius: 0.0775)
            socketOutline.flatness = 0.001
            let socket = SCNShape(path: socketOutline, extrusionDepth: 0.012)
            socket.chamferRadius = 0.004
            socket.firstMaterial?.diffuse.contents = UIColor(white: 0.10, alpha: 1)
            let recess = SCNNode(geometry: socket)
            recess.eulerAngles.y = -.pi / 2
            recess.position = SCNVector3(-2.085, y, sideKeyZ)
            root.addChildNode(recess)
            let outline = UIBezierPath(roundedRect: CGRect(x: -0.0625, y: -height / 2, width: 0.125, height: height), cornerRadius: 0.06)
            outline.flatness = 0.001
            let button = SCNShape(path: outline, extrusionDepth: 0.025)
            button.chamferRadius = 0.008
            let metal = SCNMaterial()
            metal.lightingModel = .physicallyBased
            metal.diffuse.contents = brushedMetal
            metal.metalness.contents = 0.85
            metal.roughness.contents = 0.3
            metal.normal.contents = brushedNormal
            metal.normal.intensity = 0.3
            button.firstMaterial = metal
            let node = SCNNode(geometry: button)
            node.eulerAngles.y = -.pi / 2
            node.position = SCNVector3(-2.105, y, sideKeyZ)
            root.addChildNode(node)
        }
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 700
        key.position = SCNVector3(-5, 5, 6)
        scene.rootNode.addChildNode(key)
        // Double the black inset from 0.04 to 0.08 on each edge.
        let screenInset: CGFloat = 0.08
        let screen = SCNPlane(width: 4.1 - 2 * screenInset, height: 8.82 - 2 * screenInset)
        // Restore the original screen corner; the rolled edge is a separate mesh.
        screen.cornerRadius = 0.50
        screen.cornerSegmentCount = 48
        context.coordinator.material = screen.firstMaterial
        context.coordinator.update(state: state, expanded: expanded, animated: !reduceMotion)
        screen.firstMaterial?.lightingModel = .constant
        let display = SCNNode(geometry: screen)
        display.position.z = 0.183
        root.addChildNode(display)
        // A quarter-round cross-section bridges black bezel and display.
        // This changes the edge profile, not the four screen corner radii.
        var rimVertices: [SCNVector3] = []
        var rimNormals: [SCNVector3] = []
        var rimIndices: [Int32] = []
        let arcSteps = 16
        let profileSteps = 12
        let perimeterCount = 4 * (arcSteps + 1)
        for level in 0...profileSteps {
            let angle = Double(level) / Double(profileSteps) * .pi / 2
            let inset = 0.08 * (1 - cos(angle))
            let z = 0.145 + 0.038 * sin(angle)
            let radius = 0.55 - 0.05 * (inset / 0.08)
            let halfWidth = 2.05 - inset
            let halfHeight = 4.41 - inset
            for corner in 0..<4 {
                let sx = corner == 0 || corner == 3 ? 1.0 : -1.0
                let sy = corner < 2 ? 1.0 : -1.0
                for step in 0...arcSteps {
                    let a = Double(corner) * .pi / 2 + Double(step) / Double(arcSteps) * .pi / 2
                    let nx = cos(a), ny = sin(a)
                    rimVertices.append(SCNVector3(Float(sx * (halfWidth - radius) + radius * nx),
                        Float(sy * (halfHeight - radius) + radius * ny), Float(z)))
                    let lateral = 0.038 * cos(angle)
                    let forward = 0.08 * sin(angle)
                    let magnitude = sqrt(lateral * lateral + forward * forward)
                    rimNormals.append(SCNVector3(Float(nx * lateral / magnitude), Float(ny * lateral / magnitude), Float(forward / magnitude)))
                }
            }
        }
        for level in 0..<profileSteps {
            for point in 0..<perimeterCount {
                let next = (point + 1) % perimeterCount
                let a = Int32(level * perimeterCount + point)
                let b = Int32(level * perimeterCount + next)
                let c = Int32((level + 1) * perimeterCount + point)
                let d = Int32((level + 1) * perimeterCount + next)
                rimIndices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let rim = SCNGeometry(sources: [SCNGeometrySource(vertices: rimVertices), SCNGeometrySource(normals: rimNormals)],
            elements: [SCNGeometryElement(indices: rimIndices, primitiveType: .triangles)])
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 0.018, alpha: 1)
        glass.roughness.contents = 0.18
        rim.firstMaterial = glass
        root.addChildNode(SCNNode(geometry: rim))
        let receiver = SCNPlane(width: 0.52, height: 0.038)
        receiver.cornerRadius = 0.019
        receiver.cornerSegmentCount = 12
        receiver.firstMaterial?.lightingModel = .constant
        receiver.firstMaterial?.diffuse.contents = IslandPreviewTexture.make(width: 208, height: 16) { context in
            UIColor(white: 0.15, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 208, height: 16))
            UIColor(white: 0.40, alpha: 1).setFill()
            for x in stride(from: 4, to: 208, by: 8) {
                context.fillEllipse(in: CGRect(x: x, y: 5, width: 3, height: 6))
            }
        }
        let receiverNode = SCNNode(geometry: receiver)
        receiverNode.position = SCNVector3(0, 4.37, 0.195)
        root.addChildNode(receiverNode)
        pose.apply(to: root)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(-1.08, 0.7, 9.8)
        #if DEBUG
        if CommandLine.arguments.contains("--island-device-overview") {
            camera.position = SCNVector3(0, 0, 18)
        }
        #endif
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
    }
}
