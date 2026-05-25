# SiteNotes — Fastlane screenshots

Auto-capture the 5 key screens at all required Apple device sizes.

## Prereqs

```bash
gem install bundler fastlane
```

Open `SiteNote.xcodeproj` in Xcode, add a new **UI Test target** named `SiteNoteUITests` (Editor → Add Target → iOS UI Testing Bundle).
Then drag `SiteNoteUITests/SnapshotTests.swift` (from this repo) into the new target's group so it's compiled into the UI test bundle.

## Run

```bash
fastlane snapshot
```

Output goes to `fastlane/screenshots/<lang>/<device>/*.png`. Upload them in App Store Connect.

## Tweaking the captured screens

Edit `SiteNoteUITests/SnapshotTests.swift`. Each `snapshot("name")` call captures the current screen state. The launch flag `-UITestingScreenshots YES` tells `SiteNoteApp` to skip onboarding pop-up and use sanitised mock data (see `SiteNoteApp.swift`).

## If Fastlane is not available

Fall back to manual capture per `RELEASE_CHECKLIST.md` § 6 Path B.
