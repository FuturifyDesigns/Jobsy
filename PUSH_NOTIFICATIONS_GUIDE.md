# Jobsy Push Notifications — Setup Guide (v30)

## Overview

Push notifications in Jobsy work like this:

```
Event happens (new message, application, etc.)
    → DB trigger inserts row into `notifications` table
    → Supabase Database Webhook fires
    → Edge Function `push-notification` runs
    → Looks up user's FCM token from `profiles`
    → Sends push via Firebase Cloud Messaging HTTP v1 API
    → Phone receives and displays the notification
```

For re-engagement ("come back") messages:

```
Scheduled Edge Function runs daily at noon (Botswana time)
    → Queries users with FCM tokens who haven't been active
    → Inserts a `re_engagement` notification row
    → That triggers the same webhook → push flow above
```

---

## Step-by-Step Setup

### STEP 1: Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click **"Add project"** → name it **Jobsy**
3. Disable Google Analytics (not needed) → click **Create project**
4. Once created, click the **Android icon** (Add app)
5. **Android package name:** `com.futurify.jobsy`
6. **App nickname:** Jobsy
7. **SHA-1:** skip for now
8. Click **Register app**
9. **Download `google-services.json`**
10. Place it at: `android/app/google-services.json`

### STEP 2: Get Firebase Service Account Key

1. In Firebase Console → **Project Settings** (gear icon) → **Service accounts**
2. Click **"Generate new private key"**
3. Download the JSON file (keep it safe, it's a secret!)
4. You'll need the FULL contents of this file for Step 5

### STEP 3: Run the SQL Migration

In **Supabase Dashboard → SQL Editor**, run:

```sql
-- Paste the contents of PUSH_NOTIFICATIONS_MIGRATION.sql
```

This adds `fcm_token` and `device_platform` columns to the `profiles` table.

### STEP 4: Deploy Edge Functions

You need the **Supabase CLI** installed. If you don't have it:

```bash
npm install -g supabase
```

Then link your project and deploy:

```bash
# In the project root directory (where the supabase/ folder is)
supabase login
supabase link --project-ref jvulfleleybcoljcmpwq

# Deploy the push notification function
supabase functions deploy push-notification --no-verify-jwt

# Deploy the re-engagement function
supabase functions deploy re-engagement --no-verify-jwt
```

### STEP 5: Set Edge Function Secrets

```bash
# Your Firebase project ID (find it in Firebase Console → Project Settings)
supabase secrets set FCM_PROJECT_ID=your-firebase-project-id

# The ENTIRE content of the service account JSON file from Step 2
# (paste it as a single line, or use quotes)
supabase secrets set FCM_SERVICE_ACCOUNT_KEY='{"type":"service_account","project_id":"...","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","client_id":"...","auth_uri":"...","token_uri":"...","auth_provider_x509_cert_url":"...","client_x509_cert_url":"..."}'
```

**Tip:** On Windows, it might be easier to set the secret via the
Supabase Dashboard → Edge Functions → Secrets instead of the CLI.

### STEP 6: Create Database Webhook

1. Go to **Supabase Dashboard → Database → Webhooks**
2. Click **"Create a new webhook"**
3. Configure:
   - **Name:** `push-on-notification-insert`
   - **Table:** `notifications`
   - **Events:** `INSERT` only
   - **Type:** Supabase Edge Function
   - **Edge Function:** `push-notification`
   - **HTTP Headers:** add `Authorization: Bearer YOUR_ANON_KEY`
     (replace with your actual anon key)
4. Click **Create webhook**

### STEP 7: Schedule Re-engagement Function

1. Go to **Supabase Dashboard → Edge Functions**
2. Find `re-engagement` → click **Schedules**
3. Create schedule:
   - **Name:** `re-engagement-daily`
   - **Cron expression:** `0 10 * * *` (10:00 UTC = 12:00 noon Botswana)
4. Save

### STEP 8: Build and Test

```bash
flutter clean
flutter pub get
flutter build apk --release
```

---

## What Notifications Get Sent

| Event | Trigger | Title | Body |
|---|---|---|---|
| New message | DB trigger on `messages` INSERT | Sender's name | Message preview (80 chars) |
| New application | DB trigger on `job_applications` INSERT | "New Application" | "X applied to 'Job Title'" |
| Application accepted | DB trigger on `job_applications` UPDATE | "You got the job!" | "Your application for 'X' was accepted" |
| Application rejected | DB trigger on `job_applications` UPDATE | "Application Update" | "Your application for 'X' was not accepted..." |
| Re-engagement (3d) | Scheduled Edge Function | Varies | Gentle nudge to check new jobs |
| Re-engagement (7d) | Scheduled Edge Function | Varies | Urgency about filling jobs |
| Re-engagement (14d) | Scheduled Edge Function | Varies | "We miss you!" message |

---

## Architecture Notes

- **No FCM token = no push.** The Edge Function gracefully skips users without tokens.
- **Stale tokens auto-clear.** If FCM returns UNREGISTERED (user uninstalled), the token is nulled in profiles.
- **Sign-out clears token.** Call `PushNotificationService.instance.clearToken()` on logout.
- **Re-engagement throttle:** max 1 push per 3 days per user, stops after 60 days of inactivity.
- **Foreground messages** show as local notifications via `flutter_local_notifications`.
- **Tap handling** passes data payload to `onNotificationTap` callback for navigation.

---

## Cost Impact

- **Firebase Cloud Messaging:** FREE (unlimited pushes)
- **Supabase Edge Functions:** 500K invocations/month on free tier — more than enough
- **APK size increase:** ~2-3 MB (Firebase SDK)
- **No new Supabase storage cost** (just 2 new TEXT columns on profiles)

---

## Files Changed/Added in v30

### New files:
- `lib/services/push_notification_service.dart` — Flutter FCM handler
- `supabase/functions/push-notification/index.ts` — Edge Function for sending pushes
- `supabase/functions/re-engagement/index.ts` — Edge Function for dormant user nudges
- `PUSH_NOTIFICATIONS_MIGRATION.sql` — DB migration
- `PUSH_NOTIFICATIONS_GUIDE.md` — this file

### Modified files:
- `pubspec.yaml` — added firebase_core, firebase_messaging, flutter_local_notifications
- `android/build.gradle` — added google-services classpath
- `android/app/build.gradle` — added google-services plugin + Firebase BOM
- `android/app/src/main/AndroidManifest.xml` — FCM metadata
- `android/app/src/main/res/values/colors.xml` — notification accent color
- `lib/main.dart` — Firebase init + push service init
