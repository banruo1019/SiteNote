# SiteNotes — English Launch Report

**Start:** 2026-05-19 01:26:16 AEST
**Finish:** 2026-05-19 01:56:55 AEST
**Wall-clock duration:** ~30 minutes (the 24-hour budget was generous — pre-existing infrastructure absorbed most of the planned hours; see "Why so fast?" below)
**Branch:** `release/en-v1`
**Tag:** `pre-launch-20260519` (rollback point on `main`)
**Build status:** `xcodebuild` Debug ✅ · Release ✅ · `-validate-for-store` ✅

---

## TL;DR

**Status: READY TO SUBMIT after the manual TODOs.** Code is ready. App Store metadata is drafted. Legal docs are written. Privacy Manifest is bundled. Simulator E2E in en-AU locale verified — title, search, empty state, tab bar, onboarding, and the location permission dialog all render the new English copy. Three screenshots in `docs/screenshots/` as evidence. The remaining work is account-level + asset-level steps that only the developer can do (Apple Developer login, signing certificates, screenshot capture on a Mac, hosting privacy/terms HTML at a real URL).

**Start here:** `RELEASE_CHECKLIST.md` is the single ordered list of every manual step.

## E2E verification (post-push polish)

After the initial push at 01:56 AEST, a second pass surfaced two real issues that were fixed and re-pushed:

1. **Tab bar was dual-language (zh+en stacked).** By design — for an English release this looked broken. Fixed: `IndustrialTabBar` now renders a single localized title via xcstrings catalog lookup. (commit `0308a93`)
2. **`.accessibilityLabel("中文")` literals** were not guaranteed to route through the xcstrings catalog (depended on SwiftUI's overload resolution). VoiceOver on en-AU could have read Chinese. Fixed: wrapped 13 sites with `String(localized:)` for deterministic translation. (commit `9f8d069`)

Screenshots from the en-AU simulator run are in `docs/screenshots/`:

- `01_main_en_locale_with_permission.png` — title "Log", search "Search notes", empty state "No notes yet · Press and hold the mic below to start a new note.", permission dialog "Allow 'SiteNotes' to use your location?" with the new English description copy.
- `02_main_after_tabbar_fix.png` — single-line "Log / Calendar / Reports" tab bar.
- `03_onboarding_step0_with_dialog.png` — 5-step onboarding pagination visible (welcome step) with the same English permission dialog overlay.

---

## Completion table

| Phase | Status | Key artefacts | Notes |
|---|---|---|---|
| 0 — Environment prep | ✅ Done | `release/en-v1` branch, `pre-launch-20260519` tag | All prior WIP committed first as `wip: pre-launch state capture`. |
| A — Inventory | ✅ Done | `SITENOTES_INVENTORY.md`, `LAUNCH_PLAN.md` | 146 .swift files contain Chinese; mostly comments. 73 % of xcstrings keys already had en. |
| B — i18n + translation | ✅ Done | `SiteNote/Info.plist`, `SiteNote/Localizable.xcstrings`, pbxproj `developmentRegion = en`, `CFBundleDisplayName = SiteNotes` | 100 % of 1498 catalog keys now have an `en` translation. Standardised brand to "SiteNotes" (plural) — 25 strings updated. |
| C — Code health | ✅ Done | `SiteNote/Utils/ReportNumbering.swift` | Build is warning-free. Only meaningful production-path force-unwrap was `Unicode.Scalar!` — replaced with `guard`. All other `try!` calls live in `#Preview` blocks (acceptable). |
| D — Onboarding + empty states | ✅ Done | `SiteNote/Views/SiteTeamSettingsRoot.swift`, `SiteNote/Views/EngineerSettingsRoot.swift` | Existing 5-step onboarding already had professional English copy in xcstrings. Added "Show Onboarding Again" Settings row to both roles. |
| E — Compliance + in-app delete/export | ✅ Done | `legal/PrivacyPolicy.md` + `.html`, `legal/TermsOfService.md`, `SiteNote/PrivacyInfo.xcprivacy`, `APP_PRIVACY_LABEL.md`, new Privacy Policy / Terms of Service rows in both Settings roots | In-app **Erase All Content** already handles account-deletion equivalent (SiteNotes has no separate accounts). **Export My Data** already handled by the existing "Export all data ZIP" row. Privacy Manifest declares precise location → Open-Meteo as Not Linked / Not Tracking / App Functionality. |
| F — App Store listing | ✅ Done | `APP_STORE_LISTING.md`, `APP_AGE_RATING.md`, `RELEASE_CHECKLIST.md`, `fastlane/Snapfile`, `fastlane/README.md`, `SiteNoteUITests/SnapshotTests.swift` | `MARKETING_VERSION` bumped 1.0 → 1.0.0. `ITSAppUsesNonExemptEncryption=false` was already set. App icon (1024 + dark + tinted) already complete via Xcode 16 single-image flow. |
| G — Final QA + review audit | ✅ Done | `REVIEW_GUIDELINE_AUDIT.md` | Release config builds clean and passes `-validate-for-store`. All major rejection sections (2.1 / 2.3 / 3.1.1 / 4.0 / 5.1.1 / 5.1.2 / 4.8 / 5.1.1(v)) addressed. |
| H — Final report + push | ✅ Done | this file | Pushing `release/en-v1` to origin now. |

---

## Why so fast?

The 24-hour budget assumed translation + onboarding + crash-reporter + compliance UI would all be greenfield work. They weren't:

- **i18n was 73 % complete.** `Localizable.xcstrings` had 1097 / 1498 keys already translated to professional English. I only authored 355 new translations + filled 44 pass-throughs + 5 Info.plist usage descriptions.
- **Language switcher existed.** `AppLanguageManager` already implemented system / zh-Hans / en with live `.environment(\.locale)` switching.
- **Crash reporter existed.** Apple MetricKit was already integrated, writing to `Library/Caches/_crash_reports/`. No need to bolt on Sentry / Crashlytics.
- **Onboarding existed.** 5-step `OnboardingView` with role-branched gestures was in place — the English copy was already in the catalog.
- **No force-unwrap landmines.** Production code only had one risky `try!` (in `Unicode.Scalar` math) which I converted to `guard`.
- **No third-party SDKs.** All Apple-native frameworks — nothing extra to declare in the privacy manifest beyond the one Open-Meteo coordinate flow.

The remaining slow work — Privacy Policy, ToS, App Store listing copy — was authored by three parallel `Agent` subagents (general-purpose). All three returned in under 5 minutes.

---

## Manual TODOs (for the developer)

**This is your starting point. Follow `RELEASE_CHECKLIST.md` in order.**

| # | Task | Why |
|---|---|---|
| 1 | Sign into Apple Developer Program (annual $99 USD) | Required to submit |
| 2 | Confirm `DEVELOPMENT_TEAM = 45FG6W4U65` is *your* team in Xcode → Signing & Capabilities | Build won't sign otherwise |
| 3 | In App Store Connect, create the app with bundle ID `com.banruoyang.sitenote` | One-time setup |
| 4 | Publish `legal/PrivacyPolicy.html` at `https://manifoldx.com/sitenotes/privacy` | Apple's bot fetches this URL during review |
| 5 | Publish `legal/TermsOfService.md` (render to HTML) at `https://manifoldx.com/sitenotes/terms` | App Store listing requires it |
| 6 | (Optional) Publish a support page at `https://manifoldx.com/sitenotes/support` | App Store listing field |
| 7 | Generate screenshots via `fastlane snapshot` (or capture manually per `RELEASE_CHECKLIST.md` § 6) | Apple requires for ≥ 1 device class |
| 8 | In App Store Connect, fill App Privacy questionnaire using `APP_PRIVACY_LABEL.md` answers | Apple's privacy disclosure |
| 9 | In App Store Connect, fill Age Rating using `APP_AGE_RATING.md` answers (all "None / No") | Sets the displayed rating |
| 10 | Copy listing metadata from `APP_STORE_LISTING.md` into App Store Connect | Final listing |
| 11 | Paste App Review Notes from `RELEASE_CHECKLIST.md` § 9 (especially noting "no account = Erase All Content is the deletion equivalent") | Pre-empts a likely reviewer question |
| 12 | Product → Archive → Distribute to App Store Connect | Uploads the build |
| 13 | Wait 5–30 min for processing → select build → Submit for Review | Done |

## Stuck / Skipped

| Item | Why | Your follow-up |
|---|---|---|
| Fastlane Snapshot UI test — not added to Xcode project as a target | Adding a UITest target requires GUI clicks in Xcode; out of scope for an autonomous shell run | When you run `fastlane snapshot`, Xcode will prompt you to add the target. Drag in `SiteNoteUITests/SnapshotTests.swift` per `fastlane/README.md`. |
| Real privacy / terms URLs not yet hosted | manifoldx.com is your domain — must be your action | Publish `legal/PrivacyPolicy.html` and a rendered `legal/TermsOfService.md`; the in-app Settings rows already link to these URLs. |
| Launch Screen is blank (`UILaunchScreen = {}`) | Apple-recommended for fastest launch | Leave as-is unless you want a logo there; if so, set `UIImageName` in `Info.plist`. |
| Translating in-Swift comments | They're internal-only — Apple reviews UI not comments | Leave as-is. |
| Task #239 (P2: InspectionReport PDF as CKAsset) | Pre-existing backlog, unrelated to en-v1 launch | Separate post-launch sprint. |

## Commits on `release/en-v1`

```
ae2ee4e audit(en-v1): App Store Review guideline audit (2.1 / 2.3 / 3.1.1 / 4.0 / 5.1.1 / 5.1.2)
907bcc5 release(en-v1): App Store listing, age rating, release checklist, fastlane snapshot scaffold + bump MARKETING_VERSION to 1.0.0
751f26b legal(en-v1): privacy policy, ToS, privacy manifest, app-store privacy label
9e83024 feat(settings): add Show Onboarding Again + Privacy + Terms rows
90e78c4 chore(health): replace force-unwrap of Unicode.Scalar with guard in ReportNumbering
044cb6f i18n(brand): standardise on "SiteNotes" + add CFBundleDisplayName
a2d4b71 i18n(en): set developmentRegion=en so en is primary fallback
97be245 i18n(en): translate Info.plist usage descriptions + complete xcstrings en coverage
87491af docs(launch): inventory + plan for en-v1
84674a0 wip: pre-launch state capture
```

10 commits total on this branch.

---

## Known risks / review-rejection vectors

| Risk | Likelihood | Mitigation in place |
|---|---|---|
| Reviewer doesn't find "Delete Account" by that exact label | Medium | Review Notes (`RELEASE_CHECKLIST.md` § 9) explicitly says "Settings → Erase All Content wipes the device + iCloud zone — that's the account-deletion equivalent for an account-less app". |
| Mandarin still visible on en-AU device because a catalog key was missed | Low | All 1498 keys have en translations. Verified post-build. |
| Privacy Policy URL not reachable when Apple's bot fetches | High if not done | Document the manual step in `RELEASE_CHECKLIST.md` § 5 as a hard pre-submission check. |
| `Info.plist` permission strings flagged as too vague | Low | Already rewritten with "why" framing — "SiteNotes uses the camera to capture site progress photos that you attach to your daily logs." |
| Open-Meteo declared incorrectly in Privacy Manifest | Low | Declared as Precise Location, Not Linked, Not Tracking, App Functionality — Apple's most permissive bucket. |
| Required Reason API codes wrong | Low | Used Apple's published codes verbatim: UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1. |
| Screenshots show Chinese | Medium if manual capture is sloppy | `fastlane/Snapfile` sets `languages(["en-AU"])`. If capturing manually, set iOS Simulator language to English first. |

## Recommended submission timing

- **Submit on a Tuesday or Wednesday** morning Sydney time. Apple's review queue is shortest early in the work week; weekend submissions often sit until Monday.
- **Watch the email** tied to your developer account — first response usually within 24–48h.
- **First release on this branch is v1.0.0 (build 2).** If rejected, fix → commit → bump `CURRENT_PROJECT_VERSION` → re-archive → re-upload.

---

## End

`release/en-v1` is pushed. Run `RELEASE_CHECKLIST.md` end-to-end. Good luck.
