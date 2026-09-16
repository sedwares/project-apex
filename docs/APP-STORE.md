# Project Apex — App Store submission pack

Prepared 2026-09-15 for version 1.0. Everything here is ready to paste into
App Store Connect. Character counts are given where Apple enforces a limit.

---

## 1. The listing fields

**App Name** (30 max) — 27 characters

```
Project Apex: Race Engineer
```

**Subtitle** (30 max) — 25 characters

```
One setup a day. No luck.
```

Alternates if you want a different angle: `The daily race-setup puzzle` (27),
`Engineer the car. Not the luck.` — too long at 31, `Build the car. Beat the day.` (28).

**Promotional text** (170 max) — 162 characters. This field can be changed any
time without a review, so use it for launch messaging later.

```
Every engineer gets the same circuit, the same weather, the same budget — every day. Eight decisions, one submission, zero randomness. New challenge at midnight UTC.
```

**Keywords** (100 max, comma-separated, no spaces after commas) — 99 characters

```
motorsport,racing,daily,puzzle,strategy,tuning,pitwall,laptime,grid,sim,brainteaser,leaderboard,car
```

Do not repeat words already in the name or subtitle — Apple indexes those
fields separately, so `apex`, `race`, `engineer`, `setup`, `day` and `luck`
would be wasted characters here.

A higher-traffic variant swaps two terms for `f1,formula`:

```
f1,formula,motorsport,daily,puzzle,strategy,tuning,pitwall,laptime,grid,sim,brainteaser,leaderboard
```

That is 98 characters and would pull real search volume, but both are
registered trademarks of Formula One Licensing BV, and Apple does reject
keyword fields that use third-party marks. The first list is the safe one. If
you want the traffic, ship 1.0 with the safe list and test the other in a
1.0.1 — a keyword rejection on your first submission costs you a review cycle.

**Description** (4000 max) — 1,847 characters

```
You are the Chief Engineer. You do not drive the car — you design it.

Every day, every engineer in the world gets the same circuit, the same weather, and the same budget. Eight engineering decisions. One submission. No undo.

Then the car runs three laps, and the numbers tell you exactly what your choices were worth.

THE DAILY ASSIGNMENT
A new circuit at midnight UTC, with its own weather and its own credit budget. Most days the stewards outlaw one component, and you have to build around the ban. Choose across eight systems — engine mode, tires, aerodynamics, suspension, gear ratio, cooling, brakes and reliability — then lock it in and live with it.

NO LUCK. NONE.
The simulation is fixed-point and fully deterministic. The same setup produces the same lap time on any device, forever. There is no dice roll hiding behind a bad result. If you were slow, you were wrong, and the debrief will show you where.

THE DEBRIEF
Your lap, sector by sector, measured against the fastest legal setup that existed that day — found by solving every one of the thousands of legal combinations. See exactly how much time each sector cost you, what percentage of possible setups you beat, and what your Chief Engineer would change next time.

LEARN, THEN PROVE IT
Experiment replays today's exact conditions with a different setup as many times as you like, and never touches your official result. Quick Race throws you a surprise circuit. Test Lab lets you pick the circuit, weather and budget yourself.

COMPETE
A global leaderboard each day. Everyone's setups stay sealed until the day closes, so nobody can copy the leader's answer while the race is still on. Build a streak by submitting on consecutive days.

No ads. No in-app purchases. No accounts to create.

There is no option without a cost. That is the game.
```

---

## 2. Required URLs

| Field | Value | Status |
|---|---|---|
| Privacy Policy URL | `https://sedwares.github.io/project-apex/` | hosted from `docs/` on `pass6-launch` |
| Support URL | `https://sedwares.github.io/project-apex/` | same page — it carries the contact address |
| Marketing URL | Optional — leave blank for 1.0 | — |

Apple requires the support URL to be a working web page. An `mailto:` link is
not accepted.

---

## 3. Privacy policy — the one real blocker

**The policy you have is wrong and cannot be published as-is.** The copy dated
31 July 2026 states "No analytics or behavioral tracking," which stopped being
true when Firebase Analytics and Crashlytics shipped. It also tells users to
email you for deletion (there has been an in-app control since the 5.1.1(v)
work) and says other players can see your setup (the rules seal it until the
day closes). Publishing it would put a false privacy claim in front of users
and contradict the nutrition labels you are about to file.

A corrected version is now in your repo at `docs/index.html`, styled in the
app's livery and self-contained. It discloses Crashlytics and Analytics
accurately, describes the sealed-setups behaviour correctly, documents the
in-app deletion including the `ENG-DELETED` tombstone and why rows are kept,
and covers the IP-derived coarse location.

To host it, from the repo root:

```
git remote add origin https://github.com/<you>/project-apex.git
git push -u origin pass6-launch
```

Then on GitHub: Settings → Pages → Source: *Deploy from a branch* → branch
`main` (merge first) → folder `/docs`. The policy is live at
`https://<you>.github.io/project-apex/` within a minute or two.

If the repo is private, Pages needs a paid plan — in that case make a second,
public repo containing only `docs/index.html`.

---

## 4. App Privacy answers

These were reconciled in August against the archive's own App Privacy Report
and match `PrivacyInfo.xcprivacy` exactly. **Every row: "Used for tracking" =
No.**

| App Store Connect category | Data type | Linked to user | Purpose |
|---|---|---|---|
| Identifiers | User ID | **Yes** | App Functionality |
| User Content | Gameplay Content | **Yes** | App Functionality |
| Diagnostics | Crash Data | **Yes** | App Functionality |
| Usage Data | Product Interaction | **Yes** | Analytics + App Functionality |
| Identifiers | Device ID | No | Analytics |
| Location | Coarse Location | No | Analytics |
| Usage Data | Other Usage Data | No | App Functionality |
| Diagnostics | Other Diagnostic Data | No | App Functionality |

Two of these look wrong and are not. **Coarse Location** is declared even
though the app never touches Location Services — Analytics derives an
approximate region from the masked IP, and Apple counts that. **Gameplay
Content** is the easiest to forget because it does not feel like "data": it is
your eight selections, the cost and the lap times.

**Account deletion question:** answer **Yes**. Path: Settings → *Delete my
engineer*.

---

## 5. Screenshots

iPhone-only app, so **no iPad screenshots are required**. Supply the 6.9-inch
set and Apple scales it for smaller devices.

- **Size:** 1320 × 2868 px portrait (also accepted: 1290 × 2796, 1260 × 2736)
- **Count:** 1–10; upload 5 or 6
- **Format:** PNG or JPG, no alpha, no rounded corners or device frames applied
  by you
- **Capture on:** iPhone 16 Pro Max / 17 Pro Max simulator at Retina scale

Order matters more than polish — most people never swipe past the third.

1. **The debrief, sector chart visible.** Your strongest asset. The purple
   "AHEAD −0.123s" row against the red losses sells the whole premise in one
   glance. Lead with it, not the bay.
2. **The Engineering Bay mid-build**, budget bar showing a live total and a
   couple of options selected. This is what the game *is*.
3. **The daily brief** — big day number, circuit, weather, and the red
   regulation banner. Communicates "new one every day" instantly.
4. **The Chief Engineer's report** with the "next test" recommendation. Shows
   the game teaches rather than just scores.
5. **Global standing / leaderboard.** Wait until you have more than two
   entries — "Rank #1 of 2" reads as an empty game.
6. *(optional)* Quick Race or Test Lab, to signal there is more than one
   puzzle a day.

Add a short caption band at the top of each if you can — "Eight decisions, one
budget", "See exactly where the lap went". Screenshots with a line of text
convert meaningfully better than bare captures.

---

## 6. Age rating

Answer **No** to every content question. Expected result: **4+**.

No violence, no simulated gambling (a deterministic sim with no wagering is not
gambling), no user-generated content, no chat, no unrestricted web access, no
purchases. Callsigns are auto-assigned, which is what keeps you out of the
user-generated-content questions.

---

## 7. App Review notes

Paste into the *Notes* field. Reviewers reject deletion flows they cannot find.

```
No login required — the app creates an anonymous Firebase account on first
launch and assigns a callsign automatically. There is no sign-in screen and no
demo account is needed.

Account deletion (guideline 5.1.1(v)): Settings (gear icon, top left of the
home screen) → "Delete my engineer". This deletes the player profile, all
submitted setups, local history, and the anonymous auth user. Past leaderboard
rows are retained with the callsign replaced by "ENG-DELETED", because each row
is the record of a daily competition other players took part in and deleting
one would re-rank every player who finished behind it. No personal data remains
on a retained row.

The app requires a network connection to fetch the daily challenge. Challenges
are published in advance; if the reviewer sees "Paddock unreachable" please
contact us, as it indicates a backend issue rather than app behaviour.

Notification permission is requested only after a third completed day, so it
will not appear during a short review session.
```

---

## 8. Before you hit Submit

- [ ] **Deploy the Cloud Functions** — `firebase deploy --only functions`.
      Without this, "Delete my engineer" queues a request nothing drains, which
      is a direct 5.1.1(v) rejection. Verify by deleting a throwaway account
      and confirming the row reads `ENG-DELETED`.
- [ ] **Check the publish buffer.** The last published day is the day the game
      stops working. Publish well past your launch window — a review cycle plus
      launch week is easily a month, and nobody is watching the buffer while
      you are busy.
- [x] **Host the privacy policy and support page.** Both are
      `https://sedwares.github.io/project-apex/`, served by GitHub Pages
      from `docs/` on `pass6-launch`. Linked in-app from Settings →
      Privacy since build 23 (`AppLinks.privacyPolicy`).
- [ ] **Merge `pass6-launch` into `main`.**
- [ ] **One midnight-UTC rollover on TestFlight** (8pm your local) with a second
      tester — the streak rollover, the yesterday-reveal card and a leaderboard
      above n=1 have never been observed working.
- [ ] Screenshots captured, with the leaderboard shot taken once the board has
      real entries.
