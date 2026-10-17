// Google Play server-side subscription verification for Hesabaty.
// Secrets are provided as Supabase Edge Function environment secrets, NEVER
// in Flutter/GitHub. Without them purchases stay disabled and fail closed.
import { createClient } from "npm:@supabase/supabase-js@2.57.0";

const productId = "hesabaty_premium_monthly";
const packageName = "io.github.mohmoudtarek37spec.hesabaty";
const reply = (value: unknown, status = 200) => new Response(
  JSON.stringify(value),
  { status, headers: { "content-type": "application/json" } },
);

function encodeUrl(data: Uint8Array): string {
  let value = "";
  for (const byte of data) value += String.fromCharCode(byte);
  return btoa(value).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function encodedJson(data: unknown): string {
  return encodeUrl(new TextEncoder().encode(JSON.stringify(data)));
}

async function googleAccessToken(json: string): Promise<string> {
  const account = JSON.parse(json);
  if (typeof account.client_email !== "string" ||
      typeof account.private_key !== "string") {
    throw new Error("Google Play service account is incomplete");
  }
  const keyData = Uint8Array.from(
    atob(account.private_key
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "").replace(/\s/g, "")),
    (v) => v.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey("pkcs8", keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const unsigned = encodedJson({ alg: "RS256", typ: "JWT" }) + "." +
    encodedJson({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      iat: now, exp: now + 3500,
    });
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const jwt = unsigned + "." + encodeUrl(new Uint8Array(signature));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) throw new Error("Google service token unavailable");
  const result = await response.json();
  if (typeof result.access_token !== "string") {
    throw new Error("Invalid Google access token");
  }
  return result.access_token;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "POST required" }, 405);
  const authHeader = request.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return reply({ error: "Sign in first" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !serviceKey) {
    return reply({ error: "Backend auth not configured" }, 503);
  }
  const viewer = createClient(url, publishable,
    { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: account, error: authError } =
    await viewer.auth.getUser(authHeader.slice(7));
  if (authError || !account.user?.id || account.user.is_anonymous) {
    return reply({ error: "Valid account required" }, 401);
  }
  let body: Record<string, unknown>;
  try {
    body = await request.json();
    if (body == null || typeof body !== "object" || Array.isArray(body)) {
      return reply({ error: "JSON object required" }, 400);
    }
  } catch (_) {
    return reply({ error: "Invalid JSON" }, 400);
  }
  const googleAccount = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  // Explicit production gate: adding a service-account credential alone
  // must never make a purchase button available before Play Console testing.
  const ready = Boolean(googleAccount && url && serviceKey &&
    Deno.env.get("GOOGLE_PLAY_BILLING_ENABLED") === "true");
  if (body.action === "status") {
    return reply({ ready, productId });
  }
  if (!ready) return reply({ error: "Billing is not enabled yet" }, 503);
  if (body.productId !== productId ||
      typeof body.purchaseToken !== "string" ||
      body.purchaseToken.length < 12 || body.purchaseToken.length > 4096) {
    return reply({ error: "Unsupported Google Play purchase" }, 400);
  }
  const purchaseToken = body.purchaseToken;
  try {
    const accessToken = await googleAccessToken(googleAccount!);
    const path = "https://androidpublisher.googleapis.com/androidpublisher/v3" +
      "/applications/" + encodeURIComponent(packageName) +
      "/purchases/subscriptionsv2/tokens/" + encodeURIComponent(purchaseToken);
    const verifiedResponse = await fetch(path, {
      headers: { authorization: "Bearer " + accessToken },
    });
    if (!verifiedResponse.ok) {
      return reply({ verified: false, error: "Google rejected purchase" }, 403);
    }
    const purchase = await verifiedResponse.json();
    const items = Array.isArray(purchase.lineItems) ? purchase.lineItems : [];
    const purchased = items.filter((item: Record<string, unknown>) =>
      item.productId === productId && typeof item.expiryTime === "string");
    if (purchased.length === 0) {
      return reply({ verified: false, error: "Wrong subscription product" }, 403);
    }
    const expires = purchased.map((item: Record<string, string>) =>
      Date.parse(item.expiryTime)).filter((x: number) => Number.isFinite(x));
    if (expires.length === 0) return reply({ verified: false }, 403);
    const expiry = Math.max(...expires);
    const state = purchase.subscriptionState;
    const states: Record<string, string> = {
      SUBSCRIPTION_STATE_ACTIVE: "active",
      SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
      SUBSCRIPTION_STATE_CANCELED: "canceled",
      SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
      SUBSCRIPTION_STATE_EXPIRED: "expired",
    };
    const status = states[state];
    if (!status) return reply({ verified: false, error: "Not paid" }, 403);

    // Only the service role can read/write purchase token claims or entitlements.
    const admin = createClient(url, serviceKey,
      { auth: { persistSession: false, autoRefreshToken: false } });
    const hashBytes = await crypto.subtle.digest(
      "SHA-256", new TextEncoder().encode(purchaseToken));
    const tokenHash = [...new Uint8Array(hashBytes)].map((b) =>
      b.toString(16).padStart(2, "0")).join("");
    const { error: claimed } = await admin.from("play_purchase_claims")
      .insert({ token_hash: tokenHash, user_id: account.user.id });
    if (claimed) {
      const { data: owner, error: ownerError } =
        await admin.from("play_purchase_claims").select("user_id")
          .eq("token_hash", tokenHash).maybeSingle();
      if (ownerError || owner?.user_id !== account.user.id) {
        return reply({ verified: false, error: "Purchase belongs to another account" }, 403);
      }
    }
    const entitlement = {
      user_id: account.user.id,
      product_id: productId,
      status,
      source: "google_play",
      expires_at: new Date(expiry).toISOString(),
      updated_at: new Date().toISOString(),
    };
    const { error: writeError } = await admin.from("user_entitlements")
      .upsert(entitlement, { onConflict: "user_id" });
    if (writeError) return reply({ error: "Failed to store entitlement" }, 503);
    const active = ["active", "grace_period", "canceled"].includes(status) &&
      expiry > Date.now();
    return reply({ verified: true, active, expiresAt: entitlement.expires_at });
  } catch (_) {
    // Do not leak purchase tokens or service credentials in logs or responses.
    return reply({ error: "Google Play verification unavailable" }, 503);
  }
});
