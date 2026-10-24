#!/usr/bin/env bash
set -euo pipefail

VAULT_NAME="${VAULT_NAME:-typesafe-experiment-agents}"
SHARE_ID="${SHARE_ID:-}"
AGENT_PREFIX="${AGENT_PREFIX:-typesafe-experiment}"
AGENT_EXPIRATION="${AGENT_EXPIRATION:-3m}"
ROLES=(hypervisor manager worker)

command -v pass-cli >/dev/null 2>&1 || {
  echo "pass-cli is required" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 1
}

pass-cli info >/dev/null
pass-cli test >/dev/null

export PROTON_PASS_AGENT_REASON="bootstrap typesafe-experiment agent journals and scoped grants"

if [[ -n "$SHARE_ID" ]]; then
  selector=(--share-id "$SHARE_ID")
  pass-cli item list "${selector[@]}" --output json >/dev/null
  echo "Using existing vault share: $SHARE_ID"
else
  vaults_json="$(pass-cli vault list --output json)"
  if jq -e --arg name "$VAULT_NAME" '.. | strings | select(. == $name)' <<<"$vaults_json" >/dev/null; then
    echo "Using existing vault: $VAULT_NAME"
  else
    echo "Creating vault: $VAULT_NAME"
    pass-cli vault create --name "$VAULT_NAME"
  fi
  selector=(--vault-name "$VAULT_NAME")
fi

journal_title() {
  printf '%s journal' "$1"
}

journal_seed() {
  local role="$1"
  cat <<EOF
role: $role
working_on:
current_hypothesis:
evidence:
uncertain_about:
next_action:
possible_conflicts:
EOF
}

for role in "${ROLES[@]}"; do
  title="$(journal_title "$role")"
  items_json="$(pass-cli item list "${selector[@]}" --output json)"
  if jq -e --arg title "$title" '.. | objects | select((.title? == $title) or (.content?.title? == $title))' <<<"$items_json" >/dev/null; then
    echo "Journal exists: $title"
  else
    echo "Creating journal: $title"
    pass-cli item create note "${selector[@]}" --title "$title" --note "$(journal_seed "$role")"
  fi
done

pats_json="$(pass-cli pat list --output json)"

pat_exists() {
  local pat_name="$1"
  jq -e --arg name "$pat_name" '.. | objects | select(.name? == $name)' <<<"$pats_json" >/dev/null
}

grant_item() {
  local pat_name="$1"
  local item_title="$2"
  local role="$3"
  local err
  err="$(mktemp)"
  if pass-cli pat access grant --pat-name "$pat_name" "${selector[@]}" --item-title "$item_title" --role "$role" 2>"$err"; then
    rm -f "$err"
    return 0
  fi
  if grep -Eqi 'already|exists|duplicate' "$err"; then
    rm -f "$err"
    return 0
  fi
  cat "$err" >&2
  rm -f "$err"
  return 1
}

for owner in "${ROLES[@]}"; do
  pat_name="$AGENT_PREFIX-$owner"
  if pat_exists "$pat_name"; then
    echo "Agent credential exists: $pat_name"
  else
    echo
    echo "Creating agent credential: $pat_name"
    echo "Save the token printed by pass-cli now; it cannot be shown again."
    pass-cli pat create --name "$pat_name" --expiration "$AGENT_EXPIRATION"
    echo
  fi

  for journal_owner in "${ROLES[@]}"; do
    item_title="$(journal_title "$journal_owner")"
    if [[ "$owner" == "$journal_owner" ]]; then
      grant_role=editor
    else
      grant_role=viewer
    fi
    grant_item "$pat_name" "$item_title" "$grant_role"
  done

done

echo
echo "Bootstrap complete."
echo "Each role can edit its own journal and read the other two."
if [[ -n "$SHARE_ID" ]]; then
  echo "Vault: $SHARE_ID"
else
  echo "Vault: $VAULT_NAME"
fi
