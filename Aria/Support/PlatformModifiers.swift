import SwiftUI

extension View {
    @ViewBuilder
    func ariaInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func ariaSearchFieldBehavior() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func ariaTabBarHidden() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func ariaTabBarVisible() -> some View {
        #if os(iOS)
        toolbar(.visible, for: .tabBar)
        #else
        self
        #endif
    }
}
