# HazardRadar AI: why every screen, action, and scenario behaves the way it does

Written from the source code in `lib/`, `firestore.rules`, and `proxy/`. Last updated 21 Nov 2026, after commit `70fca15`.
Each entry has three parts: **What you see**, **Why it happens** (the mechanism, with the file that does it), and **If it looks broken** (the usual cause). Use the last part when you report a bug.

Section 17 lists what changed during the 20 Nov testing session. Read it first if you tested an older build.

Contents
1. Before you start: the moving parts
2. Launch: splash, sign-in, profile
3. The app frame: top bar, bottom tabs, Report button
4. Radar tab (map)
5. Hazard sheet (tap a pin)
6. Report wizard (4 steps)
7. Ask Radar AI (chat)
8. Safe walking route
9. My Reports tab
10. Settings tab
11. Account sheet (Google upgrade)
12. Dispatch tab (staff only)
13. Rules that apply everywhere (limits, levels, points, blocks)
14. Scenario table: "I did X and Y happened"
15. Things in the code that look like quirks (check these first when testing)
16. Colors, messages, and light/dark mode
17. Change log: what was fixed on 20 and 21 Nov 2026

---

## 1. Before you start: the moving parts

The app talks to three outside systems. Most "it does not work" reports trace back to one of them.

| Part | What it does | What breaks when it is missing |
|---|---|---|
| **Firebase Auth** | Gives every phone an anonymous user id (uid) on first launch. Google sign-in links that uid to a Google account. | App cannot start. You see "Could not connect. Check your network and try again." |
| **Firestore + `firestore.rules`** | Stores incidents, votes, profiles. The rules are the real enforcer of limits, levels, points, roles. | Reads or writes fail with "permission denied" if the rules are not published, or an index is missing. |
| **Proxy (`proxy/`, port 3000)** | Holds the Groq key. Does AI triage (`/triage`), Radar AI chat (`/chat`), and the safe route (`/detour`). It checks your Firebase ID token. | Triage falls back to the offline keyword classifier. Chat says "Radar AI is not reachable". Route says "The route service is not reachable". |

Why the proxy exists: the app must never contain the Groq API key, so the phone asks the proxy, and the proxy asks Groq. On a real phone over USB the proxy is reached through `adb reverse tcp:3000 tcp:3000`, which makes `localhost:3000` on the phone point to your PC. If you skip that command the phone cannot reach it.

**The adb link drops often.** Unplugging the cable, the phone sleeping or reconnecting, or adb restarting all clear it. Then the phone says "The route service is not reachable" or "Radar AI is not reachable" while web still works, because the browser runs on the laptop itself. Check with `adb reverse --list`. An empty list means you need to run the reverse command again.

**Firestore indexes.** The map and My Reports run queries that need composite indexes (listed in `firestore.indexes.json`). Without them Firestore answers `failed-precondition: The query requires an index`, and the screen shows a red "Could not load..." message. On 20 Nov the map showed only your own reports for this reason. Both indexes are now created in the console (**Firestore Database > Indexes > Composite**).

**Rules after code changes.** Publishing new code does not update Firebase. When `firestore.rules` changes (it did on 20 Nov, for profile photos), paste it into **Firestore Database > Rules** and click **Publish**. A greyed-out Publish button means the console already has the same text.

Why the Ask Radar AI and Safe route buttons can be missing: `main.dart` builds the chat and detour services only when `PROXY_URL` in `dart_defines.json` parses to a valid URL. No URL means no proxy client, and the UI hides both buttons.

---

## 2. Launch

### 2.1 Splash screen
**What you see:** a photo background (or a flat sage panel if the photo asset is missing), the title "HazardRadar AI" in a serif font, and the line "See the risk before you walk into it." It fades in, stays about 2.5 seconds, then fades into the app over 0.6 seconds.

**Why:** `SplashScreen` starts a 2,500 ms timer, then calls `pushReplacement` with a fade transition to `HomeScreen`. The dark overlay is a flat 45% black box so the cream text stays readable (no gradient, matching the flat design rule).

**If it looks broken:** a sage background with no photo means `assets/images/splash.jpg` is missing or not listed in `pubspec.yaml`. That is allowed by design (`errorBuilder`).

### 2.2 Loading spinner right after the splash
**What you see:** a red-orange spinner on a cream screen, for about a second or more.

**Why:** `HomeScreen` runs `session.start()`: it signs in anonymously (or reuses the existing user), loads or creates `users/{uid}`, and, if you earned a level with points, applies it. The spinner shows until that future finishes. At the same time it starts `enrichPending`, which quietly re-sends your earlier offline-classified reports to the AI.

### 2.3 "Could not connect. Check your network and try again."
**What you see:** that sentence in a red-orange block, a Retry button, and (debug builds only) the real error text underneath in monospace.

**Why:** `session.start()` threw: no internet, Firebase Auth blocked, anonymous sign-in not enabled in the console, or the profile read/create was denied by the rules. Debug builds print the exact exception (`kDebugMode`); release builds hide it on purpose so users do not see technical text.

**If it looks broken:** copy the debug line and send it to me. Pulling down on this screen also retries.

### 2.4 First run only: permission prompts
**What you see:** a location permission dialog when the map first opens. A camera permission dialog appears the first time you tap the photo box in the report wizard.

**Why:** the map calls `_locate()` in `initState`. `GeolocatorLocationService` checks that the phone's location switch is on, then asks for permission if it is `denied`. The follow-up GPS stream (for the nearby alert) starts only after that first lookup finishes, so two permission requests never overlap.

### 2.5 "Your name" box
**What you see:** a dialog titled "Your name" with your Google name already typed in, and a single **Save** button. There is no Cancel, and tapping outside does nothing.

**When:** right after you sign in with Google, and on any app start where a Google or staff email account has no name saved yet. Guests never see it.

**Why:** names identify people to admins in the user manager, and the top bar shows your name. `HomeScreen._afterLoad` checks `session.hasAccount` and `displayName`, then opens `askDisplayName(required: true)`. Saving calls `setDisplayName`, allowed by the `isDisplayNameUpdate` rule (1 to 40 characters, only your own profile). A green "Name saved." follows. If you save the same name that's already stored, nothing is written.

**Your chosen name is kept:** signing in with Google again no longer replaces a name you picked. The Google name is used only when the profile has no name.

**If it looks broken:** "Could not save your name. Try again." (red) means the write was refused or the connection failed. The box comes back on the next start until a name is saved.

---

## 3. The app frame

### 3.1 Top bar
**What you see:** "HazardRadar AI" on the left. On the right, your name and a small square photo. Without a photo the square shows your initials (for example "CM"). Guests see "Guest" and a person icon.

**Why:** `_AccountButton` in `home_screen.dart` shows `displayName`, or "Guest" for anonymous sessions. The photo comes from `avatars/{uid}` and is loaded once per account (`_syncAvatar`), not on every tab switch. Squares instead of circles follow the flat design (square corners everywhere except map pins). Long names are cut off with "…" after about 140 px. Tapping the button opens the Account sheet (section 11). Your level title moved to Settings and the Account sheet.

### 3.2 Bottom tabs
**What you see:** Radar, My Reports, (Dispatch for staff only), Settings.

**Why:** the Dispatch tab appears only when `profile.isStaff` (role exactly `DISPATCHER` or `ADMIN`). The role is read from your Firestore profile, not from the tier number. The profile reloads on every tab switch, so a role changed in the Firebase console shows up after you tap any tab.

The tabs live in an `IndexedStack`, which keeps every tab alive. That is why the map keeps its position and your chat stays when you switch tabs and come back.

### 3.3 "Report hazard" button
**What you see:** a red-orange square button at the bottom right, on the Radar tab only.

**Why:** `onReport` is passed to the frame only when the Radar tab is selected (`tab == 0`). Tapping it does three things in order:
1. Reloads your profile so the daily count is current. If that fails you get the toast "Could not check your account. Try again."
2. Checks the daily limit with `ReportLimitPolicy`.
3. Opens the wizard.

Outcomes of the limit check:
- **Guest with 3 reports today:** the Account sheet opens with the text "Guests can file 3 reports a day, and you reached that today." because the fix is to sign in with Google (limit becomes 10).
- **Civic Scout with 10 today:** the toast "You reached today's limit of 10 reports. It resets at midnight."
- **Suspended or banned:** a toast saying the account cannot file reports.
- **Otherwise:** the wizard opens.

Why check before the camera: the Firestore rules are the real limit, but without this check the user would take a photo, write a note, then be rejected at the end. The phone copy exists only for a clear early message.

"Midnight" means midnight in the Philippines (UTC+8), because `philippineDay()` shifts the clock before taking the date.

### 3.4 Warning banner
**What you see:** an amber bar above the map: "Your account has a warning from a moderator..."

**Why:** your `accountStatus` is `WARNED`. An admin set it in the Users tab. You can still report and vote.

---

## 4. Radar tab (the map)

### 4.1 The map and its first load
**What you see:** a spinner, then a map of OpenStreetMap tiles with a cream-and-sage tint, centered on you at zoom 15.

**Why:** the map has no center until `_locate()` finishes. It waits for the permission answer and one GPS reading. If location is on and inside the Philippines, it centers on you. If location is off, denied, or outside the Philippines, it centers on the fallback, Mandaue City (10.3236, 123.9322).

Tiles are tinted by a colour filter (`tintedTileBuilder`) at about 55% colour, so they match the poster look without becoming grayscale. Tiles are cached on the phone up to 150 MB (`tileCacheBytes`), so revisiting an area works with a weak connection. The OSM tile server is for development only; the "OpenStreetMap contributors" credit at the bottom right is required by its licence.

**Why you cannot leave the Philippines:** `CameraConstraint.contain(bounds: philippinesBounds)` with a minimum zoom of 5. Dragging past the edge stops. This also protects the app from out-of-country data.

### 4.2 Your position dot
**What you see:** a small ink dot with a cream ring.

**Why:** drawn from `_fix`, the last GPS reading. It updates only when you move 15 m or more (`distanceFilter: 15`), so a phone lying still does not keep redrawing the map.

### 4.3 Hazard pins
**What you see:** round pins coloured by risk (green Low, amber Medium, red-orange High, a separate colour for In progress) with a category icon.

**Why:** `watchActivePublic()` subscribes to a Firestore query: public incidents with status ACTIVE or IN_PROGRESS, newest first, at most 150. Because it is a live snapshot stream, new reports and status changes appear without refreshing. Resolved, quarantined, and private reports are never in this query, so they disappear from the map as soon as their status changes.

The query needs a composite index (visibility ASC, status ASC, createdAt DESC). Without it Firestore returns an error and the map shows the red "Could not load hazards. Tap to try again." label. On Android you may still see your own reports then, because they come from the phone's local cache, not the server.

Pins outside the Philippines, or documents missing a category, risk, summary, or valid coordinates, are skipped silently (`tryFromFirestore` returns null) so one bad document cannot crash the map.

### 4.4 Square number blocks (clusters)
**What you see:** a square block with a number, coloured by the worst risk inside it.

**Why:** at zoom below 16, pins that fall in the same 64-pixel screen cell are grouped (`clusterPins`). The block shows the count and the highest risk (High, then Medium, then Low). Squares versus round pins keep the two from being confused. Tapping a block zooms in by 2 levels, capped at 16, where every pin is drawn separately.

Pins regroup only when the whole-number zoom changes, so pinching does not recompute every frame.

### 4.5 Search box
**What you see:** "Search: high risk, pothole, HZD id" at the top left.

**Why:** a purely on-device filter over the 150 loaded pins. Each word you type must be the start of a word in the report. It checks:
- the reference (HZD-xxxxxx, the first 6 characters of the document id, upper-cased),
- the category,
- the risk ("high", "medium", "low", and the word "risk"),
- the status ("active", "in progress"),
- "verified" (net votes +3 or more),
- the words of the AI summary.

Capital letters and word order don't matter, so `High Risk`, `high`, `pothole high`, and `in progress` all work. Matching the start of a word means `low` does not match "slow" and `pot` matches "Pothole".

**The map moves to the matches** about 0.6 seconds after you stop typing (`_flyToMatches`). One match is centered at street zoom 17. Several matches are fitted on screen, with room left for the search box and the legend. No match shows a red "No matching hazards on the map." It does not query Firestore, so it can only find reports currently loaded.

### 4.6 Filter chips
**What you see:** All, High risk, Pothole, Electrical, Flooding, Obstruction, Lighting, Other, each with a count.

**Why:** the number counts matching pins in the loaded list, regardless of what is in the search box. Selecting a chip and typing in search are combined (both must match). Tapping a chip also moves the map to the matching pins, the same way as search. "All" with an empty search leaves the map where it is.

### 4.7 Legend, GPS chip, and buttons (bottom left)
- **Legend:** static colour key.
- **GPS chip:** "GPS ±12 m" shows the accuracy radius reported by the phone. "GPS on" means no accuracy was given. "GPS off · showing Mandaue City" means there is no fix, so the map is on the fallback centre.
- **Recenter (target icon):** runs `_locate()` again, then moves to your position at zoom 16. If there is no position or it is outside the Philippines it shows "Location is off."
- **Safe walking route (route icon):** shown only when the proxy is configured. See section 8.

### 4.8 Red-orange banner: "New high-risk report"
**What you see:** a banner with the category and HZD number. Tap to fly to the pin and open its sheet, or tap the X.

**Why:** the first Firestore snapshot only records which ids exist (`_seen`). Every later snapshot compares against it, and any new High-risk id raises the banner. That is why the first load never shows a banner for old reports. If you re-subscribe after an error, the seen ids are kept so old reports do not look new.

### 4.9 Red-orange banner: "High-risk hazard nearby"
**What you see:** "Pothole about 64 m from you. Tap to open."

**Why:** whenever your position or the pin list changes, `nearestUnwarnedHigh` looks for the closest High-risk pin within 100 m that has not already alerted. Each hazard alerts once per app session (`_warned`). It is removed automatically if that hazard leaves the map (resolved or quarantined). If the nearby alert and the new-report banner are about the same hazard, only the nearby one shows.

**Why you may not see it:** you must be within 100 m, the hazard must be High, and the phone must have moved at least 15 m or have refreshed the pin list after you arrived. A hazard you already dismissed will not alert again until you restart the app.

### 4.10 "Could not load hazards. Tap to try again."
**What you see:** a red-orange label under the chips. In debug builds a cream box under it shows the full error text. You can select that text, and the copy icon puts it on the clipboard ("Error copied." in green). The same text is printed in the `flutter run` terminal as `Radar map load error: ...`, where a Firebase index link can be clicked.

**Why:** the stream emitted an error (no internet, missing index, rules not published). A Firestore stream stops after an error, so tapping the label creates a brand-new subscription. The box has a maximum height and scrolls, so a long Firebase link never covers the map.

---

## 5. Hazard sheet (tap a pin)

### 5.1 Opening
**What you see:** a cream sheet covering about 42% of the screen, with a handle bar. It snaps between 42% and 94%. A "Swipe up for photo proof and voting" button also expands it.

**Why:** `DraggableScrollableSheet` with snap sizes 0.42 and 0.94. The short view shows only what a commuter needs at a glance: risk badge, reference and status, category, distance, and the AI summary. Everything else is below the fold to keep the first view quick.

### 5.2 Badges
- **High/Medium/Low risk:** from the stored `riskLevel`.
- **HZD-xxxxxx · Active / In progress:** status. "Resolved by city" and "Disputed" exist for staff views.
- **Verified hazard:** shown when `netVotes >= 3`.

### 5.3 Distance line
**What you see:** "64 m away", "1.3 km away", or "Distance unknown".

**Why:** the sheet reads your position once when it opens and measures the straight-line distance. "Distance unknown" means the phone could not give a position. This same number decides whether you may vote.

### 5.4 AI summary box
**What you see:** sage box titled "AI summary", or "Summary (offline, pending AI review)".

**Why:** each incident stores `aiProcessed`. True means Groq classified the note. False means the phone used the offline keyword classifier because the proxy was unreachable when the report was filed. The app retries those in the background at the next launch (`ReportEnricher`), and the owner's rules allow exactly one AI update per report.

### 5.5 Photo
**What you see:** the photo, a spinner, or a "Load photo" button, or "Visual evidence unavailable".

**Why:**
- With **Data saver off** (default), the photo loads when the sheet opens.
- With **Data saver on** (Settings), a "Load photo" button shows and nothing is downloaded until you tap it.
- "Visual evidence unavailable" means the photo document is missing, not valid Base64, or the download failed. Photos are stored in Firestore as Base64 text in `incidents/{id}/photo/main`, not in Firebase Storage.

### 5.6 Details block
Coordinates (5 decimals), time in Philippine time (PHT, UTC+8), photo size in KB, "Reported by a [level]", the reporter's note in quotes, the recommended action (red-orange rule on the left), and the assigned crew once staff set one.

### 5.7 Vote buttons: "Still here" and "Fixed or fake"
**What happens when you tap, in order:**
1. **Guest (Level 1):** the Account sheet opens with "Voting needs a linked Google account." If you complete Google sign-in, the same vote continues automatically with your new profile. If you cancel, nothing is sent.
2. **Own report:** "You cannot vote on your own report."
3. **No location:** "Turn on location to vote."
4. **More than 200 m away:** "Voting opens within 200 m of the hazard."
5. **Otherwise:** the vote is saved and a green block says "Vote recorded."

Every blocked or failed vote message above appears as a red-orange block under the buttons. "Vote recorded." and "Report flagged. It is hidden from the map." are green.

**Why these rules:** voting is the community's spam filter, so it needs a real identity (Google), physical proximity (200 m), and one vote per person. The rules enforce identity, ownership, and one vote per person. The app measures your distance with your GPS before it sends the vote.

**Vote weight:** Level 2 counts 1. Level 3 and above count 2. "Still here" adds the weight, "Fixed or fake" subtracts it.

**Verification and quarantine:** the total is `netVotes`. At +3 the report shows "Verified hazard". At -3 or lower the report becomes QUARANTINED in the same transaction and vanishes from the public map. Voting uses a Firestore transaction so the vote document and the new total are always written together.

**After voting:** both buttons are disabled for that sheet (`_voted`). "You already voted on this report." appears if the vote document already existed, for example from another device.

**The result shows right away (since 21 Nov).** The vote transaction returns the new net total (`VoteRepository.cast`), and the sheet uses it at once instead of the number it had when it opened:
- **+3 or more:** green "Verified. Enough commuters confirmed this hazard is still there.", the **Verified hazard** badge appears, and the tally reads "Verified by the community".
- **-3 or lower:** green "Thanks. Enough commuters marked this report as fixed or fake, so it is now hidden from the map and sent to a moderator for review." The buttons stay off, and the Flag button disappears. The same transaction writes a public transparency entry (section 9.1).
- **Anything else:** green "Vote recorded." with the updated "N more to verify".

All three are green because the vote itself worked; quarantine is the community doing its job, not an error.

**Quarantined reports** show a black "Community disputed report" panel and disable voting. You only see this if you own the report or are staff.

### 5.8 "Flag as spam or duplicate (Sentinel)"
**What you see:** a text button, only for Level 3 users who are not staff, and only on reports that are not theirs, not already quarantined, and not already flagged by them.

**Why:** it is the Sentinel privilege. A confirmation dialog warns that the report leaves the map immediately. On confirmation it sets `visibility: QUARANTINED` and `flaggedBy`. Staff do not get this button because they have their own quarantine tools.

### 5.9 Vote tally line
"+2 net · 1 more to verify" or "Verified by the community". The number needed is 3 minus the current net votes.

---

## 6. Report wizard (4 steps)

The progress strip at the top shows Location, Photo, Notes, Review. The **Next** button always checks the current step first. If the step is not valid, the reason appears in a red-orange block above the buttons instead of moving on.

### 6.1 Step 1: Location
**What you see:** "Finding your location...", then a 260 px map with a red-orange square crosshair in the centre, a thin ink circle around your GPS dot, and chips for GPS accuracy, geohash, position, and metres moved.

**Why:**
- The wizard asks for a **real GPS fix only**. It never uses the Mandaue fallback, because a report filed at the wrong place would send crews to the wrong street. If there is no fix you see "Turn on location to file a report." with a **Try again** button.
- You can drag the map to move the pin, but only up to **100 m** from your GPS fix. If you drag further, the pin stops at 100 m and the map snaps back when you lift your finger (`_onMapEvent`). Reason: a commuter may be across the street from a hazard, but cannot report one 2 km away.
- The geohash is a short text code for the pin's cell; it is stored with the report and used for the admin hotspot ranking.
- The minimum zoom is 15, so you cannot zoom out far enough to lose your place.
- The blocker text "Reports can only be filed inside the Philippines." appears if the pin is outside the country bounds.

### 6.2 Step 2: Photo
**What you see:** a sage box "Tap to take a photo". After the photo: the image and chips "Compressed: 112 KB JPEG" and "Limit: 150 KB". Tap the picture to retake.

**Why:**
- Only the **camera** is offered (no gallery), so the photo is of the scene right now.
- The app scales the photo to at most 1080 px and compresses it as JPEG, trying quality 80, 65, 50, 35, 25 in turn, and keeps the first result at or under 150 KB. If none fits it says "That photo is too large to send. Try again."
- Why 150 KB: the photo is stored as Base64 inside a Firestore document (document limit 1 MiB, rules cap 900,000 characters), and the free 1 GiB storage must hold many reports.
- "Could not use the camera." means the picker or compressor threw an error. In debug builds the real error is printed under it. The web build had a bug here (fixed in commit e94e79a: the web compressor does not support file compression, so the code uses `compressWithList`).
- Canceling the camera leaves the previous photo (or none). With none, Next says "Take a photo of the hazard."

### 6.3 Step 3: Notes
**What you see:** a text box "What did you see?" with a counter to 500 characters.

**Why:** the note is what the AI reads. English, Tagalog and Cebuano are all handled (Groq on the proxy, and the offline keyword list covers all three). Empty notes are blocked with "Describe the hazard in a few words."

Important side effect: **changing the note clears the AI result** (`setNote` sets triage to null). If you go back and edit, the review step re-runs the AI. This prevents publishing a result that no longer matches the text.

### 6.4 Step 4: Review
**What you see:** "Radar AI is reading your note...", then a risk badge, "Classified by Radar AI" (or "Classified offline"), the category in large serif, the summary, and a "Recommended action" line.

**Why:** `FallbackTriageService` calls the proxy `/triage`. If that fails (proxy off, no internet, timeout, bad JSON) it uses `KeywordTriageService` on the phone. Offline rules are checked in this order: Electrical (High), Flooding (Medium), Lighting (Low), Pothole (Medium), Obstruction (Low), otherwise Other (Low). Keywords match whole words only, so "baha" (flood) does not match "bahay" (house).

So offline classification is a cruder guess. The review page tells you so: "Radar AI was not reachable, so the phone classified this from your words. The AI will check it again when you are back online."

The Publish button is greyed out until a result exists. If the AI step itself fails you see an error with **Try again**.

### 6.5 Publish
**What happens:** the report document and the photo document are written, your daily counter, +10 CTP, and `reportsTotal + 1` are updated in one Firestore transaction (all three succeed or none do), and the wizard closes with a green "Report sent. Thank you." The Radar tab then refreshes your profile.

**Why it can be refused:** "The report was refused..." means `firestore.rules` rejected the write: rules not published, daily limit already reached on the server, suspended/banned status, bad field shapes, or photo too large. Other failures show "Could not send the report. Check your connection and try again."

**Why points come at publish:** the rules deliberately allow only a +10 CTP step in the same write as a new report, so points cannot be self-awarded any other way. There are no Cloud Functions on the Spark plan; the rules are the referee.

### 6.6 Back button
Hidden on step 1. On other steps it goes back one step. The phone's system back button leaves the wizard and discards the draft.

---

## 7. Ask Radar AI (chat)

**Where:** the sage "Ask Radar AI" button next to the search box. Hidden when there is no proxy.

### 7.1 What it sends
Your question (max 500 characters), the **20 hazards nearest to the middle of the map** (id, category, risk, status, summary only), up to 6 earlier messages, the selected mode, and a **report status summary**. Reporter ids and notes never leave the phone.

**Report status summary (since 21 Nov).** Active and in-progress counts come from the loaded map pins. Resolved and quarantined counts, and the 10 newest resolved or moderated reports (HZD id, category, what happened, reason, crew), come from the public transparency log. The proxy checks every number and label against fixed limits and adds a fixed explanation of each status to the prompt, so Radar AI can answer "How many are in progress?", "What was resolved recently?", "Which crew fixed HZD-…?" or "What does quarantined mean?". If the log cannot be read within 3 seconds, the question is still sent without it. The **Report status** quick prompt asks the counts in one tap.

**Why the map centre, not your GPS:** you can pan to another area and ask about it. The 20-hazard cap and 6-message history keep the request small and cheap.

### 7.2 Modes
- **Risk analysis:** summarise the danger nearby.
- **Recommendations:** safety advice.
- **Safe detour:** answer, then offer a "Pick a destination for a safe route" button. The app adds that button itself; the AI cannot.
- **Ask commuter:** a 3-question interview (how are you travelling, where to, did you see a hazard). Answers stay on the phone and are combined into one question at the end. If you say "Yes" to seeing a hazard, the app reminds you to open the pin and vote. **The chat never casts a vote itself.**

Choosing a mode chip a second time deselects it. Quick-prompt chips along the bottom set a mode and send a ready-made question.

### 7.3 Action buttons inside answers
"Show pothole on map" and "Report a hazard" close the chat and then act. "Show on map" works only for incident ids that the app sent in that request, so the AI cannot point you at something you were never shown. Unknown action types are dropped.

### 7.4 Messages you may see
- "Radar AI is checking the map..." while waiting.
- "Radar AI is not reachable right now. Try again in a moment." proxy off or unreachable.
- "Radar AI gave an empty answer. Try asking again." the proxy replied without text.
- "Keep your question under 500 characters." / "Type a question first."
- Quick taps while waiting are ignored, so you cannot flood the proxy.

Error messages in the chat appear as a red-orange block at the end of the conversation.

The conversation survives closing the sheet and switching tabs, because the controller lives in the map's state. The restart icon clears it.

---

## 8. Safe walking route

**Steps:** tap the route button, then tap a destination on the map.

**Why:**
1. It needs your GPS (otherwise, in red: "Turn on location to get a walking route from where you are.").
2. A cream panel says "Tap your destination on the map." with Cancel.
3. The phone sends your position, the destination, and up to 50 High and Medium hazards nearest the **middle of the trip** to the proxy `/detour`. Using the middle means hazards near the destination are not crowded out by hazards near you.
4. The proxy (`findSafeRoute` in `proxy/src/detour.js`) plans the route in up to three rounds:
   - It asks the public OSRM router for up to 3 walking routes.
   - It measures how close each route line comes to each hazard. It measures to the line itself, not only to the route's corner points, so a hazard between two corners is not missed.
   - A route that stays at least **40 m** (`SAFE_METERS`) from every hazard wins, and the shortest of those is chosen.
   - If every route passes closer than 40 m, it takes the closest hazard and asks OSRM for extra routes through points placed **90 m** beside it on four sides (north, east, south, west). Then it picks again. It does this at most twice.
   - Detours much longer than the direct way are ignored (more than 1.7 times as long, and more than 1 km extra), because nobody walks 3 km around one pothole.
   - A hazard right at your start or at your destination cannot be avoided, so it is skipped.
5. The route is drawn with an ink outline and the camera zooms to fit it. The panel shows, for example, "1.3 km · 18 min walk · stays 140 m from High and Medium hazards" (or "no High or Medium hazards nearby"), plus a small color key.
   - **Green:** the suggested route, when it keeps at least 40 m from every High and Medium hazard.
   - **Red underneath:** the shortest route the router offered, when it passes within 40 m of one. The proxy returns it as `direct` next to the chosen route, so you can see what the detour avoids.
   - When the shortest route is already safe, the proxy sends no `direct` route and only the green line shows.
   - When no route keeps clear, the one route is drawn **red**. Colors are fixed, so they look the same in light and dark mode.
6. If no safe route exists, the panel says so plainly: "Warning: passes within 12 m of a High or Medium hazard. No safer route found." It never pretends the route is safe. Low hazards are not avoided (a small crack is not worth a long detour), so the line may cross a green pin. The panel sits under the filter chips so it never covers the legend, GPS chip, or buttons.

The phone waits up to **30 seconds** for a route, longer than the 8 seconds used for chat and triage, because the extra rounds take time.

**Messages (all red):**
- "Pick a destination within 10 km." (the proxy rejected the distance, status 400)
- "Too many route requests. Wait a minute and try again." (more than 6 routes a minute, status 429)
- "The route took too long to plan. Try a closer destination." (30 s timeout)
- "The route service is not reachable. Avoid the red pins and stay on main roads." (proxy or OSRM down. On the phone, first check that `adb reverse` is still set, section 1.)
- "No walking route was found." (OSRM returned nothing usable, or points outside the Philippines)

Low-risk hazards are not avoided on purpose: only High and Medium are sent. The public OSRM server is demo-only; a release needs a hosted provider. Restart the proxy (`Ctrl+C`, then `npm start`) after any proxy change, or the old route logic keeps running.

---

## 9. My Reports tab

**Guest card (sage):** shown only to Level 1. "Sign in with Google" opens the Account sheet.

**Profile card:** level, title, focus badge if any, **trust points (CTP)** on the right, a red-orange progress bar, and three numbers.
- **CTP** are earned +10 when you publish a report and +10 when staff resolve one of your reports.
- **Reports** = `reportsTotal`; **Resolved** = `reportsResolved`; **Accuracy** = resolved ÷ total, shown as a percent (0% when you have no reports).

**Level progress:**
- Level 1 to Civic Scout: 50 CTP, **or** sign in with Google immediately.
- Civic Scout to Neighborhood Sentinel: 250 CTP **and** at least 85% of your reports resolved by the city.
These are checked when the app starts a session (`LevelPolicy.dueUpgrade`) and the profile is then updated. The rules re-check the same numbers, so a modified app cannot award itself a level. When a level appears during later refreshes, the toast "Level up: you are now a ..." shows.

**Focus badge picker:** appears for Level 3 and above who have no badge: Roadway Watch, Grid Guardian, Hydro Monitor. After you pick one the picker disappears, so the app gives no way to change it.

**Filter chips (All / Active / In progress / Resolved)** show counts for your own reports and filter the list.

**Report cards:** coloured left edge by risk, status badge, risk badge, "Pending AI review" for offline-classified reports, summary, and "City note: ..." when staff resolved it.

**Pull down** reloads your profile and re-subscribes the list. A red "Could not load your reports. Pull down to try again." appears when the stream errored (most often a missing index on reporterUid ASC + createdAt DESC).

**Why your list is only yours:** the query filters on your uid, and the rules allow you to read your own reports even when they are private or quarantined.

### 9.1 Report transparency (every user, since 21 Nov)
**What you see:** at the bottom of My Reports, a **Report transparency** heading, chips **All**, **Resolved (n)** and **Quarantined (n)**, and the 30 newest city-wide entries. A resolved entry shows the HZD id, category, risk, date, **Crew:** and **City note:**. A quarantined entry shows the reason ("Community votes: marked fixed or fake" or "Flagged as spam or duplicate by a Sentinel"). Restored and removed entries say "Restored by a moderator" and "Removed as spam".

**Why it is a separate list:** other users cannot read quarantined reports, because they may contain spam text. The log lives in its own collection, `transparency/{incidentId}`, and holds only safe fields: category, risk, what happened, reason, crew, city note and date. It never holds the reporter's id, the note, or the photo, and it never shows which staff account resolved a report.

**"Reported by" on resolved entries (since 22 Nov):** a resolved entry shows "Reported by [name]" only when the reporter turned on **Settings > Show my name on my resolved reports** before staff resolved it. The switch is off by default. Quarantined, restored and removed entries never carry a name, so nobody is publicly linked to a disputed report (Data Privacy Act, RA 10173). The rules accept the name only on a resolved entry, and only when it equals the reporter's saved name with the switch on. Turning the switch off stops new credits; entries already written keep the name.

**Why it can be trusted:** an entry can only be written in the same transaction as the real change (a vote reaching -3, a Sentinel flag, a staff resolve, a restore, or an admin purge). The rules check that its category and risk copy the report and, for resolved reports, that the crew, note and date match. Nobody can delete an entry. A later event on the same report replaces its entry, so the list shows the latest outcome.

**If it looks broken:** "Could not load the transparency log" means the rules were not republished. An empty list on an older project means nothing was resolved or quarantined since 21 Nov; an admin can run **Sync transparency log** (section 12.2).

---

## 10. Settings tab

Sections from top to bottom: Account, Appearance, Data, City staff. Pull down to reload your profile.

### 10.1 Account
**What you see:** a 64 px square photo (or initials, or a person icon for guests), your name in large text, and "System Administrator · Level 5" (your level title and number) under it. Below that:
- **Edit name** (Google and staff accounts): opens the "Your name" box with a Cancel button. Green "Name saved." when it works.
- **Change photo** (Google and staff accounts): a bottom sheet with **Take a photo** (front camera), **Choose from gallery**, and **Remove photo** (only when you have one). Green "Photo saved." or "Photo removed."
- **Level details** (signed-in accounts): opens the Account sheet with your points, progress, and what your level can do (section 11).
- **Sign in with Google** (guests only, red-orange button): opens the Google upgrade.
- **Show my name on my resolved reports** (Google and staff accounts, since 22 Nov): a switch, off by default. Green "Your name will show on your reports the city resolves." or "Your name will no longer be added to resolved reports." See section 9.1 for what it does. Guests have no saved name, so they do not see it; a blocked account can still turn it off.

**Why the photo is small and separate:** the picker resizes the photo to 256 px and compresses it to at most 29 KB (`ImageAvatarPicker`). It is saved as Base64 in its own document, `avatars/{uid}`, not inside `users/{uid}`. The admin user list streams up to 200 profile documents, and keeping photos out of them keeps that list fast. The rules let only you write your photo (at most 40,000 Base64 characters, and not while banned or suspended). Only you and staff can read it.

**If it looks broken:**
- "Could not save the photo. Try again." (red, with the real error in debug builds) usually means the rules were not republished after 20 Nov, so `avatars/{uid}` is refused.
- "That photo is too large. Try another one." means even quality 25 was above 29 KB, which is rare at 256 px.

### 10.2 Appearance
**What you see:** two chips, **Light** (selected by default) and **Dark**.

**Why:** `AppSettings.themeMode` is saved on the phone under the key `themeMode`. The app does not follow the phone's own dark mode setting; it uses only your choice here. `main.dart` reads the saved choice before the first frame, so a dark-mode user never sees a light flash at launch. See section 16 for what changes in dark mode.

### 10.3 Data
- **Data saver:** saved on the device (`SharedPreferences`), so it persists across launches. On means photos in the hazard sheet need a tap.

### 10.4 City staff
- *Guest/anonymous:* an email and password form and a **Sign in as staff** button. It **replaces the guest session** on this phone. There is no Google button here (removed on 20 Nov); Google sign-in lives in the Account section. A wrong password gives a red "Wrong email or password." A sign-in without a staff role gives a red "Signed in, but this account has no staff role yet. Ask an admin."
- *Google account:* your name and email in a sage box, then:
  - **Check staff access** reloads the profile. Green "Staff access is on. Open the Dispatch tab." or red "No staff role on this account yet. Ask an admin to give [your name] the ADMIN or DISPATCHER role."
  - **Set staff password** (staff only; it says **Change staff password** once set). It asks for a password twice (at least 8 characters). It **links an email and password to the same account**, so your uid, role, points and reports stay the same. Afterwards the staff email form also works with your Gmail and that password, for example on a shared office computer. It needs **Email/Password** turned on in **Authentication > Sign-in method**. If it is off, the red message tells you so.
  - **Sign out.**
- *Email staff session:* "Signed in as ..." and Sign out.
- **Sign out (Google):** signs out of Google and Firebase and starts a new anonymous guest. Your points and reports stay on the Google account, so signing in again restores them. The guest you become afterwards is a different, empty user. Green "Signed out. You are browsing as a guest."

**Why the staff form failed for your admin before 20 Nov:** your admin account is a Google account. It had no password, so `signInWithEmailAndPassword` could never succeed with your Gmail. Staff access for Google accounts comes from the `role` on the profile, not from a password. "Set staff password" adds one if you want both ways in.

---

## 11. Account sheet (Google upgrade)

**Guest view:** "Become a Civic Scout", a reason line (changes by what you were doing), four benefits, "Continue with Google", "Continue as guest".

**What Google sign-in does:** it **links** the Google credential to your current anonymous uid, so your guest data is kept. If that Google account already belongs to another uid (a previous install), the app switches to that existing profile instead, which is why uid changes are handled in My Reports.

After linking, `upgradeToCivicScout` raises you to Level 2, a green "Signed in with Google. You are now a Civic Scout." appears, and the "Your name" box opens with your Google name filled in (section 2.5). Failure cases show red messages from the linker; in debug builds the raw error (such as `permission-denied`) is added below. Cancelling the Google picker simply closes without changes.

**Signed-in view ("Level details"):**
- **Level and title:** for example "Level 5" and "System Administrator".
- **Your numbers:** trust points, reports, resolved, and accuracy.
- **Progress:** for citizens, a red-orange bar and "40 / 50 points to Civic Scout" with what the next level needs. Sentinels see "Highest citizen level." Staff see "City staff level. Set by an admin." because staff levels are never earned with points.
- **What you can do:** a plain list from `levelPrivileges()`:

| Level | What the list says |
|---|---|
| 1 Commuter Observer | Browse the map and ask Radar AI; 3 reports a day; sign in with Google to vote |
| 2 Civic Scout | 10 reports a day; vote within 200 m, counts 1 |
| 3 Neighborhood Sentinel | Unlimited reports; votes count 2; flag spam or duplicates; pick a focus badge |
| 4 Municipal Dispatcher | Unlimited reports, votes count 2; Dispatch tools (start work, crews, resolve, correct AI ratings); restore quarantined reports |
| 5 System Administrator | Everything Level 4 has, plus user management, analytics, and purging spam |

  An extra line appears if an admin turned off your daily limit.
- **How points work:** "You earn 10 points for each report, and 10 more when the city resolves it."

**Why:** before 20 Nov this view said only "Your account is linked", so the "Level details" button showed no details. The list mirrors the real limits in `report_limit_policy.dart`, `vote_policy.dart`, and `firestore.rules`. If you change a limit there, update `levelPrivileges()` too.

---

## 12. Dispatch tab (staff only)

Visible when your profile role is exactly `ADMIN` or `DISPATCHER`. **Everything here is also enforced by the rules**, so hiding a button never replaces security.

Sub-tabs: **Queue** and **Quarantine** for all staff. **Users** and **Analytics** only for ADMIN.

### 12.1 Queue
- Four blocks: Active high, In progress, Resolved, Quarantined. The first two count what is currently open; Resolved and Quarantined come from separate count queries, so they show "-" until loaded.
- Risk filter chips: All, High, Medium, Low.
- Order: High first, then Medium, then Low; oldest first inside each level, so the longest-waiting urgent ticket is on top.
- Each **ticket** shows category/risk, status, HZD number, AI summary, coordinates, time (PHT), net votes, and the crew.
- **Reported by** (since 22 Nov): "Reported by [name] · [level] · [status if not Active]". Without a saved name it says "Guest" or "Name not set yet", never an id. Tapping it opens the user page (section 12.3); dispatchers see that page read-only, because only admins manage accounts. Staff can already read profiles under the rules, so no new access was added.
- **Start work** (Active tickets): asks for a crew name (can be left empty), then sets IN_PROGRESS. **Resolve** (In-progress tickets): asks for a required note (max 300 characters), sets RESOLVED, and credits the reporter +10 CTP in the same write. The status can only move forward one step: Active, In progress, Resolved. There is no skip and no reopen.
- **Crew** edits the crew name (max 60 characters). **Override AI** lets staff correct category and risk when the AI got it wrong.
- Resolved tickets leave the queue because the query lists only open statuses. Quarantined tickets are filtered out of this list and handled in the Quarantine tab.
- Buttons grey out for a ticket while its change is being saved.

### 12.2 Quarantine
- A storage meter: estimated photo storage against the free 1 GiB, and about how many more uploads fit. It turns red-orange at 80%.
- Each quarantined report shows its details and the same "Reported by" line as the Queue. **Restore and verify** puts it back on the public map. **Permanently purge** (admins only, with a confirmation) deletes the report, its photo, and its votes for good.
- Restore and purge also write the transparency log ("Restored by a moderator" / "Removed as spam"). The purge record stays public, so the community can see spam was removed. It never names the reporter.
- A purge also adds 1 to the reporter's `reportsRemoved` in the same transaction. The rules accept it only from an admin, only +1, and only when that user's quarantined report exists before the write and is gone after it, so each removal counts once.
- **Sync transparency log** (admins): adds entries for reports resolved or quarantined before the log existed, in small batches. Running it again adds nothing and says "The transparency log is up to date."

### 12.3 Users (admin)
**The list:** a search box ("Search by name"), then one row per user with initials, the name, and the role (level title). Your own row ends with "(you)". Nothing else is on the row, so the list scans quickly.

**Names:** a saved name always shows. Without one, the row says "Guest" for Level 1 and "Name not set yet" for everyone else. It never shows "Unnamed user" or a raw uid. A Google user who has no name gets the "Your name" box the next time they open the app, and their real name then appears here.

**Tap a row** to open the user page (`UserDetailScreen`):
- the photo (staff can read `avatars/{uid}`), name, role, and a status badge (red-orange for Suspended or Banned, amber for Warned),
- trust points, reports, resolved, accuracy, and the suspension end time, under a **Report history** heading,
- **Quarantined now** and **Removed as spam** (since 22 Nov). Quarantined now is counted live from the user's reports that are hidden and not resolved (two equality-only count queries, so no extra index). Removed as spam is the `reportsRemoved` counter (section 12.2),
- a **Suggested:** box from the moderation guideline in `docs/STAFF_SETUP.md`: 0 or 1 quarantined or removed means "No action"; 2 or more on an Active account "Warn"; 3 or more on a Warned account "Suspend for 7 days"; 5 or more after a suspension "Consider a ban". It moves one step at a time, and restored or resolved reports never count. It is only a hint: the app never changes an account by itself. Pull down to recount,
- **Actions:** Role, Account status (Active, Warned, Suspended, Banned), and the **No daily report limit (emergencies)** switch. Suspending asks for 1, 3, 7, or 30 days.

Each change shows a green "Role saved." / "Status saved." / "Limit setting saved." or a red error. The page follows the live user list, so the new values appear as soon as Firestore saves them.

**Your own page** shows the red "You cannot change your own account." and the actions are greyed out. That prevents an admin from locking themselves out; the rules enforce the same thing.

A suspended or banned user can no longer file reports; this is enforced by the rules.

### 12.4 Analytics (admin)
Computed on the phone from the newest 500 reports: resolution rate, mean time to resolve, totals, active by risk, in progress, resolved today, quarantined, category share bar, top 1 km hotspot cells (geohash), AI health (share classified by Radar AI vs offline), and the storage meter. Because it reads only the newest 500, numbers for a larger city would be partial; the footer says so.

---

## 13. Rules that apply everywhere

| Rule | Value | Where enforced |
|---|---|---|
| Daily reports | Level 1: 3, Level 2: 10, Level 3+: unlimited, or unlimited with an admin override | Rules (real), phone (early message) |
| Day boundary | Midnight in the Philippines (UTC+8) | Rules and `philippine_day.dart` |
| Vote distance | within 200 m | App, using your GPS |
| Vote weight | L1 none, L2 = 1, L3+ = 2 | Rules and phone |
| Verified | net votes >= +3 | Phone label |
| Quarantine | net votes <= -3, or a Sentinel flag | Voting transaction and rules |
| Photo | at most 150 KB JPEG | Phone compressor and rules |
| Note | 1 to 500 characters | Phone and rules |
| Pin shift | at most 100 m from GPS | App, using your GPS |
| Level 2 | 50 CTP or Google sign-in | Rules |
| Level 3 | 250 CTP and 85% of reports resolved | Rules |
| Staff | role DISPATCHER or ADMIN on the profile | Rules |
| Nearby alert | High risk, within 100 m, once per session | Phone |
| Display name | 1 to 40 characters, your own profile only | Rules and phone |
| Profile photo | at most 29 KB JPEG (40,000 Base64 characters); owner writes; owner and staff read | Rules and phone |
| Safe route clearance | at least 40 m from High and Medium hazards when possible | Proxy |
| Staff password | at least 8 characters; needs Email/Password enabled | Firebase Auth and phone |
| Transparency entry | only with the matching vote, flag, resolve, restore, or purge; copies category and risk; no deletes | Rules |
| Reporter credit | name only on resolved entries, only with `creditName` on, and equal to the saved name | Rules |
| Removed-as-spam count | +1 only in the admin purge of that user's quarantined report | Rules |
| Suggested moderation action | hint from quarantined + removed counts and account status; never applied automatically | Phone |
| Safe vs risky route | green when it stays 40 m or more from High/Medium hazards, red otherwise | Proxy and phone |

Why so much is in the rules: the project is on the Firebase Spark plan, which has no Cloud Functions, so there is no server code to trust. Firestore security rules are the only code the client cannot change.

---

## 14. Scenario table: "I did X and Y happened"

| You did | You see | Reason |
|---|---|---|
| Open the app with no internet | "Could not connect..." with Retry | Anonymous sign-in or profile load failed |
| Open the map with location off | Map on Mandaue, chip "GPS off · showing Mandaue City" | No fix, fallback centre |
| Tap Report hazard with location off | "Turn on location to file a report." | Wizard never uses the fallback |
| Take a 4 MB photo | Works, shows e.g. 98 KB | Resized to 1080 px and recompressed |
| Edit the note after seeing the AI result | Review runs again | The old result was cleared |
| Publish with the proxy off | Report published, result marked "Classified offline", later upgraded to "Classified by Radar AI" | Keyword fallback, then `ReportEnricher` on a later launch |
| Guest vote | Account sheet | Voting needs Level 2+ |
| Vote while 300 m away | "Voting opens within 200 m of the hazard." | Distance rule |
| Vote on your own report | "You cannot vote on your own report." | Ownership rule |
| Vote twice | Buttons disabled, or "You already voted on this report." | One vote per user per report |
| 3 users vote "Fixed or fake" (L2) | Report disappears from the map | netVotes -3 means QUARANTINED |
| Guest files 4th report today | Account sheet "you reached that today" | Limit 3 |
| Staff resolves your report | Report moves to Resolved, +10 CTP, City note appears | Resolve write credits CTP |
| Change role in console, stay on the same screen | Dispatch tab appears after tapping any tab or pulling to refresh | Profile reloads on tab switch |
| Dispatch tab missing for ADMIN | Role is not the exact string `ADMIN`, or you are signed in as a different uid | See section 15 |
| Tap Ask Radar AI | Sheet opens, replies slowly | Request goes phone, proxy, Groq |
| Ask when the proxy is off | "Radar AI is not reachable right now." | `ProxyException` |
| Pull down in My Reports | Spinner, then fresh numbers | Re-subscribe plus profile reload |
| Sign out of Google | You become a guest with 0 points | New anonymous uid. Sign in again to get the old data back |
| Phone shows only your own reports, web shows all | Red "Could not load hazards" with `failed-precondition` | Missing map index (fixed 20 Nov) |
| Phone: "route service is not reachable", web works | Route and chat fail on the phone only | `adb reverse` link dropped. Run it again |
| Type `high risk` in search | Map flies to the High pins | Word-start search on risk, status, category, id, summary |
| Route where every street passes a hazard | Route still drawn, panel says "Warning: passes within X m..." | No safer route exists within the detour limits |
| Sign in with Google | Green message, then the "Your name" box | Name is required for accounts |
| Pick a profile photo before republishing rules | Red "Could not save the photo" | `avatars/{uid}` rule not published yet |
| Tap Dark in Settings | Whole app turns dark; stays dark after restart | Saved `themeMode` |
| Admin taps a user row | User page with stats and actions | List shows name and role only |
| Use the staff form with your Gmail | Red "Wrong email or password." | No password on a Google account. Use "Set staff password" first |
| New code doesn't seem to show up | Old buttons and texts still visible | Press `R` (hot restart), not `r`. Restart the proxy for proxy changes |
| A vote takes a report to -3 | Green "…hidden from the map and sent to a moderator", pin disappears, entry in Report transparency | Vote transaction quarantines and logs it |
| Every vote or resolve fails after the 21 Nov update | Red "Could not…" messages | Rules not republished, so the transparency write is refused |
| Ask Radar AI "How many are in progress?" | A number that matches the map | Status summary sent with the question |
| Route over a hazard | Red shortest line, green safe line on top | Proxy returns both routes |

---

## 15. Things in the code that look like quirks (check these while testing)

These are not confirmed bugs. They are places where behaviour may surprise you or differ from the label. If you hit one, report it and I will decide with you whether to change it.

1. **"Restore and verify" does not verify.** The Quarantine button's label says it verifies, but `restore()` puts the report back with `netVotes` reset to 0 (documented in `moderation_repository.dart`). The restored report will not show "Verified hazard". Likely fix: rename the label to "Restore" (or set the votes to the threshold on purpose).
2. **Focus badge picker for staff.** The picker appears for any tier of 3 or above without a badge, which includes Dispatcher (4) and Admin (5). It may be unwanted for staff.
3. **Staff can vote with weight 2.** Weight is "tier 3 and above", so Dispatchers and Admins vote with the Sentinel weight. The Flag button is hidden for staff, but voting is not.
4. **Nearby alert is once per session.** Dismissing it, or restarting the app and walking away and back, behaves differently: dismissed ids are remembered only until the app process ends.
5. **Search and chip counts use only loaded pins (max 150).** In a busy area some hazards will not be found by search because they are not loaded.
6. **Search box is not cleared when filter chips change**, and chip counts ignore the search text. Both chips and search move the map, so combining them can jump the map twice.
7. **Proxy-dependent buttons vanish silently** if `PROXY_URL` is missing from `dart_defines.json` or a full restart was not done after editing it.
8. **A stale editor buffer** can show red squiggles in `lib/main.dart` even though the file on disk is correct (it happened again on 20 Nov). Use **Ctrl+Shift+P > Revert File**, then **Dart: Restart Analysis Server**. Do not save that tab.
9. **Console steps still pending** if any of these happen: "The report was refused..." (rules not published), "Could not load hazards" or "Could not load your reports" (indexes), missing Dispatch tab (role string and tier number on the right user document), "Could not save the photo" (rules not republished after 20 Nov).
10. **Public OSM tiles and public OSRM** are development-only services and may rate-limit or slow down.
11. **The map stays light in dark mode.** Only the panels, sheets, and text around it turn dark. The tiles use the same cream tint in both modes.
12. **Old accounts without a name** show "Name not set yet" to admins until that person opens the app and saves a name.
13. **Profile photos are square**, like every other block in the app. Only map pins are round.
14. **Focus badge picker and voting for staff** (items 2 and 3) are unchanged.

## 16. Colors, messages, and light/dark mode

### 16.1 Message colors
Every message that reports a result now has a color and an icon (`lib/ui/common/feedback.dart`):

| Kind | Look | Examples |
|---|---|---|
| Success | Deep green `#256446`, cream text, check icon | "Vote recorded.", "Report sent. Thank you.", "Name saved.", "Staff access is on." |
| Error or blocked | Red-orange `#E73213`, black text, warning icon | "Could not load hazards", "Voting opens within 200 m", "Wrong email or password.", "No matching hazards on the map." |

They appear in two forms. Pop-up messages at the bottom of the screen use `showSuccess` / `showError`. Inline blocks under a button or form use `FeedbackMessage`. Both use the same fixed colors in light and dark mode. The icon carries the same meaning for people who can't tell green from red.

**Why these colors:** green is darker than the Low-risk pin green so cream text stays readable (about 5.6:1 contrast). Red-orange with black text matches the High-risk color rule (about 4.9:1). Neutral texts such as "No open tickets. The streets are clear." stay plain because they are neither success nor failure.

### 16.2 Light and dark mode
- **Light (default):** cream background, ink text, sage panels.
- **Dark:** near-black background `#1C1B19`, cream text, dark sage panels `#35504A`. Red-orange buttons, risk colors, pins, and message colors are the same in both modes.
- Text on the colored risk badges (Low, Medium, In progress) keeps its fixed color, so it stays readable on those fills.
- The splash screen does not change.

**How it works:** colors that change with the mode come from `AppPalette` (read as `context.palette.paper / ink / sage`). Colors that never change stay in `AppColors`. If a screen ever shows dark text on the dark background, it is a spot that still uses a fixed `AppColors.ink`. Report the screen.

## 17. Change log: what was fixed on 20 to 22 Nov 2026

| Commit | What changed |
|---|---|
| `479ee54` | Safe route avoids hazards (40 m clearance, detours around the blocking hazard, honest warning). Search and chips move the map. Map load error shows the real error in debug. |
| `587030a` | Rules test for the map query for guests, Google users, and admins. |
| `1834d56` | `firestore.indexes.json` records the two indexes. Copyable debug error under the map label. |
| (console) | The two composite indexes were created. This fixed "phone shows only my reports". |
| `35325a4` | Search matches risk, status, verified, and summary words, in any case and order. |
| `ccc18a8` | Route timeout raised to 30 s; clear messages for too many requests and timeouts. Phone failure was the dropped `adb reverse` link. |
| `ee4acb3` | Light/dark mode, colored messages, name prompt, profile photo, name and photo in the top bar and Settings, staff password for Google admins, user list plus user page. Rules: `avatars/{uid}`. |
| `b35080d` | Removed "Sign in with Google" from City staff. |
| `db7f817` | "Level details" now shows points, progress, and what your level can do. |
| `285774e` | Vote outcomes: green "Vote recorded.", "Verified…", or the quarantine message right after a vote. |
| `5c41571` | Public transparency log (`transparency/{incidentId}`) written with each vote, flag, resolve, restore, and purge. |
| `18512dd` | Report transparency section in My Reports; admin Sync transparency log button. |
| `0784875` | Radar AI knows active, in progress, resolved, and quarantined reports; "Report status" quick prompt. |
| `70fca15` | Safe route drawn green; the shortest route drawn red when it passes a hazard; color key in the panel. |
| `1543083` | Queue and Quarantine cards show "Reported by [name] · [level]"; dispatchers get a read-only user page. |
| `a9f21d1` | User page: Report history (quarantined now, removed as spam) and a suggested moderation action. Rules: `reportsRemoved`. |
| `36a64c0` | Opt-in "Reported by" on resolved transparency entries; Settings switch. Rules: `creditName`, `reporterName`. |

Test counts after these changes: Flutter 192, proxy 46, rules 94.
