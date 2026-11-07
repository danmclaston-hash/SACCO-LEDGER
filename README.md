# SACCO Ledger

Records and audit trail for savings groups and SACCOs in Uganda. **The app never holds money.** Groups pay through their own MTN, Airtel, bank or cash. The app keeps proof of who paid what, in each cycle.

One Flutter code base:
- **Android and iPhone apps**: for members and officers
- **Web app (installable PWA)**: for administrators only
- **One database**: Supabase (PostgreSQL)

Read also: [Simple plan](docs/PLAN.md) · [Licences](docs/LICENCES.md)

## Set it up

### Step 1: Make the database
**Why:** every phone and browser shares this one record book.
1. Go to [supabase.com](https://supabase.com), sign up, click **New project**. Pick the region closest to Uganda. Save the database password somewhere private. **Never share it.**
2. Open **SQL Editor**. Paste all of `supabase/migrations/20261106000000_init.sql` and click **Run**. Then do the same with `20261107000000_accounts.sql`, then `20261107000100_hardening.sql`, then `20261107000200_owner.sql`, then `20261107000300_goals.sql`. Order matters: each file needs the one before.
3. Open **Authentication → Providers (or Sign In) → Email**, turn **Confirm email** off. Members use phones, so no email can be confirmed.

**Check it worked:** **Table Editor** shows `journals`, `members`, `audit_log` and others.
**If it fails:** copy the red message and send it to your developer. Run on a new empty project, since the file runs only once.

### Step 2: Get two keys
**Why:** the app needs to know which database to talk to.

In **Project Settings → API** copy:
- **Project URL**
- **Publishable key** (older name: anon key). Safe inside an app: the database rules protect the data.

**Do not use** the secret / service_role key. It opens everything.

### Step 3: Give the keys to GitHub
**Why:** the build robot puts them into your apps.

GitHub repo → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**:

| Name | Value |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_KEY` | Publishable key |

Then **Settings → Pages → Source: GitHub Actions**. Then **Actions → build → Run workflow**.

**Check it worked:** all jobs go green. The Android app is under the run's **Artifacts**. Your admin site is at the address shown on the **Pages** settings.
**If it fails:** open the red step, copy the error, send it to your developer. **If Pages is refused:** GitHub Pages is free only for public repos, so make the repo public or use Cloudflare Pages (free).

### Step 4: Make yourself owner
**Why:** lets you see all groups on the web.

Sign up on the admin site with your email. Then in the Supabase SQL Editor (change the email to yours):
```sql
insert into public.platform_admins select id from auth.users where email = 'you@example.com';
```
**Check it worked:** after refresh, **All groups** shows in the side menu.

### Step 5: Try it
1. Sign in. Tick the data notice. Click **Try with demo data**.
2. On a phone, install the APK and make a second account. On the web, open **Members → Add**, and give the phone the invite code.
3. On the phone: **Channels → Record a Payment** with any test ID.
4. On the web: **Approvals**. You cannot confirm your own record, so use a different officer.

**Check it worked:** **Ledger → Trial Balance** says BALANCED, and **Check for tampering** passes.

## Run on your own computer
**Needs:** [Flutter](https://docs.flutter.dev/get-started/install) stable.
```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_KEY=your_key
```
Change `chrome` to your phone's name for the phone layout. Find it with `flutter devices`.

Database tests need Postgres: `PGHOST=localhost PGUSER=postgres PGPASSWORD=x bash supabase/tests/run.sh`. **Check:** `failed` shows 0.

## Publish

| Where | Needs | Notes |
|---|---|---|
| Google Play | Developer account (about $25 once), your own signing key | Add the key in `android/app/build.gradle.kts`. Test builds use a debug key, which Play refuses. Keep the key file out of Git |
| Apple App Store | Developer account (about $99 a year), a Mac | Open `ios/Runner.xcworkspace` in Xcode, choose your team, archive |
| Admin web | Nothing extra | Deployed by the build robot |

Before real groups: see [Licences](docs/LICENCES.md) and move to Supabase Pro for backups.

## My Account (every user)
Open it from your picture in the top bar.

| Part | What it does |
|---|---|
| Profile | Name, phone, photo. Can also update your card in your groups (shown in the audit trail) |
| Password | Change it. Asks for the current one first |
| Security | App lock PIN (and fingerprint or face on phones), sign out of all devices, last 20 sign-ins |
| Look and language | Auto, light or dark theme, text size, language. Saved on the account |
| Privacy | When you agreed to the data notice, download all your data as one file, ask to close your account |

Closing an account removes photo, phone and sign-in history, and takes the person out of their groups. **Money records stay**, because groups must keep proof. The owner finishes it on the web under **All groups**.

## Rules the system enforces
Each rule lives in the database, so no app or browser can get around it. Tests are in `supabase/tests/run_tests.sql`.

- Money rows cannot be edited or deleted. Fix mistakes with a reversal and a reason.
- Every journal balances: debits equal credits.
- Same transaction ID cannot be recorded twice in a group.
- Two people: recorder ≠ checker. Borrower ≠ approver. Approver ≠ payer. Two different witnesses.
- Meeting closes only if counted cash equals ledger cash. Two different counters.
- Emergency fund is never lent.
- Members see only their own records. Strangers see nothing.
- Share-out pays exactly the pool, by largest remainder.

## Folders
```
lib/core      money, share-out, risk, search index, licences (plain logic)
lib/data      door to the database
lib/state     what screens show
lib/ui        screens (same look as the original Android app)
supabase      database rules and tests
web           admin PWA files
android, ios  native app shells
docs          plan and licences
```
