# Pitch run-sheet

One page for the person driving the demo. Script and objection answers are in
the project specification (section 15); this is the operational checklist.

## Which link

| Use | Link | Why |
|---|---|---|
| **The pitch** | https://fastrack.name.ng/demo/ | Offline demo build: runs on the device once loaded, has **Reset demo** and the one-tap **sample ID**. Nothing a rehearsal does reaches the real queue. |
| **A live pilot / showing the real backend** | https://fastrack.name.ng/app/ | Real backend on Neon. No Reset demo and no sample ID: have a photo of an ID on the device, and register a fresh email for each walk (every walk adds a file to the officer queue). |

The steps below use the demo link.

## The night before

- [ ] Open the hosted web app on the pitch laptop and the Android phone once, so assets are cached.
- [ ] **Reset demo** (link under the splash buttons, or the ↺ icon on the officer queue). Queue should show exactly Adaeze, Ibrahim, Northshore.
- [ ] Walk Adaeze end to end once. A9 must read **Up to NGN 1,240,000 · Elevated review**; O2 must read **NGN 1,240,000 · Medium risk**.
- [ ] Reset demo again.
- [ ] Browser zoom 100 %, display 1366×768 (or the room's HDMI resolution). Close other tabs.
- [ ] The 90-second backup recording ([`docs/assets/fasttrack-demo.mp4`](assets/fasttrack-demo.mp4): Adaeze A1 → A9, officer approves, A10 shows Approved) is on the laptop desktop, playable offline.

## 15 minutes before

- [ ] Open the app in two tabs: applicant at `/demo/`, officer at `/demo/#/officer/login` (`officer@fasttrack.demo` / `FastTrack!demo1`). The first load takes a few seconds — do it now, not in front of the client.
- [ ] Put the client's own "Open an Account" / "Secure a Loan" page in a third tab.

## During the walk (A2 → A9, under five minutes)

| Screen | Tap | Say |
|---|---|---|
| A2 | Individual | "Individual or company — two tracks, one flow." |
| A3 | Register any email, 8+ character password | |
| A4 | Fill details (or keep it short: name, DOB, phone, address, occupation, next of kin, purpose) | "This replaces the PDF account form." |
| A5 | *Adaeze O.* sample → Verify | Point at the amber chip: "Sandbox identity data. Going live means a verification-provider contract." |
| A6 | *Use sample ID* (live link: upload an ID photo) → *Adaeze O.* sample alerts | "Most clients have bank-alert SMS, not a PDF." |
| A7 | Sign, tick, Submit | |
| A8 | — | "Identity, statement, scoring — three honest steps." |
| A9 | Scroll to the disclaimer | "A pre-qualification, not an offer. A specialist decides." |
| O2 | Switch tab → open the top file → read two sentences → add a note → Approve | "Same number. A human still signs." |
| A10 | Switch back → refresh | Status shows **Approved**. |

Then 30 seconds on **Ibrahim** (High risk, NGN 410,000 — "we don't fake an approval") and, if time allows, **Northshore** (corporate path).

## If something goes wrong

- **Page refreshed by accident** — nothing is lost; the demo resumes where it was.
- **Wrong data on screen** — Reset demo, start the walk again (≈ 3 minutes).
- **No network at all** — the demo link still works once loaded; if it never loaded, play the recording.
- **Live link answers slowly the first time** — the backend wakes from idle in a few seconds. Open it once 15 minutes before.

## Say it before they ask

- Identity checks are sandbox; production needs a licensed KYC provider (a per-lookup cost).
- The AI reads the statement; **the firm's rules set the amount**; a person approves.
- This is the front door and the first read — not core banking, disbursement or a credit bureau.
