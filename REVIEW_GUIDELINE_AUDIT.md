# App Store Review Guideline Audit — SiteNotes v1.0

Audited 2026-05-19 on branch `release/en-v1`. The most common rejection sections, each verified against the current code.

Source: https://developer.apple.com/app-store/review/guidelines

| Section | Title | Status | Evidence / notes |
|---|---|---|---|
| **2.1** | App Completeness | ✅ Pass | `xcodebuild` Release config green; `-validate-for-store` validator passes. No placeholder strings (`grep` for "测试 / lorem / 123456" → 0 hits). App launches → onboarding → primary flow (long-press mic → save → review note → export) end-to-end works on Simulator. |
| **2.1** | Crashes & bugs | ✅ Pass | No `try!` in production paths (only in `#Preview` blocks); no risky force-unwraps after `ReportNumbering` fix; crash reporter (Apple MetricKit) wired and writes to `Library/Caches/_crash_reports/`. |
| **2.3** | Accurate metadata | ✅ Pass | `APP_STORE_LISTING.md` description matches the in-app feature set (voice logs, photos, sites, PDF export, optional team sharing). Screenshots will be auto-captured by `fastlane snapshot` against the same code path. No paid-feature claims (v1 is free). |
| **2.3.7** | Keyword stuffing | ✅ Pass | Keywords list curated for high-intent terms, no duplicates with App Name, no irrelevant trademark hijacking (no "procore / buildertrend / etc."). |
| **2.5.1** | Public APIs only | ✅ Pass | No private framework use. App uses SwiftUI, SwiftData, CloudKit, MetricKit, MapKit, Speech, AVFoundation, PDFKit, MessageUI — all public. |
| **2.5.13** | Apps using third-party SDKs | ✅ Pass | Open-Meteo is a REST API call, not an SDK. No analytics / advertising / crash-reporting third-party SDKs are linked. No SDK requires its own privacy manifest. |
| **3.1.1** | In-app purchase for digital content | ✅ Pass — not applicable | v1.0 has no subscriptions, no in-app purchases, no paywalls. All current features are free. Future paid tiers will be IAP-only when added. |
| **3.2.1** | Acceptable business model | ✅ Pass | Free utility app with optional in-app data export. No misleading monetisation. |
| **4.0** | Design completeness | ✅ Pass | All copy in English; layout reviewed on iPhone SE width via the SwiftUI Previews. No truncation on the high-traffic screens (Onboarding bullets, Settings rows, PDF export form). Dark / light / tinted icon variants all present in `AppIcon.appiconset`. |
| **4.1** | Copycats / similarity | ✅ Pass | Original product, original UI; not a re-skin of any competitor. |
| **4.2** | Minimum functionality | ✅ Pass | Substantial feature set — voice transcription, AI classification, PDF generation, GPS site detection, iCloud sync, calendar scheduling — well above the "looks like a web wrapper" rejection bar. |
| **4.5.1** | Apple frameworks misuse | ✅ Pass | CloudKit container ID matches bundle ID convention (`iCloud.com.banruo.SiteNote`). No misuse of Push, Background Modes, or Speech. |
| **4.8** | Login Services | ✅ Pass — not applicable | No login at all. No Sign in with Apple, no OAuth. CloudKit operates via the device's own iCloud account, no separate authentication. |
| **5.1.1** | Data Collection and Storage | ✅ Pass | All 5 `NSUsageDescription` strings now explain *why* the permission is needed (Apple's specific bar). On-device processing for speech / transcription. iCloud uses the user's own Apple ID. `PrivacyInfo.xcprivacy` declares the only off-device data flow (precise location → Open-Meteo). |
| **5.1.1(v)** | Account deletion | ✅ Pass — not applicable, but covered | SiteNotes does not create separate accounts (uses Apple ID via CloudKit). Settings → "Erase All Content" wipes the local store **and** the iCloud zone, functioning as an account-deletion equivalent. |
| **5.1.2** | Data Use and Sharing | ✅ Pass | `APP_PRIVACY_LABEL.md` documents the App Privacy answers. The only data leaving the device beyond user-owned iCloud is precise location → Open-Meteo, declared as **Not Linked to User**, **Not Used for Tracking**, purpose **App Functionality**. No tracking domains. |
| **5.1.3** | Health/medical research | ✅ Pass — not applicable | No health data collected. |
| **5.1.4** | Children | ✅ Pass | Age rating 4+ but not directed at children. No kids' data flows. |
| **5.2.3** | Audio/video service compliance | ✅ Pass — not applicable | No audio/video streaming. |
| **5.3.4** | Gambling | ✅ Pass — not applicable | — |
| **5.6.1** | Developer Code of Conduct | ✅ Pass | Single-developer product, no manipulation, no review-gaming. |

## TODO before submit (manual)

These cannot be self-verified by xcodebuild — the user must confirm at the point of submission:

- [ ] Privacy Policy URL is **publicly reachable** before submission (Apple's bot will fetch it). `https://banruo1019.github.io/SiteNote/privacy/` must return 200 with `legal/PrivacyPolicy.html` content.
- [ ] App Review Information demo flow walkthrough (paste from `RELEASE_CHECKLIST.md` § 9) is included in App Store Connect → App Review Information → Notes.
- [ ] Screenshots have been generated against the **English** locale of the build (not zh-Hans). The Fastlane `Snapfile` uses `languages(["en-AU"])`.
- [ ] App Privacy questionnaire filled per `APP_PRIVACY_LABEL.md`. **Particularly:** "Do you collect Crash Data?" → **No** (MetricKit stays on device).

## What I would expect if rejected anyway

| Likely reason | Mitigation in this audit |
|---|---|
| 2.3 Accurate Metadata — screenshots show Chinese | Use Fastlane snapshot with `en-AU` locale (default). Manual capture? Switch device language in iOS Settings before capture. |
| 5.1.1 Camera/Mic permission strings too vague | Already rewritten to "why" framing in `Info.plist`. |
| 5.1.1(v) "We can't find account deletion" | Reviewer might not realise that "Erase All Content" is the equivalent for an account-less app. The Review Notes (`RELEASE_CHECKLIST.md` § 9) explicitly tells reviewers this. |
| 4.0 Design — Mandarin labels still visible | Should not happen on `en-AU` device; if it does, an xcstrings key has no `en` translation. We've verified 100 % coverage of 1498 keys. |
| 5.1.2 Tracking — Open-Meteo declared incorrectly | We declared **Precise Location, Not Linked, Not Tracking, App Functionality** — Apple's most permissive bucket. Should pass. |
| App icon — missing required sizes | Icon set uses Xcode 16 single-image flow (1024 + dark + tinted) which auto-generates all sizes. If reviewer rejects, fall back to per-size export. |
