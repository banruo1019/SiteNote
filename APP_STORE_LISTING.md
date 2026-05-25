# SiteNotes — App Store Connect Listing (v1.0.0)

Working doc for filling out App Store Connect metadata. All user-facing strings are plain text — copy/paste directly.

---

## 1. App Name (≤30 characters)

**Primary choice (30 chars):**

```
SiteNotes — Construction Log
```

Character count: 30 (the em dash `—` is 1 char). Captures the brand + the core "what is it" in one line; works in English-AU, EN-UK and EN-US search.

**Alternatives:**

- `SiteNotes: Site Diary & Logs` — 29 chars. Stronger if "site diary" is the dominant search term (UK/AU foremen).
- `SiteNotes — Daily Site Diary` — 28 chars. Leans into the PDF site-diary export as the headline feature.

---

## 2. Subtitle (≤30 characters)

**Primary choice (29 chars):**

```
Voice logs for jobsites
```

Wait — recount: `Voice logs for jobsites` is 23 chars. Padding for keyword reach:

```
Voice site log & PDF diary
```

Character count: 26. Names the input method (voice), the artefact (site log), the output (PDF diary). Differentiates from Procore/Raken on the first glance.

**Alternatives:**

- `Voice-first site diary app` — 26 chars. Plants "site diary" + "voice-first" as the wedge.
- `Talk it, log it, export it` — 26 chars. Rhythmic, memorable, hints at the three-step flow without naming features.

---

## 3. Promotional Text (≤170 characters)

**Option A (placeholder for week-of-launch, 158 chars):**

```
Just launched. Voice-first construction logs, on-device AI, offline-ready. Built for foremen and supervisors who never have a free hand. Try it free.
```

**Option B (feature-rotation friendly, 165 chars):**

```
New: dictate a site note in one tap, auto-sorted into hazards, completed work and daily diary. Export a PDF for head office in seconds. No account, no ads.
```

---

## 4. Description (≤4000 characters)

```
SiteNotes is the fastest way to keep a construction site log when your hands are full.

Long-press the mic, talk for ten seconds, and the app does the rest. No typing on a wet glove. No login. No monthly subscription.

Built for site supervisors, foremen, project managers, builders, sub-contractors and building inspectors who finish the day with a notebook full of scribbles and a phone full of photos — and still have to write the daily report before dinner.

WHY SITENOTES IS DIFFERENT

- Voice-first. One-handed capture, designed for a noisy jobsite and gloves.
- Works offline. The whole app runs without a connection. Sync later when you're back in coverage.
- On-device AI. Transcription and classification happen on your iPhone. Your notes don't leave the device unless you choose to export them.
- No account required. Nothing to sign up for, no team seats to buy, no servers holding your data hostage.
- Native iOS. Fast, ad-free, designed for the iPhone you already use on site.

WHAT IT DOES

- Auto-classifies each voice note into hazards, completed work and daily diary entries — so your week is already organised when you sit down to write the report.
- GPS auto-detects the nearest jobsite, so logs land on the right project without you tapping a thing.
- Attach photos inline, annotate them with arrows and notes, and pin them to a floor plan.
- Weather and site conditions are captured automatically with every entry.
- Schedule deadlines and inspections, with reminders that respect your calendar.
- Export a polished PDF site diary for the client, head office or the principal contractor in one tap.
- Optional team collaboration via Apple's CloudKit Sharing — head supervisors can assign sites to crew members, and member reports flow back to the head's device. No third-party server in the middle.
- iCloud sync uses your own Apple ID. Move between your iPhone and iPad without setting up another account.

HOW IT WORKS

1. Long-press the mic and dictate what you saw, did or flagged.
2. SiteNotes transcribes, classifies and stamps the entry with the jobsite, time and weather.
3. At the end of the day, week or job, export a PDF site diary in a couple of taps.

PRIVACY

SiteNotes runs on-device by default. Voice transcription, classification and storage all happen on your iPhone. There is no SiteNotes account, no analytics dashboard tracking your day, and no advertising network. If you turn on iCloud sync, your data syncs through your own iCloud account — we never see it.

BUILT FOR THE TRADES

Whether you're running a renovation, a commercial fit-out, a civil works site or a residential build, SiteNotes keeps your daily site diary organised without slowing you down. Designed alongside working foremen and PMs in Australia, the UK and the US.

Free in v1.0. Download it, take it on tomorrow's site walk, and see how much faster a day's worth of notes can be.
```

Character count (approx): 2,990 / 4,000. Comfortably under the cap with room to add future feature paragraphs without a rewrite.

English-AU spellings present: "organised", "colour" (none used — fine), "metre" (none used — fine), "centre" (none used — fine), "behaviour"-family (none used — fine). The variant deltas in this copy are "organised" (vs "organized"). Confirmed AU-safe — no US-only spellings.

Keyword coverage hit: site supervisors, foremen, project managers, builders, sub-contractors, building inspectors, daily site diary, jobsite, trade.

---

## 5. Keywords (≤100 characters total, comma-separated)

**Exact string to paste:**

```
foreman,builder,jobsite,daily,diary,report,trade,inspection,photo,progress,supervisor,worksite,PM
```

Character count: 99 / 100.

**Why each one (and what's deliberately omitted):**

- `foreman` — high-intent role search, not in the app name.
- `builder` — covers residential builders / small contractors.
- `jobsite` — common US search; complements "site" in the name.
- `daily` — pairs with "diary" and "report" via Apple's tokeniser.
- `diary` — the artefact a UK/AU foreman searches for.
- `report` — head-office / client-facing intent.
- `trade` — pulls in tradespeople / subbies.
- `inspection` — building inspectors are a named target audience.
- `photo` — photo-based logging is a feature wedge.
- `progress` — "progress report", "progress photo" combos.
- `supervisor` — site supervisor as a role.
- `worksite` — AU/UK variant of jobsite; broadens coverage.
- `PM` — project manager shorthand, cheap at 2 chars.

**Deliberately NOT included (because they're already in the app name or subtitle, and Apple ranks both fields independently — duplicating wastes characters):**

- `construction` (in app name)
- `site` (in app name)
- `log` (in app name)
- `voice` (in subtitle)
- `PDF` (in subtitle)
- `SiteNotes` (in app name — Apple auto-indexes the brand)

---

## 6. Category

- **Primary: Business**
- **Secondary: Productivity**

Rationale: Procore, Raken, Fieldwire, Buildertrend and Plangrid all sit in Business as their primary, which is where construction-software buyers browse. Productivity is the right secondary because the user-level value prop (voice notes, daily diary, PDF export) maps to a productivity tool more than to a vertical SaaS suite. Apple weights primary category heavily in search ranking, so leading with Business puts SiteNotes in front of the right competitive set.

---

## 7. What's New in This Version (≤4000 characters)

```
First release.

SiteNotes is now live for site supervisors, foremen, PMs, builders and inspectors who want a voice-first daily site diary that runs offline, keeps everything on-device, and exports a PDF in two taps.

Highlights in v1.0:
- One-tap voice capture with on-device AI classification.
- GPS auto-detects your nearest jobsite.
- Inline photos, annotations and floor-plan pins.
- Weather and site conditions stamped on every entry.
- PDF site diary export for head office or the client.
- iCloud sync with your own Apple ID. No SiteNotes account, no ads, free.

Thanks for taking it on site. Feedback welcome at the support link.
```

Word count: ~110 words. Character count: ~720 / 4,000.

---

## 8. URLs

| Field | URL |
| --- | --- |
| Support URL | `https://banruo1019.github.io/SiteNote/support/` |
| Marketing URL | `https://banruo1019.github.io/SiteNote/` |
| Privacy Policy URL | `https://banruo1019.github.io/SiteNote/privacy/` |

Apple requires the Support URL and Privacy Policy URL to resolve before review. Confirm all three return a 200 before you hit Submit.

---

## 9. Copyright

```
© 2026 Banruo Yang
```

Paste exactly as shown. Apple accepts the © symbol directly.

---

## 10. Trade Representative Contact Information (Korea)

**Skip this section.** It is only required if you elect to distribute in South Korea under the local Trade Representative regime. For an initial AU/UK/US-focused launch, leave the toggle off and the fields blank. You can revisit it later if you add Korea to the territory list.

---

## Submission checklist (quick sanity pass before hitting Submit)

- [ ] App Name copied in (30 chars, no trailing whitespace)
- [ ] Subtitle copied in (26 chars)
- [ ] Promotional Text copied in (≤170 chars)
- [ ] Description pasted, en-AU spellings preserved
- [ ] Keywords pasted as a single comma-separated string, no spaces, 99 chars
- [ ] Category: Business / Productivity
- [ ] What's New for v1.0 pasted
- [ ] Three URLs resolve to a 200
- [ ] Copyright reads `© 2026 Banruo Yang`
- [ ] Korea trade rep toggle: off
- [ ] Screenshots uploaded for 6.7", 6.5" and 5.5" iPhone (Apple's required sizes)
- [ ] App Privacy questionnaire completed (declare on-device processing, iCloud usage)
- [ ] Age rating questionnaire completed (expect 4+)
- [ ] Build 2 selected from the TestFlight builds list
