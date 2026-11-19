# Staff setup (dispatchers and admins)

City staff sign in with email and password. The app never offers sign-up; accounts
are created in the Firebase console. Roles are stored in `users/{uid}` and enforced by
`firestore.rules`.

## 1. Enable email sign-in (once per project)
1. Open https://console.firebase.google.com and select the project.
2. Go to **Build > Authentication > Sign-in method**.
3. Click **Add new provider > Email/Password**, switch **Enable** on (leave "Email link" off), and click **Save**.

## 2. Create a staff account
1. In **Authentication**, open the **Users** tab and click **Add user**.
2. Enter the staff email and a strong password, then click **Add user**.
3. On a phone or in Chrome, open the app, go to **Settings > City staff**, and sign in with that email.
   This creates the user's profile as Level 1.

## 3. Give the account its role
The first admin must be set in the console. After that, admins promote staff inside the app.

1. Copy the user's **User UID** from **Authentication > Users**.
2. Go to **Build > Firestore Database > Data**, open the `users` collection, and open the document with that UID.
3. Edit these fields (type: string for role, number for tier):
   - Dispatcher: `role` = `DISPATCHER`, `tier` = `4`
   - Admin: `role` = `ADMIN`, `tier` = `5`
4. In the app, go to **Settings** and pull the profile again by switching tabs, or sign out and back in.
   A **Dispatch** tab appears.

## What each role can do
- **Dispatcher (Level 4):** the Dispatch queue. Assign crews, override the AI rating, move tickets
  ACTIVE -> IN_PROGRESS -> RESOLVED (resolving needs a note and gives the reporter +10 points),
  and restore quarantined reports.
- **Admin (Level 5):** everything a dispatcher can do, plus user management, permanent purge of
  quarantined reports, and analytics.
