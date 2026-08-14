#!/usr/bin/env bash
# Integration tests for the Job Board stack.
# Runs against the nginx reverse proxy, i.e. exactly what a browser hits.
# Usage:  BASE_URL=http://localhost:8080 bash scripts/integration-test.sh
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PASSED=0
FAILED=0

pass() { echo "  PASS  $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL  $1"; FAILED=$((FAILED + 1)); }

# assert_status <description> <expected-codes-regex> <curl args...>
assert_status() {
  local desc="$1"; local expected="$2"; shift 2
  local code
  code=$(curl -s -o /tmp/body.json -w '%{http_code}' "$@")
  if [[ "$code" =~ $expected ]]; then
    pass "$desc (HTTP $code)"
  else
    fail "$desc — expected $expected, got $code"
    head -c 400 /tmp/body.json; echo
  fi
}

echo "==> Waiting for the stack at $BASE_URL"
for i in $(seq 1 60); do
  if curl -fsS "$BASE_URL/api/jobs" >/dev/null 2>&1; then
    echo "    stack is up after $((i * 5))s"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "    stack did not come up in 300s"; exit 1
  fi
  sleep 5
done

echo
echo "==> 1. Reverse proxy serves the frontend"
assert_status "GET /" '^200$' "$BASE_URL/"

echo
echo "==> 2. Jobs service"
assert_status "GET /api/jobs" '^200$' "$BASE_URL/api/jobs"
# A trailing slash must be served in place (200), not answered with a 307
# that drops the /api prefix and bounces the caller to the frontend.
assert_status "GET /api/jobs/ (trailing slash)" '^200$' "$BASE_URL/api/jobs/"
if jq -e 'type == "array"' /tmp/body.json >/dev/null 2>&1; then
  COUNT=$(jq 'length' /tmp/body.json)
  pass "GET /api/jobs returned a JSON array ($COUNT jobs)"
  [ "$COUNT" -ge 1 ] && pass "seed data present" || fail "no seeded jobs found"
else
  fail "GET /api/jobs did not return a JSON array"
fi

echo
echo "==> 3. Create a job"
JOB=$(curl -s -X POST "$BASE_URL/api/jobs" \
  -H 'Content-Type: application/json' \
  -d '{"title":"CI Smoke Test Engineer","description":"Created by GitHub Actions","company":"Pipeline Inc","location":"Remote","salary_range":"$1-$2"}')
JOB_ID=$(echo "$JOB" | jq -r '.id // empty')
if [ -n "$JOB_ID" ]; then
  pass "POST /api/jobs created job id=$JOB_ID"
else
  fail "POST /api/jobs did not return an id"; echo "$JOB" | head -c 400; echo
fi

echo
echo "==> 4. Read it back"
if [ -n "$JOB_ID" ]; then
  assert_status "GET /api/jobs/$JOB_ID" '^200$' "$BASE_URL/api/jobs/$JOB_ID"
  TITLE=$(jq -r '.title // empty' /tmp/body.json)
  [ "$TITLE" = "CI Smoke Test Engineer" ] \
    && pass "title round-tripped correctly" \
    || fail "title mismatch: '$TITLE'"
fi

echo
echo "==> 5. Validation and 404 behaviour"
assert_status "POST /api/jobs with missing fields -> 422" '^422$' \
  -X POST "$BASE_URL/api/jobs" -H 'Content-Type: application/json' -d '{"title":"only a title"}'
assert_status "GET /api/jobs/999999 -> 404" '^404$' "$BASE_URL/api/jobs/999999"

echo
echo "==> 6. Applications service"
assert_status "GET /api/applications/" '^200$' "$BASE_URL/api/applications/"

if [ -n "$JOB_ID" ]; then
  APP=$(curl -s -X POST "$BASE_URL/api/applications/" \
    -H 'Content-Type: application/json' \
    -d "{\"job_id\":\"$JOB_ID\",\"applicant_name\":\"CI Bot\",\"applicant_email\":\"ci@example.com\",\"cover_letter\":\"Automated integration test.\"}")
  APP_ID=$(echo "$APP" | jq -r '.id // empty')
  if [ -n "$APP_ID" ]; then
    pass "POST /api/applications/ created application id=$APP_ID"
  else
    fail "POST /api/applications/ did not return an id"; echo "$APP" | head -c 400; echo
  fi

  assert_status "GET /api/applications/job/$JOB_ID" '^200$' "$BASE_URL/api/applications/job/$JOB_ID"
  jq -e --arg n "CI Bot" 'map(select(.applicant_name == $n)) | length > 0' /tmp/body.json >/dev/null 2>&1 \
    && pass "application is linked to the job" \
    || fail "application not found for job $JOB_ID"

  if [ -n "${APP_ID:-}" ]; then
    assert_status "PATCH /api/applications/$APP_ID/status" '^200$' \
      -X PATCH "$BASE_URL/api/applications/$APP_ID/status" \
      -H 'Content-Type: application/json' -d '{"status":"reviewed"}'
  fi
fi

echo
echo "==> 7. Cleanup"
if [ -n "$JOB_ID" ]; then
  assert_status "DELETE /api/jobs/$JOB_ID" '^(200|204)$' -X DELETE "$BASE_URL/api/jobs/$JOB_ID"
fi

echo
echo "================================================"
echo " Passed: $PASSED    Failed: $FAILED"
echo "================================================"
[ "$FAILED" -eq 0 ] || exit 1
