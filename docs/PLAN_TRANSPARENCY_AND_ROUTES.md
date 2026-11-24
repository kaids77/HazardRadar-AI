# Implementation plan: vote outcomes, report transparency, status-aware Radar AI, colored routes

Written 21 Nov 2026. Each task below is one commit. Tasks are ordered so each one builds on the previous.
Status: **done.** All five decisions were approved as recommended. Commits: Task 1 `285774e`, Task 2
`5c41571`, Task 3 `18512dd`, Task 4 `0784875`, Task 5 `70fca15`, Task 6 (this documentation update).
Note: the Flutter tests cannot reach Firestore, so the repository writes of Task 2 are covered by the
rules emulator tests, which send the same writes the app does.

## 1. What you asked for

| # | Request | Where it shows |
|---|---|---|
| A | After a vote makes a report **verified**, show it in green, not plain black text. | Hazard sheet |
| B | After a "Fixed or fake" vote sends a report to **quarantine**, say so clearly. | Hazard sheet |
| C | A **Report transparency** section at the bottom of My Reports, visible to every user, listing resolved and quarantined reports and the crew that resolved each one. | My Reports tab |
| D | Radar AI answers questions about **active, in progress, resolved, and quarantined** reports. | Ask Radar AI |
| E | The safe route **suggests a hazard-free path in green**, and shows a path that passes a hazard **in red**. | Radar map |

## 2. Decisions to confirm before coding

1. **Where the public transparency list comes from (C).**
   Today a user can only read public reports and their own. Quarantined reports are hidden from
   everyone else on purpose, because they can contain spam text.
   - **Recommended:** a new public collection `transparency/{incidentId}` holding only safe fields:
     HZD reference, category, risk, what happened (Resolved, Quarantined, Restored, Removed as spam),
     the reason for quarantine (community votes or a Sentinel flag), the crew, the city's resolution
     note, and the date. It never holds the reporter, the note, or the photo. Each entry is written in
     the same Firestore transaction as the action itself, and the rules check that it matches the report.
   - Alternative: let every user read quarantined reports directly. Simpler, but it would expose spam
     notes to everyone. Not recommended.
2. **Quarantine message wording and color (B).** Proposed, shown as a green block because the vote
   worked: *"Thanks. Enough commuters marked this report as fixed or fake, so it is now hidden from
   the map and sent to a moderator for review."*
   Verified message, green: *"Verified. Enough commuters confirmed this hazard is still there."*
3. **Older reports (C).** Reports resolved or quarantined before this change have no transparency
   entry. Proposed: an admin-only **Sync transparency log** button in Dispatch > Quarantine that
   adds the missing entries once. Without it, only new events appear.
4. **Route colors (E).** Proposed:
   - The shortest route is drawn **red** when it passes within 40 m of a High or Medium hazard.
   - The suggested safe route is drawn **green** on top.
   - If no route avoids the hazards, only the best one is drawn, in red, with the existing warning.
   - If the shortest route is already safe, only one green line is drawn.
5. **Who can see crews (C).** Crew names typed by staff (for example "DPWH Patch Crew 4") and the
   resolution note become visible to every signed-in user. The staff account that resolved it is
   never shown.

## 3. Tasks

### Task 1: Vote outcome messages and live tally (A, B)
- `VoteRepository.cast` returns the new net vote total from its transaction.
- The hazard sheet uses it right away:
  - **+3 or more:** a green "Verified…" block, the **Verified hazard** badge appears, and the tally
    reads "Verified by the community".
  - **-3 or lower:** a green "…hidden from the map and sent to a moderator" block, the buttons stay off.
  - **Otherwise:** a green "Vote recorded." block with "N more to verify".
- Tests: widget tests for the three outcomes.
- Commit: `feat(votes): show verified and quarantined outcomes right after a vote`

### Task 2: Transparency log in Firestore (C, data only)
- New `transparency/{incidentId}` documents with: `reference`, `category`, `riskLevel`, `kind`
  (RESOLVED, QUARANTINED, RESTORED, PURGED), `reason` (COMMUNITY_VOTES, SENTINEL_FLAG, or none),
  `crew`, `resolutionNote`, `at`.
- Written in the same transaction as:
  - a vote that quarantines (QUARANTINED, COMMUNITY_VOTES),
  - a Sentinel flag (QUARANTINED, SENTINEL_FLAG),
  - a staff resolve (RESOLVED, crew and note),
  - a staff restore (RESTORED),
  - an admin purge (PURGED; the entry stays as a public record that spam was removed).
- `firestore.rules`: any signed-in user reads. Writes are allowed only together with the matching
  report change, with fields copied from the report. No deletes.
- Rules tests for allowed and denied cases, plus Flutter tests for each repository write.
- **Console:** republish `firestore.rules` after this task. No new index is needed.
- Commit: `feat(transparency): record resolved and quarantined reports in a public log`

### Task 3: Report transparency section in My Reports (C, screen)
- At the bottom of My Reports, for every user (guests too): a **Report transparency** heading,
  chips **Resolved** and **Quarantined** with counts, and the newest 30 entries.
  - Resolved entry: HZD reference, category, risk, "Resolved by city", the date, **Crew:** name,
    and the city note.
  - Quarantined entry: HZD reference, category, risk, the date, and the reason ("Community votes:
    marked fixed or fake" or "Flagged as spam or duplicate by a Sentinel"). Restored and removed
    entries say so.
- Pull down to refresh includes it.
- Admin **Sync transparency log** button in Dispatch > Quarantine (decision 3).
- Tests: widget tests for both kinds and the empty state.
- Commit: `feat(reports): add a public report transparency section`

### Task 4: Radar AI knows report statuses (D)
- The app sends, with each question:
  - the status of each listed hazard (Active or In progress),
  - counts: active and in progress from the map, resolved and quarantined from the transparency log,
  - up to 10 newest transparency entries (reference, category, kind, reason, crew).
- Proxy `/chat`: validates and size-limits the new fields, and adds a fixed rule to the prompt
  explaining what each status means and to answer counts only from the data sent.
- Examples it should answer: "How many reports are in progress?", "What reports were resolved?",
  "What does quarantined mean?", "Which crew fixed HZD-4F9A2C?"
- Tests: proxy validation and prompt tests, Flutter chat service test for the payload.
- **Restart the proxy** after this task.
- Commit: `feat(chat): answer questions about active, in progress, resolved, and quarantined reports`

### Task 5: Green safe route, red risky route (E)
- Proxy `/detour` also returns the shortest route and its clearance, next to the chosen safe route.
- The map draws the risky shortest route in red and the suggested safe route in green, following
  decision 4.
- The route panel adds a small key: green "Suggested safe route", red "Passes a hazard".
- Tests: proxy tests for the extra route, widget test for the two colors.
- **Restart the proxy** after this task.
- Commit: `feat(route): draw the suggested safe route green and the risky route red`

### Task 6: Documentation
- Update `README.md`, `docs/WALKTHROUGH.md`, and `docs/WALKTHROUGH_WHY.md`, and the
  external course documentation copy (`HazardRadar-AI-Documentation.docx`, outside git).
- Commit: `docs: describe vote outcomes, report transparency, status-aware Radar AI, and route colors`

## 4. Checks after every task
`flutter analyze`, `flutter test --no-pub`, `cd proxy; npm test`, and
`cd rules-test; npm run emulator:test`. A task is committed only when all pass. Each commit is
scanned for keys before it is made.
