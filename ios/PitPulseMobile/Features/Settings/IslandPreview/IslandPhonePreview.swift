import SceneKit
import SharedComponents
import SharedData
import SwiftUI

/// The screen and chassis share one SceneKit coordinate system and camera.
struct IslandPhonePreview: UIViewRepresentable {
    let state: PitPulseActivityAttributes.ContentState
    let expanded: Bool
    var pose: IslandModelPose
    var onCollapsed: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject {
        var material: SCNMaterial?
        var builtThickness: Double?
        var state: PitPulseActivityAttributes.ContentState?
        var progress: Double = 1
        var start: Double = 1
        var target: Double = 1
        var began: CFTimeInterval = 0
        var link: CADisplayLink?
        var onCollapsed: (@MainActor () -> Void)?
        var timelineBegan = CACurrentMediaTime()
        var lastFrame = -1
        var reduceMotion = false

        func update(state: PitPulseActivityAttributes.ContentState, expanded: Bool, animated: Bool) {
            if self.state?.presentation != state.presentation { timelineBegan = CACurrentMediaTime(); lastFrame = -1 }
            self.state = state
            reduceMotion = !animated
            if link == nil {
                let timer = CADisplayLink(target: self, selector: #selector(tick))
                timer.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
                timer.add(to: .main, forMode: .common)
                link = timer
            }
            let next = expanded ? 1.0 : 0.0
            if !animated {
                progress = next
                target = next
            }
            if next != target {
                start = progress
                target = next
                began = CACurrentMediaTime()
            }
            render()
        }

        @objc func tick() {
            if progress != target {
                let t = min(1, (CACurrentMediaTime() - began) / (target == 0 ? 0.38 : 0.85))
                let eased = target == 0 ? 1 - pow(1 - t, 3) : (t == 1 ? 1 : 1 - exp(-8 * t) * (cos(10 * t) + 0.8 * sin(10 * t)))
                progress = start + (target - start) * eased
                render()
                if t == 1, target == 0 { onCollapsed?() }
            } else {
                let elapsed = CACurrentMediaTime() - timelineBegan
                let fourth = state?.presentation == IslandPreviewPage.positionChanges.rawValue
                let phase = fourth ? PositionChangesPreview.phase(at: elapsed) : elapsed.truncatingRemainder(dividingBy: 5)
                let moving = phase < (fourth ? 1.4 : 0.35)
                let frame = moving ? Int(elapsed * 30) : (fourth ? PositionChangesPreview.event(at: elapsed) : Int(elapsed / 5)) * 10000 + 9999
                if frame != lastFrame { lastFrame = frame; render() }
            }
        }

        func render() {
            guard let state else { return }
            let renderer = ImageRenderer(content: PreviewDisplay(state: state, progress: progress, elapsed: CACurrentMediaTime() - timelineBegan, reduceMotion: reduceMotion))
            renderer.scale = 2
            material?.diffuse.contents = renderer.uiImage
        }
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.link?.invalidate()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        return view
    }
}
