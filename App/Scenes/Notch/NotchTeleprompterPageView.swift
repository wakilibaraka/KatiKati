import SwiftUI

// Phase 37c — the optional 7th notch page: a short script under the camera. Long scripts and links live in
// the floating window (button at the right of the controls).

struct NotchTeleprompterPageView: View {
    var body: some View {
        TeleprompterView(compact: true)
            .padding(NotchDesignSpec.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
            )
            .onDisappear { TeleprompterModel.shared.pause() }
    }
}
