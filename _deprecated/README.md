# _deprecated/

Files moved here from the main codebase during the security remediation audit (10 Sep 2026).

These files are **not compiled** or deployed. They are kept for reference only.

## Files

| File | Reason | Audit ID |
|---|---|---|
| `vision_ai_orchestrator.dart` | Client-side AI orchestrator that contained API keys in source. Replaced by server-side `vision-estimation` Edge Function. | SEC-09 |
| `estimator_screen.dart.bak` | Backup file committed to repo. Contains stale code. | CODE-06 |

## Policy

- Do NOT import these files from `lib/`
- These files may be permanently deleted after 90 days (Dec 2026)
- If you need similar functionality, reference these as starting points but build server-side equivalents
