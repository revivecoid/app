#!/usr/bin/env bash
# scripts/ci/check_migrations.sh
# Validates supabase/migrations/ before CI runs db reset.
# Fails (exit 1) on:
#   - Files not matching the naming pattern YYYYMMDDHHMMSS_name.sql (14-digit prefix)
#   - Duplicate version timestamps
#   - BOM-prefixed files
#   - Files with DO $ $ (broken dollar-quote from PowerShell escaping)
#
# Usage: bash scripts/ci/check_migrations.sh
# Returns 0 (all good) or 1 (with details on stderr).

set -euo pipefail

MIGRATIONS_DIR="supabase/migrations"
ERRORS=0

echo "=== Checking migrations in $MIGRATIONS_DIR ==="

# 1. Naming pattern
echo "-- Naming pattern (14-digit timestamp prefix) --"
for f in "$MIGRATIONS_DIR"/*.sql; do
  base=$(basename "$f")
  if ! echo "$base" | grep -qE '^\d{14}_[a-z0-9_]+\.sql$'; then
    echo "FAIL: bad name: $base" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

# 2. Duplicate timestamps
echo "-- Duplicate timestamps --"
dupes=$(for f in "$MIGRATIONS_DIR"/*.sql; do
  basename "$f" | grep -oE '^\d{14}'
done | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL: duplicate timestamps: $dupes" >&2
  ERRORS=$((ERRORS + 1))
fi

# 3. BOM check
echo "-- BOM check --"
for f in "$MIGRATIONS_DIR"/*.sql; do
  if LC_ALL=C head -c 3 "$f" | grep -qP '^\xef\xbb\xbf'; then
    echo "FAIL: BOM in $(basename "$f")" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

# 4. Broken dollar-quote (DO $ $ from PowerShell)
echo "-- Broken dollar-quote check --"
for f in "$MIGRATIONS_DIR"/*.sql; do
  if grep -qP 'DO \$ \$|END\$ \$' "$f"; then
    echo "FAIL: broken dollar-quote in $(basename "$f")" >&2
    ERRORS=$((ERRORS + 1))
  fi
done

# 5. Forbidden patterns: user_metadata / raw_user_meta_data in new policies/functions
echo "-- Forbidden auth source check --"
for f in "$MIGRATIONS_DIR"/*.sql; do
  base=$(basename "$f")
  # Only check new migrations (after remediation baseline)
  if [[ "$base" > "20260927" ]]; then
    if grep -qiE "(user_metadata|raw_user_meta_data)" "$f"; then
      echo "FAIL: user_metadata reference in new migration: $base" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

echo "==================================="
if [ "$ERRORS" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "FAILED: $ERRORS error(s) found." >&2
  exit 1
fi
