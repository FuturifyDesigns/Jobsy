// supabase/functions/push-notification/index.ts
//
// Triggered by a Supabase Database Webhook on INSERT into `notifications`.
//
// Required Supabase secrets (set via `supabase secrets set`):
//   FCM_PROJECT_ID          — Firebase project ID
//   FCM_SERVICE_ACCOUNT_KEY — Full JSON of Firebase service-account key file
//   WEBHOOK_SECRET          — Shared secret configured in the webhook header
//                             (Dashboard → Database → Webhooks → HTTP Headers:
//                              X-Webhook-Secret: <your-secret>)

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_BODY_BYTES = 32 * 1024;
const JSON_HEADERS = { "Content-Type": "application/json" };

/** Must match JobsyApplication + Flutter + AndroidManifest. Bump *_vN when sound changes. */
const JOBSY_ANDROID_CHANNEL_ID = "jobsy_default_v4";
const JOBSY_ANDROID_SOUND = "soundreality_notification";

function verifyWebhookSecret(req: Request): boolean {
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (!secret) {
    console.error("WEBHOOK_SECRET is not set — rejecting request");
    return false;
  }
  const provided = req.headers.get("X-Webhook-Secret") ?? "";
  if (provided.length !== secret.length) return false;
  let mismatch = 0;
  for (let i = 0; i < secret.length; i++) {
    mismatch |= provided.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return mismatch === 0;
}

interface ServiceAccountKey {
  client_email: string;
  private_key: string;
  token_uri: string;
}

async function getAccessToken(serviceAccount: ServiceAccountKey): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = btoa(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: serviceAccount.token_uri,
      iat: now,
      exp: now + 3600,
    }),
  );

  const textEncoder = new TextEncoder();
  const inputData = textEncoder.encode(`${header}.${payload}`);

  const pemContents = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, inputData);
  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${header}.${payload}.${signatureB64}`;

  const tokenResponse = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenResponse.json();
  return tokenData.access_token;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...JSON_HEADERS, Allow: "POST" },
    });
  }

  if (!verifyWebhookSecret(req)) {
    console.warn("Unauthorized webhook call rejected");
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > MAX_BODY_BYTES) {
    return new Response(JSON.stringify({ error: "Payload too large" }), {
      status: 413,
      headers: JSON_HEADERS,
    });
  }

  try {
    const rawBody = await req.arrayBuffer();
    if (rawBody.byteLength > MAX_BODY_BYTES) {
      return new Response(JSON.stringify({ error: "Payload too large" }), {
        status: 413,
        headers: JSON_HEADERS,
      });
    }
    const body = JSON.parse(new TextDecoder().decode(rawBody));

    const record = body.record;
    if (!record) {
      return new Response(JSON.stringify({ error: "No record in payload" }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }

    const userId: string = record.user_id ?? "";
    if (!userId) {
      return new Response(JSON.stringify({ error: "Missing user_id" }), {
        status: 400,
        headers: JSON_HEADERS,
      });
    }

    const title: string = String(record.title ?? "Jobsy").slice(0, 200);
    const notifBody: string = String(record.body ?? "").slice(0, 500);
    const notifType: string = String(record.type ?? "system").slice(0, 50);
    const targetRole: string = String(record.target_role ?? "").slice(0, 20);

    const roleLabel =
      targetRole === "employer"
        ? "Employer"
        : targetRole === "worker"
        ? "Worker"
        : "";
    const pushTitle = roleLabel ? `[${roleLabel}] ${title}` : title;

    const dataPayload: Record<string, string> = {
      type: notifType,
      notification_id: String(record.id ?? ""),
    };
    if (targetRole === "employer" || targetRole === "worker") {
      dataPayload.target_role = targetRole;
    }
    if (record.related_conversation_id) {
      dataPayload.conversation_id = String(record.related_conversation_id);
    }
    if (record.related_job_id) {
      dataPayload.job_id = String(record.related_job_id);
    }
    if (record.related_application_id) {
      dataPayload.application_id = String(record.related_application_id);
    }
    if (record.related_user_id) {
      dataPayload.related_user_id = String(record.related_user_id);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (record.related_user_id) {
      const { data: senderProfile } = await supabase
        .from("profiles")
        .select("avatar_url")
        .eq("id", record.related_user_id)
        .maybeSingle();
      if (senderProfile?.avatar_url) {
        dataPayload.avatar_url = String(senderProfile.avatar_url);
      }
    }

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("fcm_token, notifications_enabled, message_alerts_enabled")
      .eq("id", userId)
      .single();

    if (profileError || !profile?.fcm_token) {
      console.log(`No FCM token for user ${userId}, skipping push`);
      return new Response(
        JSON.stringify({ skipped: true, reason: "no_fcm_token" }),
        { status: 200, headers: JSON_HEADERS },
      );
    }

    if (profile.notifications_enabled === false) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "notifications_disabled" }),
        { status: 200, headers: JSON_HEADERS },
      );
    }

    if (notifType === "new_message" && profile.message_alerts_enabled === false) {
      return new Response(
        JSON.stringify({ skipped: true, reason: "message_alerts_disabled" }),
        { status: 200, headers: JSON_HEADERS },
      );
    }

    const serviceAccount: ServiceAccountKey = JSON.parse(
      Deno.env.get("FCM_SERVICE_ACCOUNT_KEY")!,
    );
    const accessToken = await getAccessToken(serviceAccount);

    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${Deno.env.get("FCM_PROJECT_ID")!}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: { title: pushTitle, body: notifBody },
            data: dataPayload,
            android: {
              priority: "high",
              notification: {
                channel_id: JOBSY_ANDROID_CHANNEL_ID,
                sound: JOBSY_ANDROID_SOUND,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
          },
        }),
      },
    );

    const fcmResult = await fcmResponse.json();

    if (!fcmResponse.ok) {
      console.error("FCM error:", JSON.stringify(fcmResult));

      if (
        fcmResult.error?.code === 404 ||
        fcmResult.error?.code === 400 ||
        fcmResult.error?.details?.some(
          (d: { errorCode?: string }) => d.errorCode === "UNREGISTERED",
        )
      ) {
        console.log(`Clearing stale FCM token for user ${userId}`);
        await supabase
          .from("profiles")
          .update({ fcm_token: null })
          .eq("id", userId);
      }

      return new Response(JSON.stringify({ error: "FCM delivery failed" }), {
        status: 500,
        headers: JSON_HEADERS,
      });
    }

    console.log(`Push sent to ${userId}: ${pushTitle}`);
    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (err) {
    console.error("Push notification error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: JSON_HEADERS,
    });
  }
});
