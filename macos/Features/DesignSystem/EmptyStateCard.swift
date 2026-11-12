import AppKit
import SwiftUI
import SharedData

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }
}
