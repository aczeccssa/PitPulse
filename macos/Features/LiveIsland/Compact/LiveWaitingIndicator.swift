import AppKit
import SwiftUI
import SharedData

struct LiveWaitingIndicator: View {
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "ellipsis")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 16, height: 16)
        .help(detail)
        .accessibilityLabel("等待实时数据")
        .accessibilityValue(detail)
    }
}

