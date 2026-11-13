# SACCO Ledger

Records and audit trail for savings groups and SACCOs in Uganda. **The app never holds money.** Groups pay through their own MTN, Airtel, bank or cash. The app keeps proof of who paid what, in each cycle.

One Flutter code base:
- **Android and iPhone apps**: for members and officers
- **Web app (installable PWA)**: for administrators only
- **One database**: Supabase (PostgreSQL)

Read also: [Simple plan](docs/PLAN.md) · [Licences](docs/LICENCES.md) · [Privacy policy](docs/PRIVACY.md)

## Set it up

### Step 1: Make the database
**Why:** every phone and browser shares this one record book.
1. Go to [supabase.com](https://supabase.com), sign up, click **New project**. Pick the region closest to Uganda. Save the database password somewhere private. **Never share it.**
2. Open **SQL Editor**. Paste all of `supabase/migrations/20261106000000_init.sql` and click **Run**. Then do the same with `20261107000000_accounts.sql`, then `20261107000100_hardening.sql`, then `20261107000200_owner.sql`, then `20261107000300_goals.sql`, then `20261107000400_online_payments.sql`, then `20261107000500_countries_prefs.sql`, then `20261107000600_loan_rules.sql`, then `20261107000700_owners_shared_demo.sql`, then `20261107000800_real_emails.sql`, then `20261110000000_look.sql`, then `20261113000000_circle_invites.sql`. Order matters: each file needs the one before.
3. Open **Authentication → Providers (or Sign In) → Email** and leave **Confirm email** on, so every new email account must click a link before it can sign in (see Step 8).

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
1. Sign in. Tick the data notice. Click **Look around the shared demo**. Everyone shares one demo group and can look at every screen but not change it. To try changing things, create your own group.
2. On a phone, install the APK and make a second account. On the web, open **Members → Add**, and give the phone the invite code.
3. On the phone: **Channels → Record a Payment** with any test ID.
4. On the web: **Approvals**. You cannot confirm your own record, so use a different officer.

**Check it worked:** **Ledger → Trial Balance** says BALANCED, and **Check for tampering** passes.

### Step 5b: Put the admin site on Cloudflare (optional, free)
**Why:** your own address (like `admin.yourcompany.com`), fast in Africa. The build robot makes the site and creates the Cloudflare project by itself. You only give it two keys.

1. **Get a Cloudflare token.** Cloudflare → **My Profile → API Tokens → Create Token → Create Custom Token**. Permission: **Account → Cloudflare Pages → Edit**. Create it and copy it.
   **Keep it secret.** Paste it only into GitHub, never into a chat.
2. **Get your Account ID.** Cloudflare home → **Workers & Pages**. It is on the right side. Copy it.
3. **Give both to GitHub.** Repo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `CLOUDFLARE_API_TOKEN` = the token
   - `CLOUDFLARE_ACCOUNT_ID` = the Account ID
   - Optional, under **Variables**: `CLOUDFLARE_PROJECT` = a name. Without it the site is called `sacco-ledger`.
4. **Start a build.** Repo → **Actions → Build → Run workflow** (or push anything).
5. **Let sign-in come back to the new address.** Supabase → **Authentication → URL Configuration → Redirect URLs** → add `https://sacco-ledger.pages.dev/**` (your name if you set one).

**Check it worked:** in Actions, **deploy-cloudflare** is green and the "Upload the site" step prints a `pages.dev` link. Open it: you see the sign-in page.
**If it fails:**
- "Authentication error": the token or Account ID is wrong, or the token lacks *Cloudflare Pages: Edit*. Make a new token.
- "Project name already taken": set `CLOUDFLARE_PROJECT` to another name.
- Skipped: the two secrets are not saved with exactly those names.
**Own address:** Cloudflare → your Pages project → **Custom domains → Set up a domain**. Then add it in Supabase step 5 too.

### Step 6: Switch on online payments (optional)
**Why:** members pay through Flutterwave or Pesapal. The gateway confirms each payment and our server asks it again, so nobody types a transaction ID and nobody can fake one. Money goes to the **group's own** gateway account, never to you.

1. Install the [Supabase CLI](https://supabase.com/docs/guides/cli). In this folder run `supabase login`, then `supabase link`.
2. Make a lock key (32 random bytes) and give it to the server:
   ```bash
   supabase secrets set GATEWAY_ENC_KEY=$(openssl rand -base64 32)
   ```
   **Keep it safe.** If it is lost, every group must paste their keys again.
3. Send the two server functions:
   ```bash
   supabase functions deploy pay
   supabase functions deploy pay-webhook --no-verify-jwt
   ```
   `--no-verify-jwt` is only for `pay-webhook`, because gateways cannot sign in. It trusts nothing it is sent: it always asks the gateway itself.
4. In the admin site, open the group, then **Group Settings → Online payments → Connect a gateway**. Paste the group's own keys:
   - **Flutterwave:** Settings → API keys → Secret key. Make up a long webhook secret hash. Then, in Flutterwave **Settings → Webhooks**, paste the URL the app shows and the same hash.
   - **Pesapal:** consumer key and consumer secret. Notifications set themselves up.

**Test first:** test keys work only in a **demo** group, so pretend money never enters a real group's books. Use Flutterwave's test keys there, tap **Channels → Pay online**, and pay with their test number.
**Check it worked:** the payment shows **PAID**, the ledger shows a new journal with the gateway's ID, and **Check for tampering** passes.
**If it fails:** the app shows the gateway's own message (usually a wrong key or wrong mode). For notifications, open Supabase **Edge Functions → pay-webhook → Logs**.

| What happens | Result |
|---|---|
| Gateway says paid, right amount | Posts at once. Audit trail notes the gateway ID and receipt |
| Wrong amount or currency | Kept as a pending record. An officer checks it in **Approvals** |
| Same gateway ID twice | Refused, flagged for an officer |
| Payer cancels | Marked failed. Nothing posts. **Check** again if they retry |

### Step 7: Your platform team (owners and admins)
**Why:** fellow developers can help run and test the platform without your password, and without you opening the database.

- **Admin:** can open every group to look and help.
- **Owner:** an admin who can also add, promote and remove team members.
- **Founder** (`danmclaston@gmail.com`): always an owner. Nobody can remove or demote it.

Web → **All groups → Platform team**:
1. **People who signed up** lists everyone, newest first, with their email and join date. Tap the person icon → **Make admin** or **Make owner**.
2. Or type an email under **Add by email**, pick Admin or Owner, tap **Add**. Not signed up yet? They get that role the moment they sign up.
3. Change someone later with the **⋮** menu: Make owner, Make admin only, Remove from team.

People always choose their own password. Every change goes in a history nobody can edit.
**Check it worked:** they sign in on the web and see **All groups**. After **Remove**, it disappears for them.
**If it fails:** "Only the platform owner" means you are signed in as an admin, not an owner.

### Step 8: Real emails only (stop fake accounts)

You cannot tell a real email from a fake one by looking at it: `fads@gmail.com` looks fine. The only proof is a link sent to the inbox and clicked. Google sign-in is already proved by Google.

1. **Turn on the link.** Supabase → **Authentication → Sign In / Providers → Email** → switch **Confirm email** on → Save.
2. **Let the link come back.** **Authentication → URL Configuration**: Site URL `https://sacco-ledger.pages.dev`; Redirect URLs add `https://sacco-ledger.pages.dev/**` and `com.saccoledger.app://login-callback`.
3. **Use a real mail sender.** Supabase's built-in sender only sends a few emails an hour and often lands in Spam. Make a free account at [Resend](https://resend.com) or [Brevo](https://www.brevo.com), add your domain (once the company domain is ready), and copy its SMTP details into **Authentication → Emails → SMTP Settings**. Until then the built-in sender works for testing.
4. **Turn on the gatekeeper.** **Authentication → Hooks → Add hook → Before User Created** → type **Postgres** → schema `public`, function `hook_before_user_created` → Save. It refuses throwaway inboxes (mailinator and similar), addresses that are not real email shapes, and new phone-number accounts (paused until WhatsApp/SMS codes exist). Phone accounts already made keep working.
5. **Clean up.** In the app: **Platform team → People who signed up**. ✓ means proved, ? means never proved. Owners tap ⋮ → **Block (fake account)**. They are signed out at once. Nothing is deleted, and **Unblock** undoes it. Every block is in the history.

## Run on your own computer
**Needs:** [Flutter](https://docs.flutter.dev/get-started/install) stable.
```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_KEY=your_key
```
Change `chrome` to your phone's name for the phone layout. Find it with `flutter devices`.

Database tests need Postgres: `PGHOST=localhost PGUSER=postgres PGPASSWORD=x bash supabase/tests/run.sh`. **Check:** `failed` shows 0.

## Phone apps

### Android: test now (free)
Every build makes the Android app by itself.
- **Easiest:** open your site and tap **Get the Android app** (`https://sacco-ledger.pages.dev/download/sacco-ledger.apk`). Works on almost every phone made since 2017.
- **Or:** GitHub → **Actions** → newest green run → **Artifacts** → `android-apk` (works on every phone, bigger file).

To install, the phone asks to allow "install unknown apps" for your browser. Say yes once.
**Check it worked:** the SACCO Ledger icon appears and opens the sign-in page.
**If it fails:** "App not installed" usually means an older copy signed with a different key. Uninstall it, then install again.

### Android: your own key (do this before sharing widely)
**Why:** the test key is public. Your own key proves updates really come from you. Google Play needs it. Change it later and everyone must uninstall and reinstall, so do it early.

1. On a computer with Java, make the key (choose your own passwords, write them down safely):
   ```bash
   keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Turn it into text: `base64 -w0 upload.jks > upload.txt` (Mac: `base64 -i upload.jks -o upload.txt`).
3. GitHub → **Settings → Secrets and variables → Actions → New repository secret**, four times:

   | Name | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | everything inside `upload.txt` |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` |
   | `ANDROID_KEY_PASSWORD` | the key password |
4. **Back up `upload.jks` and the passwords** somewhere safe (not in Git, not in chat). Then delete `upload.txt`.

**Check it worked:** the next build log says "Signing with your own key", and Artifacts has `android-play-store-aab`.

### Google Play
1. Make a **Google Play Console** account (about $25 once). A company account needs your company papers and a D-U-N-S number.
2. **Create app**, fill in the store listing, privacy policy and data safety form.
3. Upload `android-play-store-aab` to **Internal testing** first. Turn on **Play App Signing** (Google then keeps the final key safe).

### iPhone (iOS)
Apple only lets signed apps onto iPhones, even for testing. You need:
1. An **Apple Developer Program** account (about $99 a year). Enrol as your company once it is registered (needs a D-U-N-S number).
2. Then tell me. The build robot can sign and send each build to **TestFlight** (Apple's free tester app) with an App Store Connect API key, so no Mac is needed.

Today the robot only checks that the iPhone app builds.

| Where | Needs | Notes |
|---|---|---|
| Android test APK | Nothing | Built every push, also on your site |
| Google Play | Developer account (about $25 once), your own key | See above |
| Apple App Store / TestFlight | Developer account (about $99 a year) | See above |
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
- Online payments post only after our server asks the gateway itself. Test keys only in demo groups. Gateway keys are locked and no app can read them.
- Only the owner adds or removes platform administrators. The owner cannot be removed.

## Folders
```
lib/core      money, share-out, risk, search index, licences (plain logic)
lib/data      door to the database
lib/state     what screens show
lib/ui        screens (same look as the original Android app)
supabase      database rules, tests, and server functions for online payments
web           admin PWA files
android, ios  native app shells
docs          plan and licences
```
