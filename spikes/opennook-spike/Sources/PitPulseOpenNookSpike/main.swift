import AppKit
import NookApp
import SwiftUI

@MainActor
final class SpikeController: ObservableObject {
    @Published private(set) var surfaceState = "已隐藏"

    let nook = Nook(
        style: .standard,
        expanded: { SpikePanel() },
        compactLeading: { Image(systemName: "flag.checkered") },
        compactTrailing: { Text("FP1") }
    )

    var displays: [NSScreen] { NSScreen.screens }

    var panelReport: String {
        let screen = nook.window?.screen?.localizedName ?? "无窗口"
        return "\(String(describing: nook.state)) · \(String(describing: nook.layoutForm)) · \(screen)"
    }

    func expand(on screen: NSScreen? = nil) {
        Task {
            await nook.expand(on: screen)
            surfaceState = "展开"
        }
    }

    func compact() {
        Task {
            await nook.compact()
            surfaceState = "紧凑"
        }
    }

    func hide() {
        Task {
            await nook.hide()
            surfaceState = "已隐藏"
        }
    }
}

struct SpikePanel: View, Sendable {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PitPulse · OpenNook Spike").font(.headline)
            Text("单一 SwiftUI App 入口 + MenuBarExtra + NookSurface")
                .foregroundStyle(.white)
            Text("仅验证显示生命周期；不是赛事数据")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(minWidth: 320)
    }
}

@main
struct PitPulseOpenNookSpike: App {
    @StateObject private var controller = SpikeController()

    var body: some Scene {
        WindowGroup("OpenNook Spike") {
            controls
                .frame(minWidth: 300)
                .padding()
        }

        MenuBarExtra("PitPulse OpenNook Spike", systemImage: "flag.checkered") {
            controls
                .padding(12)
                .frame(minWidth: 260)
        }
        .menuBarExtraStyle(.menu)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenNook 生命周期 Spike").font(.headline)
            Text("Panel 状态：\(controller.surfaceState)")
            Text("实际：\(controller.panelReport)")
            Text("显示器：\(controller.displays.count)")
            Button("展开") { controller.expand() }
            Button("紧凑") { controller.compact() }
            Button("隐藏并销毁窗口") { controller.hide() }
            if controller.displays.count > 1 {
                Divider()
                ForEach(Array(controller.displays.enumerated()), id: \.offset) { index, screen in
                    Button("显示器 \(index + 1)：\(screen.localizedName)") {
                        controller.expand(on: screen)
                    }
                }
            }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}
