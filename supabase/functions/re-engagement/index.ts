// supabase/functions/re-engagement/index.ts
//
// Scheduled Edge Function — nudges inactive users via notifications → push webhook.
// Schedule in Supabase Dashboard → Edge Functions → re-engagement → Schedules:
//   Cron: 0 10 * * *  (daily 10:00 UTC)
//
// Auth: Supabase cron sends Authorization: Bearer <SERVICE_ROLE_KEY>.
//       Manual/cron-job runners can also use Authorization: Bearer <CRON_SECRET>.
//
// Optional test query (when authorized): ?min_days=1  lowers the first tier floor.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_BODY_BYTES = 8 * 1024;
const JSON_HEADERS = { "Content-Type": "application/json" };
const PAGE_SIZE = 500;
const RE_ENGAGEMENT_COOLDOWN_DAYS = 3;

interface ReEngagementTier {
  minDaysInactive: number;
  maxDaysInactive: number;
  messages: { title: string; body: string }[];
}

const TIERS: ReEngagementTier[] = [
  {
    minDaysInactive: 1,
    maxDaysInactive: 2,
    messages: [
      {
        title: "Still looking for work?",
        body: "New jobs were posted near you on Jobsy. Take a quick look.",
      },
      {
        title: "Jobsy update",
        body: "There may be new opportunities waiting in your area.",
      },
    ],
  },
  {
    minDaysInactive: 3,
    maxDaysInactive: 6,
    messages: [
      {
        title: "New opportunities waiting!",
        body: "Check out the latest jobs posted near you on Jobsy.",
      },
      {
        title: "Don't miss out!",
        body: "New jobs have been posted since your last visit. Take a look!",
      },
      {
        title: "Jobsy misses you!",
        body: "Come back and see what's new in your area.",
      },
    ],
  },
  {
    minDaysInactive: 7,
    maxDaysInactive: 13,
    messages: [
      {
        title: "Your next opportunity awaits",
        body: "Workers and employers are connecting on Jobsy right now. Jump back in!",
      },
      {
        title: "Jobs are filling up fast",
        body: "Don't let the best opportunities pass you by. Open Jobsy now!",
      },
    ],
  },
  {
    minDaysInactive: 14,
    maxDaysInactive: 60,
    messages: [
      {
        title: "We miss you!",
        body: "It's been a while! Jobsy has new features and fresh job listings waiting for you.",
      },
      {
        title: "Ready to get back to it?",
        body: "Your Jobsy profile is still active. Come see what's new!",
      },
    ],
  },
];

function pickRandom<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/** Accept Supabase dashboard schedules (service role) OR external cron (CRON_SECRET). */
function verifyCronAuth(req: Request): boolean {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!bearer) return false;

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (serviceKey && bearer === serviceKey) return true;

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && bearer === cronSecret) return true;

  return false;
}

function resolveLastSeen(user: {
  last_seen_at?: string | null;
  created_at?: string | null;
}): Date | null {
  const raw = user.last_seen_at ?? user.created_at;
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function daysInactive(lastSeen: Date, now: Date): number {
  return Math.floor((now.getTime() - lastSeen.getTime()) / (1000 * 60 * 60 * 24));
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...JSON_HEADERS, Allow: "POST" },
    });
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (contentLength > MAX_BODY_BYTES) {
    return new Response(JSON.stringify({ error: "Payload too large" }), {
      status: 413,
      headers: JSON_HEADERS,
    });
  }

  if (!verifyCronAuth(req)) {
    console.warn("Unauthorized re-engagement call rejected");
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  try {
    const url = new URL(req.url);
    const minDaysOverride = Number(url.searchParams.get("min_days") ?? "0");
    const effectiveMinDays = Number.isFinite(minDaysOverride) && minDaysOverride > 0
      ? Math.floor(minDaysOverride)
      : null;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const now = new Date();
    let sentCount = 0;
    let scanned = 0;
    let skippedActive = 0;
    let skippedRecent = 0;
    let skippedDisabled = 0;
    let skippedNoTimestamp = 0;
    let insertErrors = 0;
    let page = 0;
    let hasMore = true;

    while (hasMore) {
      const from = page * PAGE_SIZE;
      const to = from + PAGE_SIZE - 1;

      const { data: candidates, error: queryError } = await supabase
        .from("profiles")
        .select("id, last_seen_at, created_at, user_type, notifications_enabled")
        .range(from, to);

      if (queryError) {
        console.error("Query error:", queryError.message);
        return new Response(JSON.stringify({ error: "Internal server error" }), {
          status: 500,
          headers: JSON_HEADERS,
        });
      }

      if (!candidates || candidates.length < PAGE_SIZE) {
        hasMore = false;
      }
      if (!candidates || candidates.length === 0) break;

      for (const user of candidates) {
        scanned++;

        if (user.notifications_enabled === false) {
          skippedDisabled++;
          continue;
        }

        const lastSeen = resolveLastSeen(user);
        if (!lastSeen) {
          skippedNoTimestamp++;
          continue;
        }

        const inactiveDays = daysInactive(lastSeen, now);

        const tier = TIERS.find((t) => {
          const min = effectiveMinDays != null
            ? Math.max(t.minDaysInactive, effectiveMinDays)
            : t.minDaysInactive;
          return inactiveDays >= min && inactiveDays <= t.maxDaysInactive;
        });

        if (!tier) {
          skippedActive++;
          continue;
        }

        const cooldownStart = new Date(
          now.getTime() - RE_ENGAGEMENT_COOLDOWN_DAYS * 24 * 60 * 60 * 1000,
        );
        const { data: recentReEngagement } = await supabase
          .from("notifications")
          .select("id")
          .eq("user_id", user.id)
          .eq("type", "re_engagement")
          .gte("created_at", cooldownStart.toISOString())
          .limit(1);

        if (recentReEngagement && recentReEngagement.length > 0) {
          skippedRecent++;
          continue;
        }

        const message = pickRandom(tier.messages);
        const targetRole = user.user_type === "employer" ? "employer" : "worker";

        const { error: insertError } = await supabase.from("notifications").insert({
          user_id: user.id,
          type: "re_engagement",
          title: message.title,
          body: message.body,
          target_role: targetRole,
        });

        if (insertError) {
          insertErrors++;
          console.error(`Failed to insert re-engagement for ${user.id}:`, insertError);
          continue;
        }

        sentCount++;
      }

      page++;
    }

    const summary = {
      sent: sentCount,
      scanned,
      skipped_active: skippedActive,
      skipped_recent: skippedRecent,
      skipped_disabled: skippedDisabled,
      skipped_no_timestamp: skippedNoTimestamp,
      insert_errors: insertErrors,
      min_days_override: effectiveMinDays,
    };

    console.log("Re-engagement run:", JSON.stringify(summary));

    return new Response(JSON.stringify(summary), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (err) {
    console.error("Re-engagement error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: JSON_HEADERS,
    });
  }
});
