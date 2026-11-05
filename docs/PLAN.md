# Simple plan: SACCO Ledger

This replaces the big AQODH OOS plan for now. It keeps that plan's best ideas and drops what a small start does not need.

## What it is

A record book that nobody can quietly change. Money moves on MTN, Airtel, bank or cash, in the group's **own** account. The app keeps the proof: who paid, how much, which cycle, which transaction ID, who checked it.

**Not** a bank. **Not** a wallet. It never touches money.

## Kept from the AQODH plan

| Idea | How it shows up here |
|---|---|
| "Record and reconcile, do not move money" | The whole product |
| Append-only double-entry ledger, integer money | `journals`, `journal_lines`, triggers stop edits |
| One check for every sensitive action | Every write is a rule-checked database function |
| Tamper-evident audit log | Hash chain, with a "Check for tampering" button |
| Tenant isolation in the database | `org_id` on rows, row-level security, tested |
| Mobile first, weak signal | Saved last view; payment records queue without signal |
| Golden money tests | Worked Examples A and B run on the app code and the database |

## Changed to keep it simple

| AQODH plan | Now | Why |
|---|---|---|
| Separate API, workers, queues, cloud set-up | Supabase only | One thing to run. Nearly free to start |
| Web app only (PWA) | One Flutter code base: Android, iOS, web | You asked for it |
| Same web app for everyone | Web is admin only. Members use phone apps | You asked for it |
| Rules engine, form builder, workflow engine | Fixed rules with group settings (share price, limit, interest, quorum) | Not needed for first groups. Add when group number 2 truly differs |
| SMS, projects, billing | Later | Saves money and time |
| Phone login by SMS code | Phone + password + invite code from the secretary | SMS costs money. The code proves who joined |

## Database: Supabase (PostgreSQL)

| Choice | Cost | Good | Bad |
|---|---|---|---|
| **Supabase** (chosen) | Free to try, $25 a month Pro | Real SQL, built-in login, row security, no server | Free plan pauses after 7 days idle |
| Firebase | Pay per use | Easy | Double-entry is hard. One estimate says 2 to 5 times Supabase Pro |
| Neon | From $19 a month | Cheap when idle | You must add login and an API yourself |

**Rule: use Free for testing. Move to Pro before real money records.** Pro is the plan that gives regular backups. Losing a ledger is worse than $25. Prices from [this 2026 summary](https://toolradar.com/blog/supabase-pricing-2026); check Supabase's own page before paying.

## How one payment flows

1. Member pays the group's MoMo on their own phone (`*165#`). MTN moves the money.
2. Member types the transaction ID in the app. Status: **pending**. Ledger unchanged.
3. Treasurer checks the group's MoMo statement. A different person must confirm.
4. Confirmed: a balanced journal posts, audit row added.
5. Mistake: reverse with a reason. The old row stays forever.

Cash handed to an officer during an open meeting posts at once, since the room is the witness. The meeting closes only if counted cash equals ledger cash.

## Roadmap (gates, not dates)

| Gate | Pass when | Status |
|---|---|---|
| 1. Code | Database tests and code checks pass | Done here; full build runs on GitHub |
| 2. Run | Supabase set up, web live, APK on your phone, one test cycle done | You, with README |
| 3. Legal | PDPO registered, lawyer's letter (see `LICENCES.md`) | You |
| 4. Pilot | One real group, about 30 members. Treasurer signs opening balances. One full cycle, cash matches | Move to Pro first |
| 5. Grow | Group 2 and 3. Only then think about SMS alerts or auto-matching MoMo statements | Later |

**Stop rule:** if the trial balance ever fails, stop adding features and fix that first.

## Known limits (honest)

- Opening balances: enter each member's old savings as a normal cash record. No bulk import yet.
- Translations: only the words from the old app are in Luganda and Swahili. The rest show in English. A native speaker should check them.
- Statement export: PDF and copy-as-CSV. Other reports (balance sheet, UMRA quarterly) are not built.
- Withdrawals are blocked while a member has an active loan, and there are no guarantors beyond 2 witnesses.
- A database owner can still switch off the edit block. The hash chain shows if that was used on the audit trail. A regular copy of the latest hash kept outside gives stronger proof.
