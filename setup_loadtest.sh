#!/usr/bin/env bash
# Safe web performance testing toolkit for Ubuntu (k6, wrk, ab)
# Usage:
#   sudo bash setup_loadtest.sh https://your-domain.com
#   TARGET defaults to https://example.com if not provided.

set -euo pipefail

TARGET="${1:-https://example.com}"
WORKDIR="/opt/loadtest"
K6_FILE="${WORKDIR}/test.js"

echo "==> Target: ${TARGET}"
echo "==> Preparing system..."
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl gnupg software-properties-common jq unzip

echo "==> Install k6 (official repo)"
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt-get update -y
apt-get install -y k6

echo "==> Install wrk and ab (ApacheBench)"
apt-get install -y wrk apache2-utils

echo "==> Create workspace ${WORKDIR}"
mkdir -p "${WORKDIR}"

echo "==> Write k6 test script"
cat > "${K6_FILE}" <<'EOF'
import http from "k6/http";
import { check, sleep } from "k6";
import { Counter } from "k6/metrics";

const TARGET = __ENV.TARGET || "https://example.com";
const TIME_BETWEEN = Number(__ENV.SLEEP || 0.3); // seconds between requests per VU

export const options = {
  // Edit stages to fit your traffic profile. These ramp gradually (safe).
  stages: [
    { duration: "30s", target: 10 },   // warm-up
    { duration: "1m",  target: 50 },   // ramp
    { duration: "2m",  target: 100 },  // steady
    { duration: "30s", target: 0 },    // cool-down
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],     // <1% errors
    http_req_duration: ["p(95)<500"],   // 95% under 500ms
  },
};

const errors = new Counter("errors");

export default function () {
  const res = http.get(TARGET, { tags: { name: "GET /" } });
  const ok = check(res, {
    "status is 2xx/3xx": (r) => r.status >= 200 && r.status < 400,
  });
  if (!ok) errors.add(1);
  sleep(TIME_BETWEEN);
}
EOF

echo "==> Quick smoke test (10s @ 5 VUs)"
cd "${WORKDIR}"
TARGET="${TARGET}" k6 run --vus 5 --duration 10s "${K6_FILE}" || true

cat > ${WORKDIR}/README.txt <<EOF
Safe Load Testing Toolkit
-------------------------
Files:
- test.js: k6 script (reads TARGET env var)
- Examples:

  # 1) Smoke test (fast correctness check)
  TARGET=${TARGET} k6 run --vus 1 --duration 15s test.js

  # 2) Baseline load (moderate, steady)
  TARGET=${TARGET} k6 run --vus 20 --duration 2m test.js

  # 3) Ramp profile (from env, custom pacing)
  TARGET=${TARGET} SLEEP=0.2 k6 run test.js

  # 4) Save JSON summary for later analysis
  TARGET=${TARGET} k6 run --vus 50 --duration 1m \
    --summary-export=summary.json test.js

  # 5) Use wrk for quick RPS probe (30s, 100 threads, 200 conns)
  wrk -t100 -c200 -d30s ${TARGET}

  # 6) ApacheBench (ab) quick check (1k requests, 100 concurrent)
  ab -n 1000 -c 100 ${TARGET}/

Notes:
- Only test domains you own or have written permission to test.
- Ramp up gradually; watch error rates and CPU/memory on your servers.
- Prefer staging or maintenance windows to avoid disrupting users.
EOF

echo "==> Done."
echo "Next steps:"
echo "  1) cd ${WORKDIR}"
echo "  2) TARGET=${TARGET} k6 run ${K6_FILE}"
echo "  3) Try wrk/ab examples in ${WORKDIR}/README.txt"
