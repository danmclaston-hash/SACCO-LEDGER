// Gateways knock here when something happens. No sign-in (gateways cannot sign in), so:
//   1. we read ONLY which payment it is about,
//   2. we look up that payment and the group's own keys,
//   3. we ask the gateway's verify API ourselves. The notification's amount or status is never trusted.
//
//   POST/GET ?g=flutterwave|pesapal   notification from the gateway
//   GET /done?g=...                   where the payer lands after paying (also triggers a check)
import { sameSecret } from "../_shared/gateways.ts";
import { adminDb, loadAccount, verifyAndSettle } from "../_shared/settle.ts";

const text = (msg: string, status = 200) => new Response(msg, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const gateway = url.searchParams.get("g") ?? "";
  const isReturn = url.pathname.endsWith("/done");
  const db = adminDb();

  // Which payment? Flutterwave sends tx_ref; Pesapal sends OrderTrackingId + OrderMerchantReference (= our tx_ref).
  let body: any = {};
  if (req.method === "POST") {
    try {
      body = await req.json();
    } catch (_) { /* Pesapal GET style or empty */ }
  }
  const txRef: string | null = body?.data?.tx_ref ?? body?.txRef ?? url.searchParams.get("tx_ref") ??
    url.searchParams.get("OrderMerchantReference") ?? body?.OrderMerchantReference ?? null;
  const orderId: string | null = url.searchParams.get("OrderTrackingId") ?? body?.OrderTrackingId ?? null;

  if (!txRef || !txRef.startsWith("SL-")) {
    return isReturn ? text("Payment page closed. Go back to SACCO Ledger and tap Check.") : text("ignored", 200);
  }

  const { data: p } = await db.from("gateway_payments").select("*").eq("tx_ref", txRef).maybeSingle();
  if (!p || p.gateway !== gateway) {
    return isReturn ? text("We could not find this payment. Go back to SACCO Ledger.") : text("unknown", 200);
  }

  try {
    // Flutterwave: if the group set a secret hash, the notification must carry it.
    if (!isReturn && gateway === "flutterwave") {
      const acct = await loadAccount(db, p.org_id);
      const want = acct.creds.webhook_hash;
      const got = req.headers.get("verif-hash") ?? "";
      if (want && !sameSecret(got, want)) return text("bad signature", 401);
    }
    // Pesapal tells us its order id; keep it if we did not have it (only if it matches nothing else).
    if (gateway === "pesapal" && orderId && !p.gateway_order_id) {
      await db.from("gateway_payments").update({ gateway_order_id: orderId }).eq("id", p.id).is("gateway_order_id", null);
      p.gateway_order_id = orderId;
    }
    const r = await verifyAndSettle(db, p);
    if (isReturn) {
      const msg = r.status === "paid"
        ? "Payment confirmed by the gateway and recorded. You can close this page and go back to SACCO Ledger."
        : r.status === "failed"
        ? "The payment did not go through. Go back to SACCO Ledger and try again."
        : r.status === "needs_review"
        ? "Payment received. An officer will check it. Go back to SACCO Ledger."
        : "Still waiting for the gateway. Go back to SACCO Ledger and tap Check in a minute.";
      return text(msg);
    }
    if (gateway === "pesapal") {
      // Pesapal expects this exact answer.
      return new Response(JSON.stringify({
        orderNotificationType: url.searchParams.get("OrderNotificationType") ?? "IPNCHANGE",
        orderTrackingId: orderId,
        orderMerchantReference: txRef,
        status: 200,
      }), { headers: { "Content-Type": "application/json" } });
    }
    return text("ok");
  } catch (e) {
    console.error("pay-webhook", txRef, (e as Error).message);
    // 500 makes the gateway try again later, which is what we want if we could not check.
    return isReturn ? text("Could not check right now. Go back to SACCO Ledger and tap Check.") : text("retry", 500);
  }
});
