// Talks to payment gateways. Each gateway is one small "adapter" with the same 4 jobs,
// so adding another country's gateway later means adding one adapter, nothing else.
//
// Golden rule: we NEVER believe what a notification says. We only use it to know WHICH payment
// to check, then we ask the gateway's own verify API with the group's secret key.

export type Creds = Record<string, string>;
export type Mode = "test" | "live";

export interface StartInput {
  txRef: string;
  amountMinor: number;
  currency: string;
  description: string;
  title: string;
  name: string;
  email: string;
  phone: string | null;
  returnUrl: string;
  ipnId: string | null;
}

export interface Verified {
  state: "paid" | "failed" | "waiting";
  txId?: string;
  ref?: string | null;
  paidMinor?: number;
  currency?: string;
  method?: string | null;
  note?: string;
}

export interface Gateway {
  /** Checks the keys work. Returns extra setup (Pesapal's notification id). Throws a clear message if not. */
  connect(creds: Creds, mode: Mode, notifyUrl: string): Promise<{ ipnId: string | null }>;
  /** Makes a checkout page. Returns where to send the payer. */
  start(creds: Creds, mode: Mode, p: StartInput): Promise<{ url: string; orderId: string | null }>;
  /** Asks the gateway itself what happened. */
  verify(creds: Creds, mode: Mode, txRef: string, orderId: string | null): Promise<Verified>;
}

/** UGX, TZS, RWF have no cents. KES has 100. Same rule as the app (lib/core/money.dart). */
export const decimals = (currency: string) => (currency === "KES" ? 2 : 0);
export const toMajor = (minor: number, currency: string) => minor / 10 ** decimals(currency);
export const toMinor = (major: number, currency: string) => Math.round(Number(major) * 10 ** decimals(currency));

async function call(url: string, init: RequestInit, who: string): Promise<any> {
  let res: Response;
  try {
    res = await fetch(url, { ...init, signal: AbortSignal.timeout(20000) });
  } catch (_) {
    throw new Error(`${who} did not answer. Try again in a minute.`);
  }
  const text = await res.text();
  let body: any = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch (_) {
    body = { message: text.slice(0, 200) };
  }
  return { ok: res.ok, status: res.status, body };
}

// ---------------- Flutterwave (30+ African countries) ----------------
const FLW = "https://api.flutterwave.com/v3";
const flwHeaders = (c: Creds) => ({ Authorization: `Bearer ${c.secret_key}`, "Content-Type": "application/json" });

export const flutterwave: Gateway = {
  async connect(c, mode) {
    if (!c.secret_key?.startsWith("FLWSECK")) throw new Error("That is not a Flutterwave secret key. It starts with FLWSECK.");
    const isTest = c.secret_key.includes("_TEST");
    if (isTest !== (mode === "test")) throw new Error(isTest ? "This is a TEST key. Choose Test mode." : "This is a LIVE key. Choose Live mode.");
    const r = await call(`${FLW}/balances`, { headers: flwHeaders(c) }, "Flutterwave");
    if (r.status === 401 || r.status === 403) throw new Error("Flutterwave refused this key. Copy it again from Settings → API keys.");
    if (!r.ok) throw new Error(`Flutterwave said: ${r.body?.message ?? r.status}`);
    return { ipnId: null };
  },

  async start(c, _mode, p) {
    const r = await call(`${FLW}/payments`, {
      method: "POST",
      headers: flwHeaders(c),
      body: JSON.stringify({
        tx_ref: p.txRef,
        amount: toMajor(p.amountMinor, p.currency),
        currency: p.currency,
        redirect_url: p.returnUrl,
        customer: { email: p.email, phonenumber: p.phone ?? undefined, name: p.name },
        customizations: { title: p.title.slice(0, 60), description: p.description.slice(0, 100) },
      }),
    }, "Flutterwave");
    const link = r.body?.data?.link;
    if (!r.ok || !link) throw new Error(`Flutterwave could not start the payment: ${r.body?.message ?? r.status}`);
    return { url: link, orderId: null };
  },

  async verify(c, _mode, txRef) {
    const r = await call(`${FLW}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(txRef)}`, { headers: flwHeaders(c) }, "Flutterwave");
    const d = r.body?.data;
    if (!r.ok || !d) return { state: "waiting", note: r.body?.message ?? "Not paid yet" }; // not found yet = still waiting
    if (d.tx_ref !== txRef) return { state: "waiting", note: "Gateway answered for a different reference. Ignored." };
    if (d.status === "successful") {
      return {
        state: "paid",
        txId: String(d.id),
        ref: d.flw_ref ?? null,
        paidMinor: toMinor(d.amount, d.currency),
        currency: d.currency,
        method: d.payment_type ?? null,
      };
    }
    if (d.status === "failed" || d.status === "cancelled") return { state: "failed", note: `Flutterwave: ${d.status}` };
    return { state: "waiting", note: `Flutterwave: ${d.status}` };
  },
};

// ---------------- Pesapal (East and Southern Africa) ----------------
const pesapalBase = (mode: Mode) => (mode === "live" ? "https://pay.pesapal.com/v3/api" : "https://cybqa.pesapal.com/pesapalv3/api");

async function pesapalToken(c: Creds, mode: Mode): Promise<string> {
  const r = await call(`${pesapalBase(mode)}/Auth/RequestToken`, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ consumer_key: c.consumer_key, consumer_secret: c.consumer_secret }),
  }, "Pesapal");
  if (!r.body?.token) {
    throw new Error(`Pesapal refused these keys${mode === "test" ? " (Test mode needs sandbox keys)" : ""}: ${r.body?.error?.message ?? r.body?.message ?? r.status}`);
  }
  return r.body.token;
}

const pesapalHeaders = (token: string) => ({ Authorization: `Bearer ${token}`, Accept: "application/json", "Content-Type": "application/json" });

export const pesapal: Gateway = {
  async connect(c, mode, notifyUrl) {
    if (!c.consumer_key || !c.consumer_secret) throw new Error("Enter both the consumer key and consumer secret.");
    const token = await pesapalToken(c, mode);
    const r = await call(`${pesapalBase(mode)}/URLSetup/RegisterIPN`, {
      method: "POST",
      headers: pesapalHeaders(token),
      body: JSON.stringify({ url: notifyUrl, ipn_notification_type: "GET" }),
    }, "Pesapal");
    if (!r.body?.ipn_id) throw new Error(`Pesapal could not save our notification address: ${r.body?.error?.message ?? r.status}`);
    return { ipnId: r.body.ipn_id };
  },

  async start(c, mode, p) {
    const token = await pesapalToken(c, mode);
    const r = await call(`${pesapalBase(mode)}/Transactions/SubmitOrderRequest`, {
      method: "POST",
      headers: pesapalHeaders(token),
      body: JSON.stringify({
        id: p.txRef,
        currency: p.currency,
        amount: toMajor(p.amountMinor, p.currency),
        description: p.description.slice(0, 100),
        callback_url: p.returnUrl,
        notification_id: p.ipnId,
        billing_address: { email_address: p.email, phone_number: p.phone ?? "", first_name: p.name.slice(0, 50) },
      }),
    }, "Pesapal");
    if (!r.body?.redirect_url) throw new Error(`Pesapal could not start the payment: ${r.body?.error?.message ?? r.status}`);
    return { url: r.body.redirect_url, orderId: r.body.order_tracking_id };
  },

  async verify(c, mode, txRef, orderId) {
    if (!orderId) return { state: "waiting", note: "No Pesapal order yet" };
    const token = await pesapalToken(c, mode);
    const r = await call(`${pesapalBase(mode)}/Transactions/GetTransactionStatus?orderTrackingId=${encodeURIComponent(orderId)}`,
      { headers: pesapalHeaders(token) }, "Pesapal");
    const d = r.body ?? {};
    if (d.merchant_reference !== txRef && d.status_code === 1) return { state: "waiting", note: "Gateway answered for a different reference. Ignored." };
    // status_code: 1 COMPLETED, 2 FAILED, 3 REVERSED, 0 INVALID (often: not paid yet)
    if (d.status_code === 1) {
      return {
        state: "paid",
        txId: orderId,
        ref: d.confirmation_code ?? null,
        paidMinor: toMinor(d.amount, d.currency),
        currency: d.currency,
        method: d.payment_method ?? null,
      };
    }
    if (d.status_code === 2 || d.status_code === 3) return { state: "failed", note: `Pesapal: ${d.payment_status_description}` };
    return { state: "waiting", note: `Pesapal: ${d.payment_status_description ?? "not paid yet"}` };
  },
};

export const gateways: Record<string, Gateway> = { flutterwave, pesapal };

// ---------------- Keys are locked before they reach the database ----------------
// AES-GCM with a key only the server knows (GATEWAY_ENC_KEY). The group id is mixed in,
// so a locked key copied to another group cannot be unlocked there.
async function aesKey(): Promise<CryptoKey> {
  const raw = Deno.env.get("GATEWAY_ENC_KEY");
  if (!raw) throw new Error("Server is missing GATEWAY_ENC_KEY. See README, online payments step.");
  const bytes = Uint8Array.from(atob(raw), (ch) => ch.charCodeAt(0));
  if (bytes.length !== 32) throw new Error("GATEWAY_ENC_KEY must be 32 random bytes in base64.");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function lock(creds: Creds, orgId: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new TextEncoder().encode(JSON.stringify(creds));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: new TextEncoder().encode(orgId) }, await aesKey(), data));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv);
  out.set(ct, iv.length);
  return btoa(String.fromCharCode(...out));
}

export async function unlock(blob: string, orgId: string): Promise<Creds> {
  const all = Uint8Array.from(atob(blob), (ch) => ch.charCodeAt(0));
  const pt = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: all.slice(0, 12), additionalData: new TextEncoder().encode(orgId) },
    await aesKey(),
    all.slice(12),
  );
  return JSON.parse(new TextDecoder().decode(pt));
}

/** Constant-time compare, so a wrong webhook secret cannot be guessed letter by letter. */
export function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
