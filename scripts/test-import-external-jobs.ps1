# Manual test for import-external-jobs (PowerShell)
# Usage: paste your service_role key from Supabase Dashboard → Settings → API

$ServiceRoleKey = "PASTE_SERVICE_ROLE_KEY_HERE"

curl.exe -X POST "https://jvulfleleybcoljcmpwq.supabase.co/functions/v1/import-external-jobs" `
  -H "Authorization: Bearer $ServiceRoleKey" `
  -H "Content-Type: application/json" `
  -d "{}"

Write-Host ""
Write-Host "Expected: JSON with ok:true and inserted:N"
Write-Host "401 Unauthorized = wrong key, or redeploy import-external-jobs from latest index.ts"
