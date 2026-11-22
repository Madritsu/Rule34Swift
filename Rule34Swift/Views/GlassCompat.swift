import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    @ViewBuilder
    func r34Glass(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        #if os(macOS)
        self.r34Material(cornerRadius: cornerRadius)
        #else
        if #available(iOS 26.0, *) {
            #if compiler(>=6.2)
            self.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            #else
            self.r34Material(cornerRadius: cornerRadius)
            #endif
        } else {
            self.r34Material(cornerRadius: cornerRadius)
        }
        #endif
    }

    private func r34Material(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }

    @MainActor
    func dismissKeyboard() {
        #if canImport(UIKit) && !os(macOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

struct R34EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: String?

    init(title: LocalizedStringKey, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

