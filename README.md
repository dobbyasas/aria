# Aria

Aria is a native universal SwiftUI music player for iPhone and iPad. It includes queue controls, shuffle/repeat, saved songs, progress seeking, volume, search, and a responsive library/player shell.

When another Aria device is already playing, the app automatically shows that device's live playback and controls it instead of starting a second audio stream. The playback-session menu can start an independent session on this device or rejoin shared playback at any time.

Artist names open dedicated pages with a YouTube Music portrait, downloaded songs and albums, and additional albums that can be sent to the Aria download server.

On iPad, Aria uses a persistent navigation sidebar with library counts and a mini-player, adaptive album and playlist grids, spacious detail screens, and a two-column Now Playing layout with the queue alongside the main controls. Narrow iPad multitasking automatically falls back to the compact iPhone layout.

The app now loads its catalog from the Fedora song server and streams each song with `AVPlayer`.

## Song radio

Choose **Start Radio** from a song's menu, the Now Playing screen, or a YouTube
Music song search result. Aria plays the selected song first, then follows
YouTube Music's radio recommendations. It downloads missing songs to the shared
Fedora library before playback and prepares three upcoming songs at a time.
Existing downloads are reused, and catalog updates preserve the current queue
and playback position. Downloads use the same server as the rest of the app;
they are not offline files stored on the iPhone.

**Remove song** immediately skips the current song, excludes it from future
radio on this device, and deletes its shared download and playlist references.
If the downloader is busy, deletion waits until it finishes. Failed deletions
show a retry button and survive an app restart. Explicitly starting radio from
an excluded song allows that seed again. **Stop radio** stops adding songs;
already prepared songs remain playable, and an accepted server download may
finish. Choosing another song or playlist stops the previous radio session.

Songs newly downloaded by radio carry a persistent server-side
`isRadioDownload` flag. The Library shows their count with **Delete all** to
clear those downloads together, including their shared playlist references.
This stops radio and waits for any active download to finish. Existing library
songs reused by radio remain unflagged and are kept. Bulk cleanup does not
exclude the deleted songs from future radio recommendations.

Radio uses YouTube Music's anonymous radio queue, so its recommendations can
differ from those of a signed-in YouTube account. The web endpoint can change;
connection and recommendation errors appear in the player with a retry action.
When this iPhone is controlling another device, starting radio creates separate
playback on the iPhone. If the phone already hosts shared playback, it keeps that
session.

Install the matching `feature/iphone-song-radio` server changes along with this
app build; single-song removal requires `DELETE /api/tracks/<track-id>`.

Run the radio regression tests using the Aria scheme's Test action in Xcode, or
`xcodebuild -project Aria.xcodeproj -scheme Aria -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`.

## Server connection

It tries Tailscale first at `http://100.93.250.104:8000`, then falls back to the local Wi-Fi address `http://192.168.0.16:8000`.
The Library plus button opens a downloader with YouTube Music album search, artwork and metadata, repeatable three-at-a-time results, downloaded-album detection, a manual-link fallback, and live server job progress while new songs are saved into the Fedora songs folder.

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
