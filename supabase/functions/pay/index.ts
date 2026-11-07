// Online payments, called by the app. Needs a signed-in person.
//   save_keys : group admin or treasurer connects the group's OWN Flutterwave or Pesapal account
//   start     : makes a checkout page for one payment
//   check     : "Is it paid yet?" Asks the gateway, then records the answer
import { createClient } from "npm:@supabase/supabase-js@2";
import { gateways, lock, type Mode } from "../_shared/gateways.ts";
import { adminDb, cors, json, loadAccount, notifyUrl, returnUrl, verifyAndSettle } from "../_shared/settle.ts";

const purposeText: Record<string, string> = {
  shares: "Shares",
  savings: "Savings",
  fine: "Fine",
  loan_repayment: "Loan repayment",
  emergency_contribution: "Emergency fund",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  // Who is asking? The person's own sign-in token, checked by Supabase.
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: who } = await asUser.auth.getUser(auth.replace(/^Bearer /i, ""));
  const user = who?.user;
  if (!user) return json({ error: "Please sign in again." }, 401);

  const db = adminDb();
  let body: any;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Bad request." }, 400);
  }

  try {
    // ---------- Connect the group's own gateway ----------
    if (body.action === "save_keys") {
      const { org_id, gateway, mode } = body;
      if (!gateways[gateway]) return json({ error: "Choose Flutterwave or Pesapal." }, 400);
      if (mode !== "test" && mode !== "live") return json({ error: "Choose Test or Live." }, 400);
      const { data: allowed } = await db.rpc("can_manage_gateway", { p_org: org_id, p_user: user.id });
      if (!allowed) return json({ error: "Only the group admin or treasurer can connect a payment gateway." }, 403);

      const creds: Record<string, string> = gateway === "flutterwave"
        ? { secret_key: String(body.secret_key ?? "").trim(), webhook_hash: String(body.webhook_hash ?? "").trim() }
        : { consumer_key: String(body.consumer_key ?? "").trim(), consumer_secret: String(body.consumer_secret ?? "").trim() };
      const { ipnId } = await gateways[gateway].connect(creds, mode as Mode, notifyUrl(gateway)); // proves the keys work
      const visible = gateway === "flutterwave" ? creds.secret_key : creds.consumer_key;
      const { error } = await db.rpc("save_gateway_account", {
        p_org: org_id,
        p_user: user.id,
        p_gateway: gateway,
        p_mode: mode,
        p_hint: visible.slice(-4),
        p_creds_enc: await lock(creds, org_id),
        p_ipn_id: ipnId,
      });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, webhook_url: notifyUrl(gateway) });
    }

    // ---------- Start one payment ----------
    if (body.action === "start") {
      // Runs as the person, so all the group rules (own money, active loan, open goal...) apply.
      const { data: g, error } = await asUser.rpc("create_gateway_payment", {
        p_org: body.org_id,
        p_member: body.member_id,
        p_purpose: body.purpose,
        p_amount: body.amount,
        p_loan: body.loan_id ?? null,
        p_goal: body.goal_id ?? null,
        p_note: body.note ?? null,
      });
      if (error) return json({ error: error.message }, 400);
      try {
        const acct = await loadAccount(db, g.org_id);
        const started = await gateways[g.gateway].start(acct.creds, g.mode, {
          txRef: g.tx_ref,
          amountMinor: Number(g.amount),
          currency: g.currency,
          title: g.org_name,
          description: `${purposeText[g.purpose] ?? g.purpose} for ${g.member_name} (${g.tx_ref})`,
          name: g.member_name,
          email: g.member_email ?? user.email ?? "",
          phone: g.member_phone ? `+${g.member_phone}` : null,
          returnUrl: returnUrl(g.gateway),
          ipnId: acct.ipn_id,
        });
        await db.rpc("gateway_payment_started", { p_id: g.id, p_url: started.url, p_order: started.orderId });
        return json({ id: g.id, tx_ref: g.tx_ref, checkout_url: started.url });
      } catch (e) {
        // Could not reach the gateway: mark it failed so nobody waits for it.
        await db.rpc("settle_gateway_payment", {
          p_id: g.id, p_ok: false, p_tx_id: null, p_ref: null, p_paid: null, p_currency: null, p_method: null,
          p_note: String((e as Error).message).slice(0, 300),
        });
        return json({ error: (e as Error).message }, 502);
      }
    }

    // ---------- Is it paid yet? ----------
    if (body.action === "check") {
      const { data: allowed } = await db.rpc("can_see_gateway_payment", { p_id: body.id, p_user: user.id });
      if (!allowed) return json({ error: "Payment not found." }, 404);
      const { data: p } = await db.from("gateway_payments").select("*").eq("id", body.id).single();
      const r = await verifyAndSettle(db, p);
      return json({ id: r.id, status: r.status, verify_note: r.verify_note ?? null });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error).message }, 400);
  }
});
