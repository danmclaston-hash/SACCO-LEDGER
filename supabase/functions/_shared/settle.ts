import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { gateways, unlock } from "./gateways.ts";

/** The server's own database door. Can call the server-only functions. Never sent to apps. */
export function adminDb(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export const notifyUrl = (gateway: string) => `${Deno.env.get("SUPABASE_URL")}/functions/v1/pay-webhook?g=${gateway}`;
export const returnUrl = (gateway: string) => `${Deno.env.get("SUPABASE_URL")}/functions/v1/pay-webhook/done?g=${gateway}`;

export async function loadAccount(db: SupabaseClient, orgId: string) {
  const { data, error } = await db.from("gateway_accounts").select("*").eq("org_id", orgId).maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) throw new Error("This group has no payment gateway connected.");
  return { ...data, creds: await unlock(data.creds_enc, orgId) };
}

/**
 * Asks the gateway what happened to one payment, then records the answer.
 * Safe to run many times (webhook, return page and "Check" button can all race): the database
 * locks the row and only the first answer counts.
 */
export async function verifyAndSettle(db: SupabaseClient, payment: any) {
  // "failed" can still be checked again: a payer may retry on the same page and succeed.
  if (["paid", "needs_review"].includes(payment.status)) return payment;
  const acct = await loadAccount(db, payment.org_id);
  // The payment keeps the gateway it started with, even if the group switched since.
  if (acct.gateway !== payment.gateway) return { ...payment, verify_note: "Group changed gateway. Ask an officer to check this payment by hand." };
  const v = await gateways[payment.gateway].verify(acct.creds, payment.mode, payment.tx_ref, payment.gateway_order_id);
  if (v.state === "waiting") return { ...payment, verify_note: v.note ?? "Not paid yet" };
  const { data, error } = await db.rpc("settle_gateway_payment", {
    p_id: payment.id,
    p_ok: v.state === "paid",
    p_tx_id: v.txId ?? null,
    p_ref: v.ref ?? null,
    p_paid: v.paidMinor ?? null,
    p_currency: v.currency ?? null,
    p_method: v.method ?? null,
    p_note: v.note ?? null,
  });
  if (error) throw new Error(error.message);
  return data;
}

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
