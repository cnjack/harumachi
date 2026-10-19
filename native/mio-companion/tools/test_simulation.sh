#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
port="${MIO_SIM_PORT:-4910}"
evidence="${MIO_TEST_EVIDENCE:-$(mktemp -d /tmp/mio-api-test.XXXXXX)}"
mkdir -p "$evidence"
sim="$PWD/postman/simulations/mio.sim.yaml"
postman simulation run "$sim" --port "$port" --output ndjson > "$evidence/sim.ndjson" 2> "$evidence/sim.err" &
launcher=$!
cleanup() {
  pkill -INT -f "simulation run $sim --port $port" || true
  wait "$launcher" 2>/dev/null || true
}
trap cleanup EXIT
for attempt in {1..40}; do
  if rg -q '"event":"listening"|"type":"listening"|"listening"' "$evidence/sim.ndjson"; then break; fi
  if ! kill -0 "$launcher" 2>/dev/null; then cat "$evidence/sim.err"; exit 1; fi
  sleep 0.2
done
MIO_TEST_SIM_URL="http://127.0.0.1:$port/clef" swift test 2>&1 | tee "$evidence/swift-test.txt"
if [ -n "${MIO_TEST_APP:-}" ]; then
  MIO_CLEF_BASE_URL="http://127.0.0.1:$port/clef" "$MIO_TEST_APP" --smoke-test "$evidence/app"
  python3 - "$evidence/app/smoke.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
assert result['connection']=='已连接 · clef-omni', result
assert result['decisionSource']=='Clef 决策', result
print('Native app consumed Postman responses and updated its live character')
PY
fi
python3 - "$evidence/sim.ndjson" <<'PY'
import json,sys
events=[json.loads(line) for line in open(sys.argv[1]) if line.strip().startswith('{')]
requests=[e for e in events if e.get('type',e.get('event'))=='request']
assert len(requests)>=7, f'Production HTTP transport not proven: {len(requests)} requests'
print(f'Postman captured {len(requests)} real Swift dependency requests')
PY
