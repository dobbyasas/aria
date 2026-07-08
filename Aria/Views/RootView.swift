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
        }
        .environmentObject(player)
        .tint(.ariaAccent)
        .preferredColorScheme(.dark)
        .animation(AriaMotion.playerSpring, value: player.isPlayerPresented)
    }
}
