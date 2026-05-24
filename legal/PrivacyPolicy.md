# SiteNotes Privacy Policy

**Effective date:** 2026-05-23
**Last updated:** 2026-05-23

SiteNotes is an iOS app for construction site logging, made by Banruo Yang in New South Wales, Australia. We built it so you can capture notes, photos, and voice memos on site without sending your work to a server we control. This policy explains, in plain English, what the app does with your data, what it does not do, and the rights you have.

If you only read one thing: **we do not operate servers that hold your SiteNotes data.** Your notes, photos, and voice recordings stay on your device and in your own iCloud account. We cannot read them.

---

## 1. Who we are

- **App:** SiteNotes (iOS)
- **Operator:** Banruo Yang, New South Wales, Australia
- **Contact for privacy questions:** banruostudio@gmail.com

Banruo Yang is the data controller (GDPR) and the responsible business (CCPA) for the limited interactions described below. We are an Australian operator and the app is subject to the Australian Privacy Act 1988 and the Australian Privacy Principles (APPs).

---

## 2. The short version

| Category | What happens |
|---|---|
| Accounts / logins | None. SiteNotes has no sign-up. |
| Photos | Camera photos stay on your device and in your iCloud. |
| Voice recordings | Microphone audio stays on your device and in your iCloud. Transcription runs on-device. |
| Location | One single fix per recording, used locally to detect which site you are on and to look up weather. Never tracked in the background. |
| Crash diagnostics | Collected by Apple's MetricKit, stored only on your device, never auto-uploaded. |
| Advertising IDs / contacts / browsing history | We never collect any of these. |
| Third parties | Open-Meteo (weather only, no personal data). Apple iCloud (storage you already own). |

---

## 3. What data we collect

### 3.1 Account and identity data

**None.** SiteNotes has no account system. There is nothing to sign up for, no password to set, no email to verify. The app uses the Apple ID already on your iPhone to sync your data through iCloud, but Banruo Yang never sees that Apple ID.

### 3.2 Photos (camera)

When you take a photo inside SiteNotes, the image is written to the app's private storage on your device and, if iCloud sync is enabled, mirrored into your private CloudKit container (which lives inside your Apple ID's iCloud account). We do not upload photos anywhere else. We do not run image recognition on a server. We cannot view your photos.

### 3.3 Voice recordings (microphone)

The long-press microphone button records short voice notes used to capture observations on site. The audio file is written to your device. Speech-to-text runs **on-device** using Apple's speech framework, so the audio does not leave your phone for transcription. The resulting text is saved alongside the recording. As with photos, voice files are mirrored to your iCloud if sync is on.

### 3.4 Location data

When you create a recording, SiteNotes takes **one** location fix at that moment if you have granted "While Using the App" permission. The coordinates are used for two purposes:

1. **Site auto-detection** — comparing the fix against your locally stored site centroids so the app can pre-fill the right project. This comparison happens entirely on-device.
2. **Weather lookup** — the latitude and longitude are sent to Open-Meteo so the app can attach the weather conditions to your log entry.

SiteNotes does **not** run any background location tracking, geofencing, or continuous monitoring. There is no location history sent to us.

### 3.5 Crash and performance diagnostics

iOS itself collects crash reports and performance metrics through Apple's MetricKit framework. SiteNotes reads these on-device so you can see them in the diagnostics screen and, if you choose, attach them to a feedback email. They are **not** uploaded automatically. If a crash log ever reaches us, it is because you explicitly tapped the share button and sent it from your own Mail app.

### 3.6 Data we never collect

For the avoidance of doubt, SiteNotes does not collect any of the following:

- Device advertising identifier (IDFA)
- Contact list, calendars, or reminders
- Web browsing history
- Health, fitness, or sensor data
- Microphone audio outside an explicit recording
- Background location
- Files outside the app's own sandbox

---

## 4. Why we collect each category

| Data | Purpose | Lawful basis (GDPR) |
|---|---|---|
| Photos | Visual record of site conditions, defects, inspections. | Consent (you explicitly take the photo). |
| Voice recordings + transcripts | Hands-free note capture on site. | Consent (you press and hold the mic). |
| Location (single fix) | Auto-detect which site you are on; fetch weather. | Legitimate interest in producing useful logs; consent via iOS permission prompt. |
| Crash diagnostics | Help you debug crashes and let you send them to us if you want help. | Legitimate interest. |

We do not use any of this data for advertising, profiling, or training third-party models.

---

## 5. Third parties

We try very hard to keep the list of third parties as short as possible.

### 5.1 Open-Meteo

When you create a log entry with location, SiteNotes sends just the latitude and longitude (and an optional timestamp) to Open-Meteo's public weather API to fetch conditions. Open-Meteo does not require an account and we do not send your identity, your Apple ID, or any user content. Their privacy policy is at https://open-meteo.com/en/terms.

### 5.2 Apple iCloud

iCloud sync (including CloudKit Sharing, used by the team feature) is provided by Apple under your Apple ID. Your data is stored in the Apple data centre region tied to your Apple ID. Apple's privacy policy governs that storage. Banruo Yang has no access to your iCloud container.

That is the entire third-party list. No analytics SDK, no advertising network, no crash reporting service, no customer-support chatbot.

---

## 6. Where your data is stored

- **Your device.** Notes, photos, voice files, and templates live in the SiteNotes sandbox on your iPhone or iPad, protected by iOS file protection.
- **Your iCloud.** If iCloud sync is on, the same data is mirrored into a private CloudKit container under your Apple ID. The region is whatever region Apple assigns to your account.
- **Banruo Yang servers:** none. We do not run a backend that holds your project data. We do not replicate, back up, or cache your data on any infrastructure we control.

When you share a site with a teammate, SiteNotes uses Apple's CloudKit Sharing. The share happens directly between your iCloud account and theirs via Apple's infrastructure. Banruo Yang is not in the middle.

---

## 7. How long we keep it

Because the data lives on your device and in your iCloud, the retention period is entirely under your control:

- Notes, photos, and voice files stay until **you** delete them.
- Items in the in-app Trash are kept for the duration the app shows (currently 30 days) before being purged.
- We have **no server-side retention**, because there is no server.

If you uninstall SiteNotes, the on-device data is removed by iOS. The iCloud zone may remain until you wipe it from Settings (see below).

---

## 8. Your rights

You have meaningful, immediate control inside the app.

- **Right to access** — open SiteNotes; everything we have about you is visible there. There is no hidden profile.
- **Right to export / portability** — Settings → Export produces a ZIP archive containing your notes (Markdown / JSON), photos, and voice files.
- **Right to correct** — edit any entry directly in the app.
- **Right to delete** — Settings → Erase All Content wipes both local storage and the iCloud zone we created. This is irreversible.
- **Right to withdraw consent** — revoke camera, microphone, or location permission in iOS Settings → SiteNotes at any time. The app keeps working with reduced features.

If you live in a jurisdiction with extra rights (GDPR, CCPA, Australian Privacy Act), you may exercise those rights against Banruo Yang by emailing **banruostudio@gmail.com**. Because we do not hold your content, in most cases the answer to "what do you have on me?" will literally be "nothing." We will respond within 30 days.

You also have the right to lodge a complaint with a supervisory authority — for example the Office of the Australian Information Commissioner (oaic.gov.au), your EU member-state data protection authority, or the California Privacy Protection Agency.

---

## 9. Children's privacy

SiteNotes is a tool for construction professionals. It is not directed at children under 13 and we do not knowingly collect personal information from them. If a parent or guardian believes a child has used the app, they can wipe all data via Settings → Erase All Content. Because we do not operate servers, there is nothing for us to delete on our side.

---

## 10. Data security

Security comes from the platforms underneath SiteNotes rather than from us trying to roll our own:

- **iOS file protection** encrypts the app sandbox while your device is locked.
- **iCloud at-rest encryption** is managed by Apple for the CloudKit container.
- **In-transit encryption** (HTTPS / TLS) is used for the only outbound network call we make — the weather lookup to Open-Meteo.
- We hold no credentials and operate no servers, which removes a large class of breach risk.

No system is perfectly secure. If you discover a vulnerability, please email banruostudio@gmail.com.

---

## 11. GDPR (European Economic Area and UK users)

If you are in the EEA or UK:

- **Controller:** Banruo Yang, NSW, Australia. Contact: banruostudio@gmail.com.
- **Lawful basis:** consent (camera, microphone, location — given via the iOS permission prompts) and legitimate interest (running the app and diagnostic features).
- **Data transfers:** any data that leaves your device goes either to your own Apple iCloud (governed by Apple's transfer safeguards) or to Open-Meteo as raw weather coordinates with no personal data attached.
- **EU representative:** SiteNotes is not offered at scale in the EU and Banruo Yang is not required to appoint an Article 27 representative. We still accept GDPR rights requests at banruostudio@gmail.com as a courtesy.
- You have the right to access, rectify, erase, restrict, port, and object to processing, and to lodge a complaint with your local supervisory authority.

---

## 12. CCPA / CPRA (California users)

If you are a California resident:

- **Categories of personal information collected:** none on our servers. The categories handled on-device only are listed in Section 3.
- **Right to know:** since we hold no personal information, requests will receive a confirmation of that fact within 45 days.
- **Right to delete:** use Settings → Erase All Content in the app. Email us if you need a written confirmation.
- **Right to correct:** edit entries directly in the app.
- **Right to non-discrimination:** we will never penalise you for exercising these rights — there is no paid tier that depends on giving up data.
- **Sale or sharing of personal information:** **we do not sell or share personal information**, as those terms are defined under the CCPA / CPRA. We do not run cross-context behavioural advertising.

You can submit a verified request to banruostudio@gmail.com.

---

## 13. Australian Privacy Act 1988

Banruo Yang is an Australian operator and complies with the Australian Privacy Principles (APPs):

- **APP 1 — open and transparent management:** this policy is our public statement and is also linked from inside the app.
- **APP 3 — collection of solicited personal information:** we collect only what is described in Section 3, and only via clear in-app actions.
- **APP 5 — notification of collection:** the iOS permission prompts and this policy together notify you at the point of collection.
- **APP 6 — use and disclosure:** we use data only for the purposes in Section 4 and we do not disclose it to anyone other than Open-Meteo (de-identified coordinates) and Apple iCloud (your own account).
- **APP 8 — cross-border disclosure:** Open-Meteo is operated outside Australia; we send only coordinates, which are not personal information without context.
- **APP 11 — security of personal information:** see Section 10.
- **APP 12 / 13 — access and correction:** handled in-app, as described in Section 8.

You may complain to the Office of the Australian Information Commissioner (OAIC) at oaic.gov.au.

---

## 14. Changes to this policy

If we change anything material, we will:

1. Update the "Last updated" date at the top of this document.
2. Show an in-app banner on the next launch of SiteNotes summarising what changed.
3. Keep the previous wording available on request at banruostudio@gmail.com.

Trivial typo fixes will just bump the date.

---

## 15. Contact

**Banruo Yang**
NSW, Australia
banruostudio@gmail.com

For App Store policy questions, you can also use Apple's report-a-concern flow on the SiteNotes App Store listing.

---

*Thanks for reading. We genuinely believe a privacy policy you can finish in five minutes is a better contract than one you cannot.*
