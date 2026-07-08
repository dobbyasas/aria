# Aria

Aria is a native SwiftUI iPhone music player prototype. This first version focuses on the player experience: queue controls, shuffle/repeat, saved songs, progress seeking, volume, search, and a small browse/library shell around the player.

The app now loads its catalog from the Fedora song server at `http://192.168.0.192:8000/api/tracks` and streams each song with `AVPlayer`.

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
- `server`: Python song server for the Fedora laptop.
