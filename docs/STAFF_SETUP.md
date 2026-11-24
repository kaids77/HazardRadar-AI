# Staff setup (dispatchers and admins)

City staff use one of two kinds of account:

- **A Google account** (for example, the first admin). It signs in with Google, like any commuter.
- **A city-issued email account** with a password, created in the Firebase console.

The app never offers sign-up for staff. Staff access always comes from the `role` on the user's
profile in `users/{uid}`, and `firestore.rules` enforces it.

## 1. Enable sign-in methods (once per project)
1. Open https://console.firebase.google.com and select the project.
2. Go to **Build > Authentication > Sign-in method**.
3. **Google** must already be enabled (commuters use it too).
4. Only if you want email staff accounts or the "Set staff password" option: click
   **Add new provider > Email/Password**, switch **Enable** on (leave "Email link" off), and click **Save**.

## 2. Create the staff account

### Option A: Google account
1. On a phone or in Chrome, open the app and sign in with Google (Settings > **Sign in with Google**,
   or tap the name at the top right).
2. Enter your name when the app asks. This creates the profile.

### Option B: city-issued email account
1. In **Authentication**, open the **Users** tab and click **Add user**.
2. Enter the staff email and a strong password, then click **Add user**.
3. In the app, go to **Settings > City staff**, and sign in with that email and password.
   This creates the user's profile as Level 1.

## 3. Give the account its role
The first admin must be set in the console. After that, admins change roles inside the app
(**Dispatch > Users**, tap the person, then **Role**).

1. Copy the user's **User UID** from **Authentication > Users**.
2. Go to **Build > Firestore Database > Data**, open the `users` collection, and open the document with that UID.
3. Edit these fields (type: string for role, number for tier):
   - Dispatcher: `role` = `DISPATCHER`, `tier` = `4`
   - Admin: `role` = `ADMIN`, `tier` = `5`
4. In the app, switch tabs or pull down in Settings to reload the profile. A **Dispatch** tab appears.
   For a Google account, **Settings > City staff > Check staff access** confirms it with a green message.

## 4. Optional: a password for a Google admin
A Google account has no password, so the **Sign in as staff** email form rejects its Gmail with
"Wrong email or password." To use that form as well (for example, on a shared office computer):

1. Turn on **Email/Password** (step 1.4).
2. Sign in with Google, then open **Settings > City staff > Set staff password**.
3. Enter a password twice (at least 8 characters) and tap **Save**.

The password is added to the same account, so the role, points, and reports stay the same. From then on
the staff form accepts the Gmail address and that password. The button then reads **Change staff password**.

## What each role can do
- **Dispatcher (Level 4):** the Dispatch queue. Assign crews, override the AI rating, move tickets
  ACTIVE -> IN_PROGRESS -> RESOLVED (resolving needs a note and gives the reporter +10 points),
  and restore quarantined reports.
- **Admin (Level 5):** everything a dispatcher can do, plus user management (role, account status,
  and the emergency no-daily-limit switch), permanent purge of quarantined reports, and analytics.
  Admins cannot change their own account.

## Moderation guideline (warn, suspend, ban)
Staff see who filed each report: the Queue and Quarantine cards show "Reported by [name] · [level]",
and tapping it opens the user's page. Dispatchers can read that page; only admins can act on it.

The user page has a **Report history**: trust points, reports, resolved, accuracy, **Quarantined now**
(the user's reports hidden from the map right now) and **Removed as spam** (reports an admin purged).
Below it, a **Suggested** line follows this guideline. Restored and resolved reports never count.

| Quarantined now + removed as spam | Account status | Suggested action |
|---|---|---|
| 0 or 1 | any | No action |
| 2 or more | Active | Warn |
| 3 or more | Warned | Suspend for 7 days |
| 5 or more | Suspended (after a suspension) | Consider a ban |

The suggestion is a hint only. The app never warns, suspends, or bans anyone by itself, and it moves one
step at a time. Offensive or clearly fake content can justify faster action; the admin decides. Before
acting, review the reports in Quarantine: a report can be quarantined by mistake, and restoring it
removes it from the count.

**Privacy:** reporter names stay inside the staff tools. The public Report transparency list never
names anyone on quarantined, restored, or removed reports. A name appears only on a resolved report,
and only when that reporter turned on **Settings > Show my name on my resolved reports**.

## If something goes wrong
| Problem | Fix |
|---|---|
| No Dispatch tab | `role` must be exactly `ADMIN` or `DISPATCHER`, on the document whose id is the account's User UID. Switch tabs to reload. |
| Staff form rejects a Gmail address | Use Google sign-in, or set a staff password (section 4). |
| "Email sign-in is off for this project" | Turn on Email/Password (step 1.4). |
| "For security, sign out, sign in with Google again, then set the password." | Firebase wants a recent sign-in. Do exactly that. |
