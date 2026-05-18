# SiteNotes — Manual Release Checklist

Everything **you** must do manually on a Mac with Xcode + an Apple Developer account before submitting v1.0.

Order matters — do them top to bottom.

---

## 1. Apple Developer account

- [ ] Active Apple Developer Program membership ($99 USD / yr) — sign in at https://developer.apple.com/account
- [ ] Confirm `DEVELOPMENT_TEAM = 45FG6W4U65` in `SiteNote.xcodeproj/project.pbxproj` matches your team

## 2. App Store Connect setup

- [ ] In App Store Connect, create a **new app**:
  - Platform: iOS
  - Bundle ID: `com.banruoyang.sitenote` (the one already in the project)
  - SKU: `sitenotes-ios-v1`
  - Primary language: **English (Australia)** or **English (U.S.)** — pick one
- [ ] Note the **Apple ID** App Store Connect assigns (different from your developer Apple ID)

## 3. Certificates + Provisioning Profile

- [ ] In Xcode → Settings → Accounts, sign in
- [ ] Project → Signing & Capabilities → set "Automatically manage signing" ON, pick the team
- [ ] Verify capabilities are intact: **iCloud (CloudKit)**, **Push Notifications**, **Background Modes (Remote notifications)**
- [ ] Generate or confirm an **iOS Distribution** certificate exists
- [ ] Generate or confirm an **App Store** provisioning profile for `com.banruoyang.sitenote`

## 4. App icon & launch screen

- [ ] Confirm `SiteNote/Assets.xcassets/AppIcon.appiconset/Contents.json` has the 1024 × 1024 master image ✓ (present)
- [ ] **Optional but recommended:** the current icon set uses the *same* 1024 image for the Dark and Tinted slots. On iOS 18+ users who set their home screen to Dark or Tinted mode will see the white-background icon, which can look broken against a dark wallpaper.
  - Dark variant: redraw with a dark background or set the icon to be transparent over a dark fill (matching the system dark home-screen background).
  - Tinted variant: provide a monochrome silhouette (grayscale, transparent background) so iOS can tint it the user's chosen colour.
  - Drop the new PNGs in place of `appstore 1.png` (dark) and `appstore 2.png` (tinted); the `Contents.json` already references them.
- [ ] (Optional) Replace the empty launch screen — `Info.plist` has `UILaunchScreen` set to an empty dict, which renders as the system background. If you want a logo, set the dict's `UIImageName` to an asset name.

## 5. Hosted URLs

- [ ] Publish the privacy policy:
  - Source: `legal/PrivacyPolicy.html`
  - Hosted at: **https://manifoldx.com/sitenotes/privacy** (already linked from the in-app Settings)
- [ ] Publish the terms of service:
  - Source: `legal/TermsOfService.md` (render to HTML or paste into your CMS)
  - Hosted at: **https://manifoldx.com/sitenotes/terms** (linked from in-app Settings)
- [ ] Optional but recommended — publish a support page:
  - Hosted at: **https://manifoldx.com/sitenotes/support**
  - Content: short FAQ, support email `support@manifoldx.com`, link to PrivacyPolicy + Terms

## 6. Screenshots

Apple requires screenshots for these device classes:

| Class | Apple's required size | Real device equivalent |
|---|---|---|
| iPhone 6.9" / 6.7" | 1320 × 2868 (or 1290 × 2796) | iPhone 16 Pro Max / iPhone 15 Pro Max |
| iPhone 6.5" | 1242 × 2688 | iPhone 11 Pro Max / iPhone XS Max |
| iPhone 5.5" | 1242 × 2208 | iPhone 8 Plus (still required for legacy) |
| iPad 12.9" | 2048 × 2732 | iPad Pro 12.9" (6th gen) |

You need ≥ 1 screenshot per class but Apple recommends 5.

Two paths:

### Path A — Automated (Fastlane Snapshot)

```bash
cd /Users/banruo/Developer/SiteNote
gem install bundler fastlane
fastlane snapshot
```

Snapfile + UI test stub are pre-provisioned at `fastlane/Snapfile`. The UI test under `SiteNoteUITests/SnapshotTests.swift` opens the 5 key screens (Onboarding, Notes list, Add log, Photo detail, PDF export). Edit it if the flow has shifted.

### Path B — Manual

1. Open the project in Xcode.
2. Pick each simulator (iPhone 16 Pro Max, iPhone 11 Pro Max, iPhone 8 Plus, iPad Pro 12.9").
3. Run the app, navigate through the 5 key screens.
4. ⌘S in simulator menu → File → Save Screen (or ⌘S keyboard shortcut → saves to `~/Desktop`).
5. Upload the PNGs in App Store Connect.

## 7. App Privacy

Use **APP_PRIVACY_LABEL.md** as your source of truth. Walk through the questionnaire in App Store Connect → App Privacy and answer per that document.

## 8. Age Rating

Use **APP_AGE_RATING.md** — every answer is "None / No". Final rating: **4+**.

## 9. App Review Information

- **Sign-in required:** NO (no accounts — note this in Review Notes so reviewers don't go looking for a login)
- **Demo account:** N/A
- **Contact:** Banruo Yang, `banruostudio@gmail.com`
- **Notes for reviewer** — paste this verbatim:

  > SiteNotes is a voice-first construction site logging app. It has no accounts and no servers — all user data lives on the device + the user's own iCloud (CloudKit). To test the full flow:
  >
  > 1. Tap through the 5-step onboarding (pick "Site Team" role)
  > 2. Long-press the red microphone → dictate a sentence in English → release
  > 3. Tap the saved note → review the AI-classified entries
  > 4. Settings → Sites → "+" → enter "Sydney Sample Site, 123 Sample St Sydney NSW 2000" → Save
  > 5. Back on the Record tab → tag the note to the site
  > 6. Settings → Export My Data → produces a ZIP
  > 7. Settings → Erase All Content → wipes the device + iCloud zone (account deletion equivalent)
  >
  > **Permissions:** the camera, microphone, location-when-in-use, photo-library-add and speech-recognition prompts each have specific "why" descriptions in `Info.plist`. Location is sampled exactly once when the user taps the mic; there is no background location tracking.

## 10. Listing metadata

Use **APP_STORE_LISTING.md** — copy the chosen App Name, Subtitle, Promotional Text, Description, Keywords, Category, URLs, Copyright into App Store Connect.

## 11. Build & upload

In Xcode:

1. Product → Scheme → Edit Scheme → Run / Archive → both set to **Release** build configuration
2. Product → Destination → "Any iOS Device (arm64)"
3. Product → **Archive**
4. Organizer opens → click **Distribute App** → **App Store Connect** → **Upload**
5. Wait for processing (usually 5–30 min). Once processed, the build appears in App Store Connect → TestFlight + Builds.

## 12. Final submission

- [ ] In App Store Connect → App Store tab → Version 1.0:
  - Add build (select the just-uploaded one)
  - Fill all listing fields if not already
  - Privacy & Age Rating: green ticks
  - **Submit for Review**

## 13. Post-submission

- [ ] Apple normally responds in 24–48 hours. Watch the email tied to your Developer account.
- [ ] If rejected, read the message carefully — most rejections cite a specific App Store Review Guideline section (see **REVIEW_GUIDELINE_AUDIT.md**).
- [ ] Approved? Release manually or schedule a release date.

---

## Hard rules — DO NOT skip

- ❌ **DO NOT** ship a build with `ITSAppUsesNonExemptEncryption` missing → already set to `false` in `Info.plist` ✓
- ❌ **DO NOT** ship without `PrivacyInfo.xcprivacy` → already present in `SiteNote/PrivacyInfo.xcprivacy` ✓
- ❌ **DO NOT** push to `main` until v1.0 is approved (current work is on `release/en-v1`)
- ❌ **DO NOT** include personally identifying mock data in the App Store description or screenshots (sanitise to "Sydney Sample Site", "Sam", "Jamie")
- ❌ **DO NOT** ship with bundle / target name mismatch — display name is `SiteNotes`, target is `SiteNote`, bundle ID is `com.banruoyang.sitenote` (this is fine and intentional)
