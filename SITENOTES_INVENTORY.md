# SiteNotes — Codebase Inventory

**Generated:** 2026-05-19 (Phase A)
**Branch:** `release/en-v1`

## Stack

- **Platform:** iOS native, **SwiftUI** (no UIKit-only screens)
- **Persistence:** SwiftData (`@Model`) + CloudKit mirror
- **Min deployment target:** iOS 17.0 (per `IPHONEOS_DEPLOYMENT_TARGET`)
- **Xcode project format:** Xcode 16 `PBXFileSystemSynchronizedRootGroup` (objectVersion = 77) — new `.swift` files auto-sync into the target
- **Bundle ID:** `com.banruoyang.sitenote`
- **Version:** `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 2`
- **Encryption:** `ITSAppUsesNonExemptEncryption = false` (only HTTPS) — already set ✓
- **AppIcon:** universal 1024×1024 + dark + tinted (Xcode 16 single-image, auto-generates all sizes) ✓
- **Launch screen:** SwiftUI `UILaunchScreen` empty dict (default) — needs polish

## i18n state

- **String Catalog:** `SiteNote/Localizable.xcstrings` (1498 keys)
- **Source language:** `zh-Hans`
- **knownRegions:** `en`, `zh-Hans`, `Base`
- **Coverage:**
  - 1097 keys have `en` translation (73%)
  - 401 keys missing `en` translation (gap to fill)
  - 8 keys have explicit `zh-Hans` override
- **Localization framework:**
  - `String(localized:, locale:)` API used in 844 call sites
  - `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` (modern xcstrings extraction)
  - Live runtime switch already implemented via `AppLanguageManager` + `.environment(\.locale)`
  - `AppLanguage` enum: `.system`, `.zhHans`, `.en` (Settings toggle ready)
- **Hardcoded Chinese in Swift NOT in catalog:** ~474 — most are **code comments / log strings / debug** (verified by sampling). User-visible strings already routed through `String(localized:)`.

## Files containing Chinese

- 146 `.swift` files contain Chinese characters (mostly inline comments)
- 0 files have Chinese in filename
- 0 Chinese-named symbols (variables / functions / classes / structs)

## Info.plist permission strings (in Chinese — must translate)

| Key | Current (zh) |
|---|---|
| `NSCameraUsageDescription` | "SiteNote 用相机拍工地现场照片附在速记里，照片只存在你的手机上。" |
| `NSLocationWhenInUseUsageDescription` | "SiteNote 用位置在录音时关联当前工地，并发送坐标到 Open-Meteo 查询天气；不做后台追踪。" |
| `NSMicrophoneUsageDescription` | "SiteNote 用麦克风录下你的工地速记，录音文件只存在你的手机上。" |
| `NSPhotoLibraryAddUsageDescription` | "SiteNote 把巡检照片保存到你的相册以便分享。" |
| `NSSpeechRecognitionUsageDescription` | "SiteNote 把语音转成文字方便检索和导出，转写在设备本地完成。" |

## Crash reporting

- **In place:** Apple native MetricKit (`SiteNote/Services/CrashReporter.swift`)
- Writes diagnostics to `Library/Caches/_crash_reports/`
- No third-party SDKs (no Sentry / no Crashlytics) — clean for App Review

## Onboarding

- Existing 5-step `OnboardingView` (welcome / profile pick / first site / role-branched gesture / try-record)
- Dismiss key: `settings.onboarding.dismissed.v1`
- Needs: full English copy + permission-explanation framing per Apple HIG

## TODOs / FIXMEs / HACKs

- 2 occurrences total in Swift code (very clean)

## Known issues / risk factors

| Item | Risk |
|---|---|
| Source language of xcstrings = `zh-Hans` | App Store primary language will be `en`; we'll keep current key names but ensure 100 % en coverage. Optionally flip `sourceLanguage` to `en` if time. |
| 401 untranslated keys | Many are punctuation-only (`·`, `\|`, `*`) or format-only (`%@`, `%lld`). Real translation gap is much smaller. |
| In-app account deletion | Not present — Apple requires it (since June 2022). Must add. |
| Data export | Not present — required for GDPR / CCPA. Must add. |
| `PrivacyInfo.xcprivacy` (Privacy Manifest) | Not present — required since May 2024. Must add with NSPrivacyAccessedAPITypes for `UserDefaults`, file timestamps, disk space, system boot time. |
| Privacy Policy / ToS / EULA URLs | Not generated. Must author + provide manifoldx.com placeholders. |
| Demo account for Apple Reviewer | Not stipulated — write into review notes. |

## Feature surface (what reviewers will see)

- Voice-driven note capture with AI-assisted classification (omni-classify chain)
- Site-aware logging (GPS auto-detect nearest site, sub-tags, schedule deadlines)
- Photo capture + annotation + EXIF GPS watermark
- PDF export of inspection reports / daily site diary
- Team collaboration (CloudKit Sharing) — gated behind "Coming Soon" placeholder
- Two-role split: **Site Team** (foreman / PM) vs **Engineer** (consultant)
- Inspection session manager (start / continue / end / form-driven)
- Backup + iCloud sync + diagnostic packager

## What stays as-is (out of scope for v1 launch)

- AI engine choices (OpenAI client), CloudKit shipping schema, photo storage layout
- Entitlements, pbxproj capabilities / signing
- All MIC / Camera 132 pt circle button positions / sizes / colours (iron rule)
