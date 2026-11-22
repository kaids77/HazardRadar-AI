# Implementation plan: moderation signals and opt-in reporter credit

Written 21 Nov 2026, approved as recommended ("proceed with what is more recommended, as long as there is
no conflict"). Each task is one commit.

**Status: done.** Task 1 `1543083`, Task 2 `a9f21d1`, Task 3 `36a64c0`, Task 4 is the docs commit.

## Principles (to avoid privacy conflicts)
- Reporter names are shown **to staff only** (Queue, Quarantine, user page). Staff can already read
  profiles under `firestore.rules`.
- Quarantined, restored, or removed reports **never** show a name publicly.
- A public "Reported by" credit appears **only on resolved reports**, and **only** for users who turn it
  on in Settings. It is **off by default** and can be turned off at any time; turning it off stops new
  credits from being added.
- Suggested moderation actions are **hints**. The app never warns, suspends, or bans anyone by itself.

## Task 1: Staff see the reporter on Queue and Quarantine
- Each ticket and quarantine card shows "Reported by [name] · [level]". Without a saved name it shows
  "Guest" or "Name not set yet", never the user id.
- Tapping it opens the user page. Admins can act there; dispatchers see it read-only.
- Commit: `feat(dispatch): show the reporter on queue and quarantine cards`

## Task 2: Report history and a suggested action on the user page
- New "Report history": reports filed, resolved, **currently quarantined**, and **removed as spam**.
- Removed-as-spam is a counter on the profile (`reportsRemoved`), raised by one in the same transaction
  as an admin purge; the rules check it matches a real purge of that user's report.
- A hint follows the moderation guideline:

| Signal | Suggested action |
|---|---|
| No quarantined or removed reports | No action |
| 2 or more quarantined or removed, account Active | Warn |
| 3 or more, account Warned | Suspend 7 days |
| 5 or more, after a suspension | Consider a ban |

  Restored and resolved reports never count against the user. Offensive or clearly fake content can
  justify faster action; the admin decides.
- Commit: `feat(users): show report history and a suggested moderation action`

## Task 3: Opt-in "Reported by" credit on resolved reports
- Settings switch for Google and staff accounts: **Show my name on my resolved reports**, off by default.
- When staff resolve a report, the transparency entry includes the reporter's name only if the switch is
  on. The rules check the name matches the reporter's profile and the switch.
- The Report transparency list shows "Reported by [name]" on those resolved entries only.
- Commit: `feat(transparency): optional reporter credit on resolved reports`

## Task 4: Documentation
- README, walkthrough files, staff setup (moderation guideline).
- Commit: `docs: moderation signals, suggested actions, and opt-in reporter credit`

## Console
Republish `firestore.rules` after Tasks 2 and 3. No new index and no proxy change.
