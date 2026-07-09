# Aria

Aria is a native SwiftUI iPhone music player prototype. This first version focuses on the player experience: queue controls, shuffle/repeat, saved songs, progress seeking, volume, search, and a small browse/library shell around the player.

The app now loads its catalog from the Fedora song server and streams each song with `AVPlayer`.
It tries Tailscale first at `http://100.93.250.104:8000`, then falls back to the local Wi-Fi address `http://192.168.0.16:8000`.

## Open the App

1. Install Xcode from the Mac App Store if it is not installed.
2. Open `Aria.xcodeproj`.
3. Select an iPhone simulator or device.
4. Build and run the `Aria` scheme.

This machine currently has only Command Line Tools selected, so terminal builds with `xcodebuild` will fail until Xcode is installed or selected with:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Project Shape

- `Aria/App`: app entry point.
- `Aria/Models`: track, playlist, tab, and repeat-mode data types.
- `Aria/Services`: Fedora server client and sample catalog data.
- `Aria/ViewModels`: player state and audio playback.
- `Aria/Views`: SwiftUI screens and reusable UI components.
- `Aria/Support`: styling and formatting helpers.

The Python song server lives on the Fedora laptop at `~/aria-server/server`.
