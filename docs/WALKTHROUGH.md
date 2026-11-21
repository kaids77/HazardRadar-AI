# HazardRadar AI: mobile app walkthrough

A top-to-bottom test path for the Android app and the web version. Written from the code. Last updated 20 Nov 2026, after commit `db7f817`.

The reasons behind each behavior are in `WALKTHROUGH_WHY.md` (same folder). Its section 17 lists what changed on 20 Nov.

When something differs from this file, report the step number, the screen, what you tapped, and any message text. Debug builds show more detail.

**Message colors:** success messages are green with a check icon. Errors and blocked actions are red-orange with a warning icon. A plain black message where you expected a color is a bug, or an old build (see Setup step 5).

## Setup before you start
Run the commands from the project folder (the one with `pubspec.yaml`). `adb` is in the Android SDK's `platform-tools` folder; add it to `PATH` or use the full path to `adb.exe`.

1. Start the proxy: `cd proxy; npm start`
2. Forward the port to the phone: `adb reverse tcp:3000 tcp:3000`
   - Check it with `adb reverse --list`. It must show `tcp:3000 tcp:3000`.
   - Run it again whenever you replug the cable or the phone reconnects. A dropped link causes "The route service is not reachable" and "Radar AI is not reachable" on the phone only.
3. Run the app on the phone: `flutter run --dart-define-from-file=dart_defines.json`
   - Web: add `-d chrome` in a second terminal.
4. Firebase console, once:
   - **Firestore Database > Rules:** paste `firestore.rules` and click **Publish**. Required since 20 Nov for profile photos. A greyed-out Publish button means it's already up to date.
   - **Firestore Database > Indexes > Composite:** both indexes show **Enabled** (`incidents`: visibility, status, createdAt; and `incidents`: reporterUid, createdAt).
   - Optional, for "Set staff password": **Authentication > Sign-in method > Email/Password** turned on.
5. After code changes, press `R` (capital R, hot restart) in each `flutter run` terminal. Restart the proxy (`Ctrl+C`, `npm start`) after proxy changes.
6. If VS Code shows red errors in `lib/main.dart` but `flutter analyze` is clean, the editor tab is stale: **Ctrl+Shift+P > Revert File**. Don't save that tab.

## A. Launch
1. **Splash:** the photo, the title and the tagline show for about 2.5 seconds, then fade out.
2. **Spinner:** a red-orange spinner shows for a moment.
   - If you see a red "Could not connect…" block with a Retry button, note the debug line under it.
3. **Permissions:** allow location when asked.
4. **Name box (Google accounts without a saved name):** "Your name" opens with your Google name filled in. It has only **Save**. A green "Name saved." follows.

## B. Frame
5. **Top bar:** your name and a small square photo, or your initials, at the top right. Guests see "Guest" and a person icon. Tap it and the Account sheet opens.
6. **Tabs:** Radar, My Reports and Settings. A fourth tab, Dispatch, appears only for ADMIN or DISPATCHER.
7. **Report hazard button:** it shows on the Radar tab only.

## C. Radar tab (map)
8. **Map loads everyone's reports**, on both phone and web. The chip counts should match on both.
9. **Map center:** it centers on you at zoom 15. With GPS off it shows Mandaue City, and the chip says "GPS off · showing Mandaue City".
10. **Your dot:** a small dark dot with a cream ring marks your position.
11. **Pins:** round pins are colored by risk. Square number blocks are clusters, and tapping one zooms in.
12. **Search:** type `high risk`, `High`, `medium`, `pothole high`, `in progress`, `verified`, part of an `HZD-` id, or a word from a summary.
    - About 0.6 s after you stop typing, the map moves to the matches.
    - No match shows a red "No matching hazards on the map."
    - `low` should not match the word "slow".
13. **Filter chips:** All, High risk and each category show counts. Tapping one also moves the map to those pins. "All" with an empty search doesn't move the map.
14. **Bottom left:** a legend, the GPS chip, the Recenter button and the Safe route button.
    - Recenter should move you to zoom 16.
15. **Banners:** the red-orange "High-risk hazard nearby" banner appears within 100 m of a High pin. "New high-risk report" appears when someone files a new High report while you watch.
16. **Pan far out:** the map should stop at the Philippines border.
17. **Load error (only if it happens):** a red-orange "Could not load hazards. Tap to try again." label. In debug builds a box under it shows the full error, with a copy icon ("Error copied." in green).

## D. Hazard sheet
18. **Open a pin:** the sheet opens at 42% with badges, category, distance and the AI summary.
19. **Expand:** swipe up or tap "Swipe up for photo proof and voting". Check that the photo, note, recommended action and vote tally show.
20. **Voting as a guest:** tap "Still here". The Google upgrade sheet should open.
21. **Voting as Level 2 or higher:** test each case.
    - Within 200 m: green "Vote recorded."
    - Farther away: red "Voting opens within 200 m…"
    - Your own report: red "You cannot vote on your own report."
    - Voting twice: both buttons are disabled, or red "You already voted on this report."
22. **Flag button:** a Level 3 user sees a Flag button, and it asks for confirmation. Afterwards a green "Report flagged…" appears.

## E. Report wizard
23. **Open it:** tap Report hazard.
24. **Step 1, Location:** drag the map to move the pin. It stops at 100 m, and the chips show the accuracy and distance moved.
25. **Step 2, Photo:** tap the box to open the camera. The chip should show "Compressed ≤150 KB". Tap Next with no photo and a red "Take a photo of the hazard." appears.
26. **Step 3, Notes:** type a note (try Tagalog or Cebuano). An empty note gets a red "Describe the hazard in a few words."
27. **Step 4, Review:** you should see a risk badge, "Classified by Radar AI", a summary and a recommended action.
    - To test offline mode, stop the proxy and go Back, then Next. It should say "Classified offline".
28. **Publish:** a green "Report sent. Thank you." should appear. The report should appear in My Reports, and your points should go up by 10.
29. **Limit:** as a guest, file a 4th report in one day. The Google upgrade sheet should open.

## F. Ask Radar AI
30. **Open chat:** tap "Ask Radar AI".
31. **Modes:** try Risk analysis, Recommendations, Safe detour and Ask commuter (the 3-question interview).
32. **Quick prompts:** tap the chips along the bottom.
33. **Action buttons:** tap "Show … on map" and "Report a hazard".
34. **Reset:** try the restart icon and the close icon.
35. **Proxy off:** a red "Radar AI is not reachable…" block appears.

## G. Safe route
36. **Pick a destination:** tap the route button, then tap a point on the map within 10 km, past a High or Medium pin.
37. **Result:** a sage route line and a summary panel appear.
    - The line should go around High and Medium pins and say "stays X m from High and Medium hazards".
    - If no street avoids them, the panel says "Warning: passes within X m of a hazard. No safer route found."
    - Clear route removes the line.
38. **Errors (red):**
    - "Pick a destination within 10 km."
    - "Too many route requests. Wait a minute and try again." (more than 6 a minute)
    - "The route took too long to plan…"
    - "The route service is not reachable…" (check `adb reverse --list` first)

## H. My Reports
39. **Cards:** a guest card (Level 1 only), a profile card with trust points and a progress bar, and the Reports / Resolved / Accuracy numbers.
40. **Filters:** the filter chips and your report cards.
41. **Pull-to-refresh:** pull down to refresh.

## I. Settings
42. **Account:** a 64 px photo or initials, your name, and "[level title] · Level N".
43. **Edit name:** the name box opens with Cancel and Save. Saving shows a green "Name saved." The new name appears in the top bar.
44. **Change photo:** Take a photo, Choose from gallery, or Remove photo (only when you have one).
    - The photo should appear in Settings and the top bar, and a green "Photo saved." shows.
    - A red "Could not save the photo" usually means the rules weren't republished (Setup step 4).
45. **Level details:** opens the Account sheet with your level, points, progress (or "City staff level. Set by an admin."), and a "What you can do" list for your level.
46. **Guests:** see a red-orange **Sign in with Google** button in the Account section instead of Edit name and Change photo.
47. **Appearance:** Light is selected by default. Tap **Dark** and the whole app turns dark except the map tiles. Close and reopen the app, and it should still be dark. Tap **Light** to go back.
48. **Data saver:** turn it on, open a pin, and the photo should show a "Load photo" button.
49. **City staff (signed in with Google):** your name and email in a sage box.
    - **Check staff access:** green "Staff access is on…" or red "No staff role on this account yet…"
    - **Set staff password** (staff only): enter a password twice, at least 8 characters. Green "Staff password saved…" follows. The button then reads **Change staff password**.
    - **Sign out:** green "Signed out…", and you become a guest with 0 points.
50. **City staff (guest):** only the email and password form, with no Google button.
    - Your Gmail plus the staff password from step 49 should sign you in as System Administrator.
    - A wrong password gives a red "Wrong email or password."

## J. Account sheet
51. **Google sign-in (guest):** "Continue with Google" links your account. A green "Signed in with Google. You are now a Civic Scout." appears, then the "Your name" box. "Continue as guest" closes the sheet.

## K. Dispatch (ADMIN account)
52. **Queue:** KPI blocks and risk chips. Tickets are sorted High first, oldest first.
53. **Ticket actions:** Start work, Resolve (the note is required), Crew and Override AI. Each shows a green or red message.
54. **Quarantine:** a storage meter, Restore, and Purge with a confirmation.
55. **Users list:** a search box and one row per user with initials, name and role only. Your row ends with "(you)". Users without a name show "Guest" (Level 1) or "Name not set yet", never "Unnamed user".
56. **User page:** tap a row.
    - It shows the photo, name, role, status badge, points, reports, resolved and accuracy.
    - Actions: Role, Account status (suspension asks for 1, 3, 7 or 30 days) and the no-daily-limit switch. Each shows a green "… saved." message.
    - On your own page the actions are greyed out, with a red "You cannot change your own account."
57. **Analytics:** the numbers, hotspots and AI health.

## L. Dark mode pass
58. **Repeat in Dark:** switch to Dark (step 47), then go back through C to K quickly. Look for dark text on the dark background or light text on a light panel, and report the screen.

## Known items to decide on (not bugs yet)
- **Quarantine button label:** it says "Restore and verify", but the code resets the votes to 0, so it restores without verifying. Suggested fix: rename it to "Restore".
- **Staff can vote and pick a badge:** Dispatchers and Admins vote with weight 2 and see the focus-badge picker. This may not be intended.
- **Map in dark mode:** the tiles stay light while the panels around them turn dark. A dark map is possible if you want it.
- **Search moves the map:** the 0.6 s wait before it moves may feel too slow or too fast.
