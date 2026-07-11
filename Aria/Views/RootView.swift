import SwiftUI

struct RootView: View {
    @StateObject private var player = PlayerViewModel()

    var body: some View {
        ZStack {
            LibraryView()
                .safeAreaInset(edge: .bottom) {
                    if !player.isPlayerPresented {
                        MiniPlayerBar()
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

            if player.isPlayerPresented {
                NowPlayingView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            if let queueNotice = player.queueNotice {
                VStack {
                    QueueNoticeToast(notice: queueNotice) {
                        player.dismissQueueNotice()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .environmentObject(player)
        .tint(.ariaAccent)
        .preferredColorScheme(.dark)
        .animation(AriaMotion.playerSpring, value: player.isPlayerPresented)
        .animation(AriaMotion.quickSpring, value: player.queueNotice)
    }
}

private struct QueueNoticeToast: View {
    let notice: QueueNotice
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 11) {
                Image(systemName: notice.symbolName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.ariaAccent)
                    .frame(width: 24)

                Text(notice.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 54)
            .frame(maxWidth: 370)
            .background(Color.ariaSurfaceRaised.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
        .accessibilityLabel(notice.message)
        .accessibilityHint("Tap to dismiss")
    }
}
