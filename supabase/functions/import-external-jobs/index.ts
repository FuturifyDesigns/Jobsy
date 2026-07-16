// supabase/functions/import-external-jobs/index.ts
//
// Rate-limit friendly web job importer for Botswana boards + Google Jobs + Facebook.
// Each cron run touches only a SUBSET of sources (round-robin), not all at once.
//
// Recommended schedule: 0 */8 * * *  (every 8 hours)
//   ≈ 3 runs/day × 1 SerpAPI call = ~90 SerpAPI calls/month (under free tier)
//   ≈ 3 runs/day × 4 RSS feeds = 12 RSS fetches/day
//
// Secrets: SERPAPI_API_KEY (optional), CRON_SECRET (optional)
// Auth: Authorization: Bearer <service_role JWT from Dashboard> or CRON_SECRET

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const JSON_HEADERS = { "Content-Type": "application/json" };

/** Min hours between SerpAPI calls (Google Jobs quota protection). */
const SERPAPI_COOLDOWN_HOURS = 8;
/** RSS feeds fetched per cron run. */
const RSS_BATCH_SIZE = 4;
/** Delay between HTTP requests (ms). */
const REQUEST_DELAY_MS = 2800;
/** Max jobs upserted per run (DB write cap). */
const MAX_UPSERTS_PER_RUN = 120;

interface NormalizedJob {
  external_id: string;
  source: string;
  title: string;
  description: string;
  category: string;
  location: string;
  company_name: string | null;
  salary_text: string | null;
  external_url: string;
  contact_email: string | null;
  contact_phone: string | null;
  posted_at: string | null;
  expires_at: string | null;
  metadata: Record<string, unknown>;
}

interface RssSource {
  id: string;
  url: string;
  label: string;
  defaultLocation: string;
}

interface ImportState {
  rss_source_index: number;
  serpapi_query_index: number;
  last_serpapi_at: string | null;
}

const CATEGORY_RULES: { category: string; keywords: string[] }[] = [
  { category: "Construction", keywords: ["construction", "builder", "civil", "site engineer", "quantity surveyor"] },
  { category: "Cleaning", keywords: ["clean", "cleaner", "housekeeper", "janitor", "domestic worker"] },
  { category: "Plumbing", keywords: ["plumb", "pipefitter", "pipe fitter"] },
  { category: "Electrical", keywords: ["electric", "electrician", "wireman", "hvac"] },
  { category: "Carpentry", keywords: ["carpent", "joiner", "woodwork", "cabinet"] },
  { category: "Painting", keywords: ["paint", "decorator", "painter"] },
  { category: "Gardening", keywords: ["garden", "landscap", "groundskeeper", "horticult"] },
  { category: "Welding", keywords: ["weld", "fabricat", "boilermaker"] },
  { category: "Masonry", keywords: ["mason", "bricklay", "tiler", "tiling"] },
  { category: "Roofing", keywords: ["roof", "thatch"] },
  { category: "General Labor", keywords: ["general worker", "labour", "laborer", "handyman", "helper", "packer", "warehouse", "mining"] },
  { category: "Administrative", keywords: ["admin", "secretary", "receptionist", "office clerk", "data captur", "personal assistant"] },
  { category: "Retail & Sales", keywords: ["retail", "sales", "cashier", "shop assistant", "merchandis", "store manager"] },
  { category: "Hospitality", keywords: ["hotel", "restaurant", "chef", "cook", "waiter", "waitress", "bartender", "hospitality", "housekeeping"] },
  { category: "Security", keywords: ["security", "guard", "watchman"] },
  { category: "Transport & Driving", keywords: ["driver", "driving", "logistics", "courier", "delivery", "truck", "fleet"] },
  { category: "Healthcare", keywords: ["nurse", "doctor", "clinical", "medical", "pharmacy", "healthcare", "caregiver"] },
  { category: "Technology", keywords: ["software", "developer", "programmer", "it support", "network", "cyber", "data analyst", "tech"] },
  { category: "Finance", keywords: ["accountant", "finance", "bookkeep", "audit", "banking", "teller"] },
];

/** SerpAPI queries — ONE per run, rotated via external_import_state. */
const SERPAPI_QUERIES = [
  "jobs in Botswana",
  "jobs Gaborone",
  "jobs Francistown",
  "jobs Maun Botswana",
  "construction jobs Botswana",
  "driver jobs Botswana",
  "cleaning jobs Botswana",
  "retail jobs Botswana",
  "admin jobs Botswana",
  "IT jobs Botswana",
];

/** Facebook public posts — discovered via Google site: search (1 query per SerpAPI turn). */
const FACEBOOK_SERPAPI_QUERIES = [
  'site:facebook.com "hiring" Botswana',
  'site:facebook.com jobs Gaborone',
  'site:facebook.com "vacancy" Botswana',
  'site:facebook.com "we are hiring" Francistown',
  'site:facebook.com jobs Maun Botswana',
  'site:facebook.com "job opportunity" Botswana',
  'site:facebook.com/groups jobs Botswana hiring',
  'site:facebook.com "now hiring" Gaborone',
];

const FACEBOOK_JOB_SIGNAL =
  /\b(hiring|vacancy|vacancies|job\s+opening|position\s+available|we\s+are\s+hiring|now\s+hiring|recruit|employment|career|apply\s+now|opportunity|wanted|urgently|looking\s+for)\b/i;

/** Botswana & regional boards (RSS / WordPress job feeds). Rotated 2 per run. */
const RSS_SOURCES: RssSource[] = [
  { id: "indeed_bw", url: "https://bw.indeed.com/rss?q=&l=Botswana", label: "Indeed", defaultLocation: "Botswana" },
  { id: "indeed_gaborone", url: "https://bw.indeed.com/rss?q=&l=Gaborone", label: "Indeed", defaultLocation: "Gaborone" },
  { id: "indeed_francistown", url: "https://bw.indeed.com/rss?q=&l=Francistown", label: "Indeed", defaultLocation: "Francistown" },
  { id: "indeed_construction", url: "https://bw.indeed.com/rss?q=construction&l=Botswana", label: "Indeed", defaultLocation: "Botswana" },
  { id: "indeed_driver", url: "https://bw.indeed.com/rss?q=driver&l=Botswana", label: "Indeed", defaultLocation: "Botswana" },
  { id: "indeed_hospitality", url: "https://bw.indeed.com/rss?q=hospitality&l=Botswana", label: "Indeed", defaultLocation: "Botswana" },
  { id: "skyjobs", url: "https://skyjobs.co.bw/feed/?post_type=job_listing", label: "Sky Jobs", defaultLocation: "Botswana" },
  { id: "skyjobs_feed", url: "https://skyjobs.co.bw/feed/", label: "Sky Jobs", defaultLocation: "Botswana" },
  { id: "jobcentral", url: "https://www.jobcentralbotswana.work/feed/", label: "Jobcentral", defaultLocation: "Botswana" },
  { id: "joblist_bw", url: "https://joblist.co.bw/feed/", label: "Joblist", defaultLocation: "Botswana" },
  { id: "alljobspo", url: "https://jobsinbotswana.alljobspo.com/rss", label: "AllJobs BW", defaultLocation: "Botswana" },
  { id: "hirebw", url: "https://hire.co.bw/feed/", label: "Hire BW", defaultLocation: "Botswana" },
];

/** Accept CRON_SECRET, env service key, or any bearer that can read import state. */
async function verifyCronAuth(req: Request): Promise<boolean> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return false;

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && bearer === cronSecret) return true;

  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (serviceKey && bearer === serviceKey) return true;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) return false;

  const probe = createClient(supabaseUrl, bearer, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error } = await probe.from("external_import_state").select("id").limit(1);
  return !error;
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function categorizeJob(title: string, description: string): string {
  const text = `${title} ${description}`.toLowerCase();
  let best = "Other";
  let bestScore = 0;
  for (const rule of CATEGORY_RULES) {
    let score = 0;
    for (const kw of rule.keywords) {
      if (text.includes(kw)) score += kw.length > 8 ? 3 : 2;
    }
    if (score > bestScore) {
      bestScore = score;
      best = rule.category;
    }
  }
  return best;
}

function extractContacts(text: string): { email: string | null; phone: string | null } {
  const emails = [
    ...text.matchAll(/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/gi),
  ]
    .map((m) => m[0].toLowerCase())
    .filter((e) => !e.endsWith(".png") && !e.endsWith(".jpg"));
  const emailMatch = emails[0] ?? null;

  const phoneMatch = text.match(
    /(?:\+267|267)?[\s-]?(?:7[1-8]|3[12])[\s-]?\d{3}[\s-]?\d{4}|\b\d{3}[\s-]?\d{4}\b/,
  );
  return {
    email: emailMatch,
    phone: phoneMatch?.[0]?.replace(/\s+/g, " ").trim() ?? null,
  };
}

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&#(\d+);/g, (_, code) => {
      const n = parseInt(code, 10);
      return Number.isFinite(n) && n > 0 && n <= 0x10FFFF ? String.fromCharCode(n) : _;
    })
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => {
      const n = parseInt(hex, 16);
      return Number.isFinite(n) && n > 0 && n <= 0x10FFFF ? String.fromCharCode(n) : _;
    })
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&ndash;/g, "–")
    .replace(/&mdash;/g, "—")
    .replace(/&hellip;/g, "…")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&#\d{2,5}(?!;)/g, "");
}

function stripHtml(html: string): string {
  return decodeHtmlEntities(
    html
      .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim(),
  );
}

function enhanceImageUrl(url: string, forLogo = false): string {
  let u = url.trim();
  const lower = u.toLowerCase();

  if (lower.includes("encrypted-tbn") || lower.includes("tbn:")) {
    return u.replace(/=s\d+(-c)?$/g, "");
  }

  if (lower.includes("googleusercontent.com")) {
    const target = forLogo ? 256 : 1200;
    u = u.replace(/=s\d+(-c)?(?=&|$)/g, `=s${target}`);
    if (!u.includes("=s")) u = `${u}=s${target}`;
    return u;
  }

  if (!forLogo) {
    u = u.replace(/=w\d+-h\d+/g, "=w1200-h800");
  }
  return u;
}

function extractFirstImage(html: string): string | null {
  const match = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  if (!match?.[1]) return null;
  const url = match[1].trim();
  return url.startsWith("http") ? enhanceImageUrl(url) : null;
}

function hashString(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  }
  return Math.abs(h).toString(36);
}

function parsePostedAt(raw: string | undefined): string | null {
  if (!raw) return null;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** End-of-day UTC for a parsed closing date (vacancy open through that calendar day). */
function endOfVacancyDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 23, 59, 59, 999));
}

function tryParseDate(raw: string): Date | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  // YYYY-MM-DD
  const iso = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) {
    const d = new Date(Date.UTC(+iso[1], +iso[2] - 1, +iso[3], 12, 0, 0));
    return Number.isNaN(d.getTime()) ? null : d;
  }

  // DD/MM/YYYY or DD-MM-YYYY
  const dmy = trimmed.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})$/);
  if (dmy) {
    let year = +dmy[3];
    if (year < 100) year += 2000;
    const d = new Date(Date.UTC(year, +dmy[2] - 1, +dmy[1], 12, 0, 0));
    return Number.isNaN(d.getTime()) ? null : d;
  }

  const d = new Date(trimmed);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Pull closing / apply-by date from listing text; fallback from posted date. */
function resolveExpiresAt(
  text: string,
  postedAt: string | null,
  extensions?: Record<string, string>,
): { expires_at: string; closing_label: string | null } {
  const haystack = `${text} ${extensions?.posted_at ?? ""}`;
  const patterns = [
    /closing\s*date\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})/i,
    /closing\s*date\s*[:\-]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
    /closing\s*date\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})/i,
    /apply\s*by\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})/i,
    /apply\s*by\s*[:\-]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
    /deadline\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})/i,
    /deadline\s*[:\-]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
    /closes?\s*(?:on|by)?\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})/i,
    /closes?\s*(?:on|by)?\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})/i,
    /valid\s*until\s*[:\-]?\s*(\d{4}-\d{2}-\d{2})/i,
  ];

  for (const pattern of patterns) {
    const match = haystack.match(pattern);
    if (!match?.[1]) continue;
    const parsed = tryParseDate(match[1]);
    if (parsed) {
      return {
        expires_at: endOfVacancyDay(parsed).toISOString(),
        closing_label: match[1],
      };
    }
  }

  if (postedAt) {
    const posted = new Date(postedAt);
    if (!Number.isNaN(posted.getTime())) {
      const fallback = new Date(posted);
      fallback.setUTCDate(fallback.getUTCDate() + 30);
      return { expires_at: endOfVacancyDay(fallback).toISOString(), closing_label: null };
    }
  }

  const fallback = new Date();
  fallback.setUTCDate(fallback.getUTCDate() + 45);
  return { expires_at: endOfVacancyDay(fallback).toISOString(), closing_label: null };
}

function extractLocation(text: string, fallback: string): string {
  const cities = [
    "Gaborone", "Francistown", "Maun", "Serowe", "Kasane", "Palapye",
    "Molepolole", "Mogoditshane", "Tlokweng", "Lobatse", "Selibe Phikwe",
    "Jwaneng", "Orapa", "Letlhakane", "Ramotswa",
  ];
  const lower = text.toLowerCase();
  for (const city of cities) {
    if (lower.includes(city.toLowerCase())) return city;
  }
  return fallback;
}

function extractCompanyFromTitle(title: string): string | null {
  const parts = title.split(" - ");
  if (parts.length >= 2) return parts[parts.length - 1].trim().slice(0, 200);
  const dash = title.split(" – ");
  if (dash.length >= 2) return dash[dash.length - 1].trim().slice(0, 200);
  return null;
}

function parseRssItems(xml: string): { title: string; link: string; description: string; pubDate: string | null }[] {
  const items: { title: string; link: string; description: string; pubDate: string | null }[] = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let match;
  while ((match = itemRegex.exec(xml)) !== null) {
    const block = match[1];
    const link = extractTag(block, "link") || extractAtomLink(block);
    items.push({
      title: stripHtml(extractTagRaw(block, "title") || extractTag(block, "title")),
      link,
      description:
        extractTagRaw(block, "description") ||
        extractTagRaw(block, "content:encoded") ||
        extractTagRaw(block, "summary"),
      pubDate: extractTag(block, "pubDate") || extractTag(block, "published") || null,
    });
  }
  return items.filter((i) => i.title && i.link);
}

function extractTag(block: string, tag: string): string {
  const raw = extractTagRaw(block, tag);
  return raw ? stripHtml(raw) : "";
}

function extractTagRaw(block: string, tag: string): string {
  const escaped = tag.replace(":", "\\:");
  const re = new RegExp(`<${escaped}[^>]*>([\\s\\S]*?)<\\/${escaped}>`, "i");
  const m = block.match(re);
  return m ? m[1].trim() : "";
}

function extractAtomLink(block: string): string {
  const m = block.match(/<link[^>]+href=["']([^"']+)["']/i);
  return m?.[1] ?? "";
}

async function loadImportState(supabase: SupabaseClient): Promise<ImportState> {
  const { data } = await supabase
    .from("external_import_state")
    .select("rss_source_index, serpapi_query_index, last_serpapi_at")
    .eq("id", 1)
    .maybeSingle();

  return {
    rss_source_index: data?.rss_source_index ?? 0,
    serpapi_query_index: data?.serpapi_query_index ?? 0,
    last_serpapi_at: data?.last_serpapi_at ?? null,
  };
}

async function saveImportState(
  supabase: SupabaseClient,
  state: ImportState,
  summary: Record<string, unknown>,
): Promise<void> {
  await supabase.from("external_import_state").upsert({
    id: 1,
    rss_source_index: state.rss_source_index % RSS_SOURCES.length,
    serpapi_query_index: state.serpapi_query_index,
    last_serpapi_at: state.last_serpapi_at,
    last_run_at: new Date().toISOString(),
    last_run_summary: summary,
    updated_at: new Date().toISOString(),
  });
}

function shouldRunSerpAPI(state: ImportState): boolean {
  if (!state.last_serpapi_at) return true;
  const last = new Date(state.last_serpapi_at).getTime();
  const hours = (Date.now() - last) / (1000 * 60 * 60);
  return hours >= SERPAPI_COOLDOWN_HOURS;
}

async function fetchGoogleJobsOneQuery(
  apiKey: string,
  query: string,
): Promise<NormalizedJob[]> {
  const results: NormalizedJob[] = [];
  const params = new URLSearchParams({
    engine: "google_jobs",
    q: query,
    location: "Botswana",
    gl: "bw",
    hl: "en",
    api_key: apiKey,
  });

  const res = await fetch(`https://serpapi.com/search.json?${params}`);
  if (!res.ok) {
    console.warn(`SerpAPI HTTP ${res.status} for "${query}"`);
    return results;
  }

  const data = await res.json();
  if (data.error) {
    console.warn(`SerpAPI error: ${data.error}`);
    return results;
  }

  const jobs = (data.jobs_results ?? []) as Record<string, unknown>[];
  for (const job of jobs) {
    const jobId = String(job.job_id ?? "");
    const rawTitle = String(job.title ?? "").trim();
    if (!rawTitle) continue;
    const title = stripHtml(rawTitle);

    const applyOptions = (job.apply_options ?? []) as { link?: string }[];
    const link = applyOptions.find((o) => o.link)?.link ?? String(job.share_link ?? "");
    if (!link) continue;

    const description = stripHtml(String(job.description ?? "").trim());
    const location = stripHtml(String(job.location ?? "Botswana").trim());
    const company = job.company_name ? stripHtml(String(job.company_name)) : null;
    const contacts = extractContacts(`${title} ${description}`);
    const extensions = (job.detected_extensions ?? {}) as Record<string, string>;
    const thumbnail = job.thumbnail ? enhanceImageUrl(String(job.thumbnail).trim(), true) : null;
    const postedAt = parsePostedAt(extensions.posted_at);
    const vacancy = resolveExpiresAt(description, postedAt, extensions);

    results.push({
      external_id: jobId ? `google_jobs:${jobId}` : `google_jobs:${hashString(link)}`,
      source: "google_jobs",
      title: title.slice(0, 200),
      description: description.slice(0, 5000),
      category: categorizeJob(title, description),
      location: location.slice(0, 200),
      company_name: company?.slice(0, 200) ?? null,
      salary_text: extensions.salary ?? null,
      external_url: link,
      contact_email: contacts.email,
      contact_phone: contacts.phone,
      posted_at: postedAt,
      expires_at: vacancy.expires_at,
      metadata: {
        query,
        board: "Google Jobs",
        image_url: thumbnail?.startsWith("http") ? thumbnail : null,
        job_type: extensions.schedule_type ?? extensions.work_from_home ?? null,
        posted_label: extensions.posted_at ?? null,
        closing_label: vacancy.closing_label,
      },
    });
  }

  return results;
}

async function fetchFacebookJobsOneQuery(
  apiKey: string,
  query: string,
): Promise<NormalizedJob[]> {
  const results: NormalizedJob[] = [];
  const params = new URLSearchParams({
    engine: "google",
    q: query,
    location: "Botswana",
    gl: "bw",
    hl: "en",
    num: "20",
    api_key: apiKey,
  });

  const res = await fetch(`https://serpapi.com/search.json?${params}`);
  if (!res.ok) {
    console.warn(`SerpAPI Facebook/Google HTTP ${res.status} for "${query}"`);
    return results;
  }

  const data = await res.json();
  if (data.error) {
    console.warn(`SerpAPI Facebook error: ${data.error}`);
    return results;
  }

  const organic = (data.organic_results ?? []) as Record<string, unknown>[];
  for (const row of organic) {
    const link = String(row.link ?? "").trim();
    if (!link || !/facebook\.com/i.test(link)) continue;

    const rawTitle = String(row.title ?? "").trim();
    if (!rawTitle) continue;
    const title = stripHtml(rawTitle);
    const snippet = stripHtml(String(row.snippet ?? "").trim());
    const haystack = `${title} ${snippet}`;
    if (!FACEBOOK_JOB_SIGNAL.test(haystack)) continue;

    const contacts = extractContacts(haystack);
    const postedAt = typeof row.date === "string" ? parsePostedAt(row.date) : null;
    const vacancy = resolveExpiresAt(haystack, postedAt);

    let company: string | null = null;
    const companyMatch = title.match(/^(.+?)\s+(is hiring|hiring|jobs?)\b/i);
    if (companyMatch?.[1]) {
      company = stripHtml(companyMatch[1]).slice(0, 200);
    }

    results.push({
      external_id: `facebook:${hashString(link)}`,
      source: "facebook",
      title: title.slice(0, 200),
      description: (snippet || haystack).slice(0, 5000),
      category: categorizeJob(title, snippet),
      location: extractLocation(haystack, "Botswana").slice(0, 200),
      company_name: company,
      salary_text: null,
      external_url: link,
      contact_email: contacts.email,
      contact_phone: contacts.phone,
      posted_at: postedAt,
      expires_at: vacancy.expires_at,
      metadata: {
        query,
        board: "Facebook",
        image_url: null,
        posted_label: typeof row.date === "string" ? row.date : null,
        closing_label: vacancy.closing_label,
      },
    });
  }

  return results;
}

async function fetchRssSource(source: RssSource): Promise<NormalizedJob[]> {
  const results: NormalizedJob[] = [];

  const res = await fetch(source.url, {
    headers: {
      "User-Agent": "JobsyImporter/1.0 (+https://jobsy.app; Botswana job aggregator)",
      Accept: "application/rss+xml, application/xml, text/xml, */*",
    },
  });

  if (!res.ok) {
    console.warn(`RSS ${source.id}: HTTP ${res.status}`);
    return results;
  }

  const xml = await res.text();
  if (!xml.includes("<item") && !xml.includes(":item")) {
    console.warn(`RSS ${source.id}: no items in feed`);
    return results;
  }

  const items = parseRssItems(xml);
  for (const item of items) {
    const rawDescription = item.description ?? "";
    const imageUrl = extractFirstImage(rawDescription);
    const description = stripHtml(rawDescription);
    const contacts = extractContacts(`${description} ${item.title}`);
    const postedAt = item.pubDate ? new Date(item.pubDate).toISOString() : null;
    const vacancy = resolveExpiresAt(`${description} ${item.title}`, postedAt);

    results.push({
      external_id: `${source.id}:${hashString(item.link)}`,
      source: source.id,
      title: item.title.slice(0, 200),
      description: description.slice(0, 5000),
      category: categorizeJob(item.title, description),
      location: extractLocation(`${description} ${item.title}`, source.defaultLocation),
      company_name: extractCompanyFromTitle(item.title),
      salary_text: null,
      external_url: item.link,
      contact_email: contacts.email,
      contact_phone: contacts.phone,
      posted_at: postedAt,
      expires_at: vacancy.expires_at,
      metadata: {
        board: source.label,
        feed: source.url,
        image_url: imageUrl,
        posted_label: item.pubDate ? new Date(item.pubDate).toLocaleDateString("en-GB") : null,
        closing_label: vacancy.closing_label,
      },
    });
  }

  return results;
}

function pickRssBatch(startIndex: number): { sources: RssSource[]; nextIndex: number } {
  const sources: RssSource[] = [];
  let idx = startIndex % RSS_SOURCES.length;
  for (let i = 0; i < RSS_BATCH_SIZE; i++) {
    sources.push(RSS_SOURCES[idx]);
    idx = (idx + 1) % RSS_SOURCES.length;
  }
  return { sources, nextIndex: idx };
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...JSON_HEADERS, Allow: "POST" },
    });
  }

  if (!(await verifyCronAuth(req))) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: JSON_HEADERS,
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const state = await loadImportState(supabase);
    const serpKey = Deno.env.get("SERPAPI_API_KEY") ?? "";
    const collected: NormalizedJob[] = [];
    const runLog: Record<string, unknown> = {
      rss_fetched: [] as string[],
      serpapi_query: null as string | null,
      serpapi_engine: null as string | null,
      serpapi_skipped_cooldown: false,
    };

    // ── SerpAPI: alternate Google Jobs + Facebook (site:facebook.com), 1 query/run ─
    if (serpKey && shouldRunSerpAPI(state)) {
      const turn = state.serpapi_query_index;
      const isFacebook = turn % 2 === 1;

      if (isFacebook) {
        const fbIdx = Math.floor(turn / 2) % FACEBOOK_SERPAPI_QUERIES.length;
        const query = FACEBOOK_SERPAPI_QUERIES[fbIdx];
        runLog.serpapi_query = query;
        runLog.serpapi_engine = "facebook";
        const fbJobs = await fetchFacebookJobsOneQuery(serpKey, query);
        collected.push(...fbJobs);
        console.log(`SerpAPI Facebook "${query}": ${fbJobs.length} jobs`);
      } else {
        const gIdx = Math.floor(turn / 2) % SERPAPI_QUERIES.length;
        const query = SERPAPI_QUERIES[gIdx];
        runLog.serpapi_query = query;
        runLog.serpapi_engine = "google_jobs";
        const googleJobs = await fetchGoogleJobsOneQuery(serpKey, query);
        collected.push(...googleJobs);
        console.log(`SerpAPI Google Jobs "${query}": ${googleJobs.length} jobs`);
      }

      state.last_serpapi_at = new Date().toISOString();
      state.serpapi_query_index = turn + 1;
      await sleep(REQUEST_DELAY_MS);
    } else if (serpKey) {
      runLog.serpapi_skipped_cooldown = true;
      console.log("SerpAPI skipped — cooldown active");
    }

    // ── RSS boards: 2 feeds per run, round-robin ────────────────────────────
    const { sources: rssBatch, nextIndex } = pickRssBatch(state.rss_source_index);
    state.rss_source_index = nextIndex;

    for (const source of rssBatch) {
      try {
        const jobs = await fetchRssSource(source);
        collected.push(...jobs);
        (runLog.rss_fetched as string[]).push(`${source.id}:${jobs.length}`);
        console.log(`RSS ${source.id}: ${jobs.length} jobs`);
      } catch (e) {
        console.warn(`RSS ${source.id} failed:`, e);
        (runLog.rss_fetched as string[]).push(`${source.id}:error`);
      }
      await sleep(REQUEST_DELAY_MS);
    }

    // Dedupe
    const byId = new Map<string, NormalizedJob>();
    for (const job of collected) byId.set(job.external_id, job);
    const unique = [...byId.values()].slice(0, MAX_UPSERTS_PER_RUN);

    let inserted = 0;
    let updated = 0;
    let errors = 0;

    for (const job of unique) {
      const row = {
        ...job,
        is_active: true,
        imported_at: new Date().toISOString(),
        expires_at: job.expires_at ??
          new Date(Date.now() + 45 * 24 * 60 * 60 * 1000).toISOString(),
      };

      const { data: existing } = await supabase
        .from("external_jobs")
        .select("id")
        .eq("external_id", job.external_id)
        .maybeSingle();

      if (existing) {
        const { error } = await supabase.from("external_jobs").update(row).eq("external_id", job.external_id);
        if (error) errors++;
        else updated++;
      } else {
        const { error } = await supabase.from("external_jobs").insert(row);
        if (error) errors++;
        else inserted++;
      }
    }

    const { data: staleCount } = await supabase.rpc("deactivate_stale_external_jobs");

    runLog.inserted = inserted;
    runLog.updated = updated;
    runLog.errors = errors;
    runLog.unique = unique.length;
    runLog.deactivated_stale = staleCount ?? 0;

    await saveImportState(supabase, state, runLog);

    return new Response(
      JSON.stringify({
        ok: true,
        rate_limit_strategy: {
          serpapi_max_per_run: 1,
          serpapi_cooldown_hours: SERPAPI_COOLDOWN_HOURS,
          rss_per_run: RSS_BATCH_SIZE,
          request_delay_ms: REQUEST_DELAY_MS,
          total_rss_sources: RSS_SOURCES.length,
          full_rss_cycle_runs: Math.ceil(RSS_SOURCES.length / RSS_BATCH_SIZE),
        },
        ...runLog,
      }),
      { status: 200, headers: JSON_HEADERS },
    );
  } catch (e) {
    console.error("import-external-jobs failed:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: JSON_HEADERS,
    });
  }
});
