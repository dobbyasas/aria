import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var player = PlayerViewModel()

    var body: some View {
        ZStack {
            if usesTabletLayout {
                TabletRootView()
            } else {
                phoneRoot
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
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .environmentObject(player)
        .environmentObject(player.playbackClock)
        .tint(.ariaAccent)
        .preferredColorScheme(.dark)
        .task {
            await ProvisioningExpiryMonitor.shared.configureNotifications()
        }
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var phoneRoot: some View {
        ZStack {
            LibraryView()
                .allowsHitTesting(!player.isPlayerPresented || player.presentedArtist != nil)
                .accessibilityHidden(player.isPlayerPresented && player.presentedArtist == nil)
                .safeAreaInset(edge: .bottom) {
                    if !player.isPlayerPresented {
                        MiniPlayerBar()
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }

            if player.isPlayerPresented && player.presentedArtist == nil {
                NowPlayingView()
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
    }
}

private enum TabletDestination: String, CaseIterable, Identifiable {
    case library
    case nowPlaying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            "Library"
        case .nowPlaying:
            "Now Playing"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "music.note.house.fill"
        case .nowPlaying:
            "play.square.stack.fill"
        }
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var selection: TabletDestination = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hasInitialized = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            tabletSidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 286, max: 330)
        } detail: {
            Group {
                if player.presentedArtist != nil {
                    LibraryView()
                } else {
                    switch selection {
                    case .library:
                        LibraryView()
                    case .nowPlaying:
                        NowPlayingView()
                    }
                }
            }
            .transition(.opacity)
            .animation(AriaMotion.fast, value: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.ariaBackground.ignoresSafeArea())
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            let shouldRestorePlayer = player.isPlayerPresented && player.currentTrack != nil
            selection = shouldRestorePlayer ? .nowPlaying : .library

            if !shouldRestorePlayer {
                player.hidePlayer()
            }
        }
        .onChange(of: selection) { _, destination in
            switch destination {
            case .library where player.isPlayerPresented:
                player.hidePlayer()
            case .nowPlaying where !player.isPlayerPresented:
                player.showPlayer()
            default:
                break
            }
        }
        .onChange(of: player.isPlayerPresented) { _, isPresented in
            let destination: TabletDestination = isPresented ? .nowPlaying : .library
            guard selection != destination else { return }
            withAnimation(AriaMotion.fast) {
                selection = destination
            }
        }
    }

    private var tabletSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ARIA")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.ariaTextPrimary)

                Text("Your music, everywhere")
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 18)

            VStack(spacing: 7) {
                ForEach(TabletDestination.allCases) { destination in
                    sidebarButton(destination)
                }
            }
            .padding(.horizontal, 12)

            Divider()
                .overlay(.white.opacity(0.08))
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 13) {
                Text("On your server")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)

                serverCount(title: "Songs", count: player.catalog.count)
                serverCount(title: "Albums", count: player.albums.count)
                serverCount(title: "Playlists", count: player.playlists.count)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 18)

            Text(AriaRelease.displayText)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.ariaTextSecondary.opacity(0.72))
                .padding(.bottom, player.currentTrack == nil ? 18 : 0)
                .accessibilityLabel("Aria \(AriaRelease.displayText)")

            if player.currentTrack != nil {
                MiniPlayerBar()
                    .padding(12)
            }
        }
        .background(Color.ariaSurface.ignoresSafeArea())
    }

    private func sidebarButton(_ destination: TabletDestination) -> some View {
        Button {
            withAnimation(AriaMotion.fast) {
                selection = destination
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: destination.systemImage)
                    .font(.headline.weight(.semibold))
                    .frame(width: 25)

                Text(destination.title)
                    .font(.headline)

                Spacer()
            }
            .foregroundStyle(selection == destination ? .ariaBackground : .ariaTextPrimary)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(selection == destination ? Color.ariaAccent : .white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
    }

    private func serverCount(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ariaTextSecondary)

            Spacer()

            Text(count.formatted())
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.ariaTextPrimary)
        }
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
