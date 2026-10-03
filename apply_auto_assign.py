import json, urllib.request, urllib.error
PAT = "sbp_fcd9960b5c5c6e16b4e5653dee494efdee237441"
MGMT = "https://api.supabase.com/v1/projects/ahaospjkkuetkaixwzzz/database/query"
def q(sql, t=300):
    r = urllib.request.Request(MGMT, data=json.dumps({"query": sql}).encode(),
        headers={"Authorization":"Bearer "+PAT,"Content-Type":"application/json"}, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=t) as resp:
            return True, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return False, e.read().decode()[:900]

mig = open(r"supabase/migrations/20260922_auto_assign_engine.sql", encoding="utf-8").read()
print("=== APPLY ===")
ok, res = q(mig)
print("  applied:", ok, ("| " + str(res)[:400]) if not ok else "")
