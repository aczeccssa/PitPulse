import SceneKit
import SharedComponents
import SharedData
import SwiftUI

struct IslandModelPose {
    var xAngle = 4.8
    var yAngle = 21.4
    var zAngle = 8.5
    var horizontal = -0.43
    var vertical = 0.17
    var thickness = 0.80

    func apply(to node: SCNNode) {
        node.eulerAngles = SCNVector3(Float(xAngle * .pi / 180), Float(yAngle * .pi / 180), Float(zAngle * .pi / 180))
        node.position = SCNVector3(Float(horizontal), Float(-vertical), 0)
    }
}
