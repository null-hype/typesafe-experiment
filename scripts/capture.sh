#!/usr/bin/env bash
# Runs the typesafe.ai urgency experiment declared in pkl/TypesafeExperiment.pkl
# and writes what it observed to build/typesafe-observed.json, for
# pkl/TypesafeExperiment.test.pkl to compare against the pinned baseline.
#
# It makes paid network calls and needs a
# secret. Run it on purpose. TYPESAFE_RUNS (default 3) sets repetitions.
# Only the resolved model, scores and usage are recorded -- never the key.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(basename "$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || echo "$DIR/..")")"
BRANCH="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
export PROTON_PASS_AGENT_REASON="capture-typesafe-experiment: repo=$REPO branch=$BRANCH"

RUNS="${TYPESAFE_RUNS:-3}"
SPEC="$DIR/../pkl/TypesafeExperiment.pkl"
OUT_DIR="$DIR/../build"
OUT="$OUT_DIR/typesafe-observed.json"
mkdir -p "$OUT_DIR"

if command -v mise >/dev/null 2>&1 && mise exec -- pkl --version >/dev/null 2>&1; then PKL=(mise exec -- pkl); else PKL=(pkl); fi
spec="$("${PKL[@]}" eval -f json "$SPEC")"
endpoint="$(jq -r .endpoint <<<"$spec")"
model="$(jq -r .requestedModel <<<"$spec")"
qid="$(jq -r .questionId <<<"$spec")"
instructions="$(jq -r .instructions <<<"$spec")"

key="$(pass-cli item view "pass://infra/typesafe.ai/TYPESAFE_API_KEY")"

runs=()
for _ in $(seq "$RUNS"); do
  scores='{}'
  resolved=''
  usage='null'
  while IFS= read -r case; do
    id="$(jq -r .id <<<"$case")"
    body="$(jq -n --arg s "$(jq -r .state <<<"$case")" --arg m "$model" --arg q "$qid" --arg i "$instructions" \
      '{state: $s, model: $m, questions: {($q): {type: "noul", instructions: $i}}}')"
    # Key goes via stdin config so it never appears in the process list.
    resp="$(printf 'header = "Authorization: Bearer %s"\n' "$key" |
      curl --silent --show-error --fail-with-body --max-time 60 -K - \
        -H 'Content-Type: application/json' -d "$body" "$endpoint")"
    resolved="$(jq -r .model <<<"$resp")"
    usage="$(jq -c .usage <<<"$resp")"
    scores="$(jq -c --arg id "$id" --argjson v "$(jq ".answers.\"$qid\".noul" <<<"$resp")" '. + {($id): $v}' <<<"$scores")"
  done < <(jq -c '.cases[]' <<<"$spec")
  runs+=("$(jq -n --arg model "$resolved" --argjson scores "$scores" --argjson usage "$usage" \
    '{model: $model, scores: $scores, lastUsage: $usage}')")
done

printf '%s\n' "${runs[@]}" |
  jq -s --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg ep "$endpoint" --arg rm "$model" \
    '{capturedAt: $at, endpoint: $ep, requestedModel: $rm, runs: .}' > "$OUT"
echo "wrote $OUT ($RUNS runs)" >&2
