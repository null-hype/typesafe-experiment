#!/usr/bin/env bash
# Bootstraps ONE agent: its own Proton Pass vault, a journal item with real
# custom fields, a scoped credential (PAT), and the grants that go with them.
#
#   make bootstrap AGENT=worker      (or: make worker)
#
# Must be run by the vault owner. PAT sessions cannot create vaults, tokens or
# grants, so this refuses to run from one. Re-running converges: whatever
# already exists is reused, and grants to/from the other agents are applied
# for whichever of their vaults and credentials exist at that point, so the
# agents can be bootstrapped in any order.
set -euo pipefail

AGENT="${AGENT:-worker}"
AGENT_PREFIX="${AGENT_PREFIX:-typesafe-experiment}"
AGENT_EXPIRATION="${AGENT_EXPIRATION:-3m}"
GRANT_TYPESAFE="${GRANT_TYPESAFE:-1}"
TYPESAFE_VAULT="infra"
TYPESAFE_ITEM="typesafe.ai"
JOURNAL_TITLE="journal"
ROLES=(hypervisor manager worker)
# Fixed, in priority order. Fields cannot be added after creation.
JOURNAL_FIELDS=(working_on current_hypothesis evidence uncertain_about next_action possible_conflicts)

die() { echo "bootstrap: $*" >&2; exit 1; }

command -v pass-cli >/dev/null 2>&1 || die "pass-cli is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

valid=0
for r in "${ROLES[@]}"; do [[ "$r" == "$AGENT" ]] && valid=1; done
((valid)) || die "AGENT must be one of: ${ROLES[*]} (got '$AGENT')"

# `pat list` is refused in PAT/agent sessions, so it doubles as the owner check.
pats_json="$(pass-cli personal-access-token list --output json 2>/dev/null)" ||
  die "must be run logged in as the vault owner (not a personal access token). Run: pass-cli login"

export PROTON_PASS_AGENT_REASON="bootstrap typesafe-experiment agent '$AGENT'"

vault_of() { printf '%s-%s' "$AGENT_PREFIX" "$1"; }
pat_of() { printf '%s-%s' "$AGENT_PREFIX" "$1"; }

vault_exists() {
  pass-cli vault list --output json |
    jq -e --arg n "$1" '.. | objects | select(.name? == $n)' >/dev/null
}

pat_exists() {
  jq -e --arg n "$1" '.. | objects | select(.name? == $n)' <<<"$pats_json" >/dev/null
}

# Grants are idempotent: "already granted" is not an error.
grant() {
  local pat="$1" role="$2"
  shift 2
  local err
  err="$(mktemp)"
  if pass-cli personal-access-token access grant \
    --personal-access-token-name "$pat" "$@" --role "$role" 2>"$err"; then
    rm -f "$err"
    return 0
  fi
  if grep -Eqi 'already|duplicate' "$err"; then
    rm -f "$err"
    return 0
  fi
  cat "$err" >&2
  rm -f "$err"
  return 1
}

# The journal's fields must exist at creation: `item update` can edit a field
# but cannot add one, and the agent's PAT only edits. Hence a custom item built
# from a template, not a note with lines of text in it.
journal_template() {
  printf '%s\n' "${JOURNAL_FIELDS[@]}" |
    jq -R '{field_name: ., field_type: "text", value: ""}' |
    jq -s --arg title "$JOURNAL_TITLE" \
      '{title: $title, note: "", sections: [{section_name: "Journal", fields: .}]}'
}

vault="$(vault_of "$AGENT")"
pat="$(pat_of "$AGENT")"

# 1. vault
if vault_exists "$vault"; then
  echo "Vault exists: $vault"
else
  echo "Creating vault: $vault"
  pass-cli vault create --name "$vault"
fi

# 2. journal
if pass-cli item list "$vault" --output json |
  jq -e --arg t "$JOURNAL_TITLE" '.. | objects | select((.title? == $t) or (.content?.title? == $t))' >/dev/null; then
  echo "Journal exists: $vault/$JOURNAL_TITLE"
else
  echo "Creating journal: $vault/$JOURNAL_TITLE"
  journal_template | pass-cli item create custom --vault-name "$vault" --from-template -
fi

# 3. credential
if pat_exists "$pat"; then
  echo "Credential exists: $pat"
else
  echo
  echo "Creating credential: $pat"
  echo "Save the token printed by pass-cli now; it cannot be shown again."
  pass-cli personal-access-token create --name "$pat" --expiration "$AGENT_EXPIRATION"
  echo
  pats_json="$(pass-cli personal-access-token list --output json)"
fi

# 4. grants: editor on its own vault
grant "$pat" editor --vault-name "$vault"
echo "Granted: $pat editor on $vault"

# 5. grants with the other agents: viewer on each other's vault, both ways,
#    for whichever of their vaults/credentials exist right now.
for other in "${ROLES[@]}"; do
  [[ "$other" == "$AGENT" ]] && continue
  other_vault="$(vault_of "$other")"
  other_pat="$(pat_of "$other")"
  if vault_exists "$other_vault"; then
    grant "$pat" viewer --vault-name "$other_vault"
    echo "Granted: $pat viewer on $other_vault"
  fi
  if pat_exists "$other_pat"; then
    grant "$other_pat" viewer --vault-name "$vault"
    echo "Granted: $other_pat viewer on $vault"
  fi
done

# 6. the TypeSafe key, so `make capture` works as this agent (read-only, one item)
if [[ "$GRANT_TYPESAFE" == "1" ]]; then
  grant "$pat" viewer --vault-name "$TYPESAFE_VAULT" --item-title "$TYPESAFE_ITEM"
  echo "Granted: $pat viewer on $TYPESAFE_VAULT/$TYPESAFE_ITEM"
fi

echo
echo "Bootstrapped '$AGENT'. Others still to do: $(
  todo=()
  for r in "${ROLES[@]}"; do vault_exists "$(vault_of "$r")" || todo+=("$r"); done
  echo "${todo[*]:-none}"
)"
