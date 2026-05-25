# App Privacy — App Store Connect Questionnaire Answers

Authoritative source for filling the **App Privacy** section of App Store Connect for SiteNotes v1.0.

**Apple's framing:** "Does your app collect any data?" — *collect* means transmitted off your device and linked back to a user.

---

## Top-level answer

> **Data Used to Track You:** None
> **Data Linked to You:** None
> **Data Not Linked to You:** Coarse Location *(Open-Meteo weather lookup — see below)*

---

## Question 1 — Does your app collect data?

**Yes**, but minimally — coordinates are sent to Open-Meteo (third-party weather API, no login) so the user can attach weather to a recording. No identifier is sent with the coordinates.

---

## Question 2 — Data types collected

| Category | Data Type | Collected? | Linked to user? | Used for tracking? | Purposes |
|---|---|---|---|---|---|
| **Contact info** | Email / phone / etc. | ❌ No | — | — | — |
| **Health & Fitness** | All | ❌ No | — | — | — |
| **Financial info** | All | ❌ No | — | — | — |
| **Location** | Precise location | ✅ Yes (Open-Meteo) | **No** | No | App Functionality |
| **Location** | Coarse location | ❌ No | — | — | — |
| **Sensitive info** | All | ❌ No | — | — | — |
| **Contacts** | Address book | ❌ No | — | — | — |
| **User content** | Photos / videos | ❌ No collection (stays on device + user's iCloud) | — | — | — |
| **User content** | Audio recordings | ❌ No collection (stays on device + user's iCloud) | — | — | — |
| **User content** | Other user content (notes) | ❌ No collection (stays on device + user's iCloud) | — | — | — |
| **Browsing history** | All | ❌ No | — | — | — |
| **Search history** | All | ❌ No | — | — | — |
| **Identifiers** | User ID / device ID / IDFA | ❌ No | — | — | — |
| **Purchases** | All | ❌ No | — | — | — |
| **Usage data** | Product interaction / advertising data | ❌ No | — | — | — |
| **Diagnostics** | Crash data / performance data | ❌ No collection (MetricKit stays on device; only sent if the user manually emails a diagnostic bundle via Settings → Feedback) | — | — | — |
| **Other** | All | ❌ No | — | — | — |

---

## Question 3 — For each "Yes", the purposes

### Precise Location → App Functionality

- Used for: attaching weather to a recording (one-shot reverse-geocoded location → coordinates → Open-Meteo).
- **Linked to user:** No. Coordinates leave the device standalone — no account identifier, no IDFA, no device ID.
- **Used to track user:** No.
- **Optional?:** Yes. Permission is requested at first attempt; users can decline. The rest of the app works without it.

---

## Question 4 — Third parties

| Third party | Data shared | Why | Their terms |
|---|---|---|---|
| **Open-Meteo** | Coordinates (no identifier) | Weather for log entries | open-meteo.com (free, no login) |
| **Apple iCloud / CloudKit** | All your SiteNotes content (only to YOUR iCloud) | Cross-device sync | Apple's terms apply |

We do not embed any analytics, A/B testing, attribution, advertising, or session-replay SDKs.

---

## Question 5 — Tracking

- **Does the app track users across other apps and websites?** **No.**
- **Tracking domains:** none. (`NSPrivacyTrackingDomains` is an empty array in `PrivacyInfo.xcprivacy`.)

---

## Notes for the App Privacy filler

1. When asked *"Do you collect Crash Data?"* → **No**. MetricKit stays on device. Crash logs are only ever transmitted if the user manually emails them.
2. When asked *"Do you collect Photos or Videos?"* → **No**. They live in on-device storage + the user's own iCloud (Apple's own privacy applies to iCloud).
3. When asked *"Do you collect Audio Data?"* → **No**, same reason as photos.
4. When asked *"Do you collect User Content (text)?"* → **No**, same reason.
5. The "Linked to user" question is interpreted by Apple as "linked to a real-world identity (account, IDFA, email)". Location data we send to Open-Meteo is NOT linked because there is no account identifier in the request.

This document is the single source of truth for the App Privacy questionnaire — if anything changes, update it AND `PrivacyInfo.xcprivacy` together.
