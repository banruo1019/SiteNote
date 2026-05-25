# SiteNotes — English Launch Plan

**Phase ordering:** A (done) → B → C → D → E → F → G → H

## Phase B — i18n + translation (target ~5h)

| # | Task | File(s) |
|---|---|---|
| B1 | Translate 5 NSUsageDescription strings in `Info.plist` to professional English with "why we need" framing | `SiteNote/Info.plist` |
| B2 | Fill 401 missing `en` translations in xcstrings | `SiteNote/Localizable.xcstrings` |
| B3 | Spot-audit a sample of the 1097 existing `en` translations — fix non-idiomatic / direct-translation copy | same |
| B4 | Make English default fallback — flip `sourceLanguage` to `en` (rewrite catalog with en source + zh-Hans translation) OR set `DEVELOPMENT_LANGUAGE = en` in pbxproj | `SiteNote/Localizable.xcstrings`, `SiteNote.xcodeproj/project.pbxproj` |
| B5 | Onboarding English copy QA — re-read every `String(localized:)` call in `OnboardingView.swift` | `SiteNote/Views/OnboardingView.swift` |
| B6 | Build verification — `xcodebuild` after each major change | — |

**Out of scope:** translating internal Swift code comments (not user-facing).

## Phase C — code health (target ~3h)

| # | Task |
|---|---|
| C1 | Full `xcodebuild` clean, all errors + warnings logged |
| C2 | Spot-check 3 long-text screens (Settings rows, Onboarding bullets, PDF preview) at iPhone SE width — fix truncations |
| C3 | Audit accessibility labels on top 5 high-traffic screens |
| C4 | Force-unwrap / `try!` sweep — convert to safe paths or `assertionFailure` |
| C5 | Network error UX — verify `EmailService` / `WeatherService` / `OpenAIClient` show friendly errors |
| C6 | Placeholder sweep — remove any "测试 / lorem / 123456" |

## Phase D — onboarding + empty states (target ~2h)

| # | Task |
|---|---|
| D1 | Reskin existing OnboardingView copy to English + tighten per HIG (Title Case for CTAs, sentence case for body) |
| D2 | Add empty state copy for Notes / Sites / Reports |
| D3 | Add "Show Onboarding Again" Settings row — sets `dismissedKey = false` |
| D4 | Verify permission-prompt explanations match Info.plist |

## Phase E — compliance + in-app delete / export (target ~3h)

| # | Task |
|---|---|
| E1 | Write `legal/PrivacyPolicy.md` + `legal/PrivacyPolicy.html` (single-file render) |
| E2 | Write `legal/TermsOfService.md` (Apple Standard EULA + supplements) |
| E3 | Write `APP_PRIVACY_LABEL.md` — App Privacy questionnaire answers |
| E4 | Create `SiteNote/PrivacyInfo.xcprivacy` — Required Reason API declarations |
| E5 | In-app **Delete Account** (Settings → confirm sheet → wipe SwiftData + CloudKit zone) |
| E6 | In-app **Export My Data** (Settings → produce ZIP) |
| E7 | Settings: link to Privacy Policy / Terms of Service / Open-Source Licenses |

## Phase F — App Store listing + assets (target ~3h)

| # | Task |
|---|---|
| F1 | `APP_STORE_LISTING.md` — name, subtitle, promo, description, keywords |
| F2 | Category — Business primary, Productivity secondary |
| F3 | `APP_AGE_RATING.md` — answers + reasoning, target 4+ |
| F4 | App Review Information — reviewer notes + permission justification + contact |
| F5 | Screenshots automation — Fastlane Snapshot script + Mac README |
| F6 | App Icon — verify 1024 master, write any todos |
| F7 | Launch Screen — minimal SwiftUI launch view (logo + app name) |
| F8 | Info.plist — `ITSAppUsesNonExemptEncryption=false` (already done ✓) |
| F9 | Build settings — `MARKETING_VERSION = 1.0.0`, build = auto |
| F10 | `RELEASE_CHECKLIST.md` — manual Apple Developer steps |

## Phase G — final QA (target ~2h)

| # | Task |
|---|---|
| G1 | `xcodebuild` Release + Debug both green |
| G2 | Simulator E2E — onboarding → log → photo → switch project → export → settings → language → delete account |
| G3 | Info.plist permission strings — re-verify English wording |
| G4 | `REVIEW_GUIDELINE_AUDIT.md` — sections 2.1 / 2.3 / 3.1.1 / 4.0 / 5.1.1 / 5.1.2 |

## Phase H — closeout (target 30 min)

| # | Task |
|---|---|
| H1 | Final `LAUNCH_REPORT.md` — status, manual TODO list, commit log, risks |
| H2 | `git push origin release/en-v1` |

## Risk register

| Risk | Mitigation |
|---|---|
| xcstrings flip of `sourceLanguage` breaks build | Keep current zh-Hans source + ensure 100 % en coverage. Only flip if time + green build. |
| Code comments in Chinese trigger reviewer concern | Apple reviews UI not internal comments; leave as-is. |
| Force-unwrap landmines surface during translate-and-build | Fix in C4; if late-stage, schedule patch v1.0.1. |
| Account-deletion edge cases (in-flight CloudKit sync) | Confirm sheet warns, then queue delete + wipe local. |
| PrivacyInfo.xcprivacy reasons incomplete | Use Apple's reason codes verbatim per API; err on the side of declaring more. |

## Don'ts

- No `force-push`, no push to anything other than `release/en-v1`
- No edits to `Entitlements`, signing, pbxproj capabilities (only `MARKETING_VERSION` + `DEVELOPMENT_LANGUAGE` if needed)
- No touching `Hero` MIC / camera circle (132 pt) position / size / colour — iron rule
- No third-party SDK adds (Sentry / Firebase) without user sign-off
