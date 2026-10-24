# typesafe-experiment

Tracks a small experiment against the [TypeSafe AI](https://typesafe.ai) API so
that changes in its behaviour are detected: four messages are scored by the
`is_urgent` noul question on `jev-latest`, and the scores are compared with a
pinned baseline.

| File | Role |
| --- | --- |
| `pkl/TypesafeExperiment.pkl` | Spec: endpoint, messages, sanity bands, pinned baseline, tolerances |
| `scripts/capture.sh` | The only thing that touches the TypeSafe network API; writes `build/typesafe-observed.json` |
| `scripts/bootstrap.sh` | Bootstraps the Proton Pass journals and scoped agent credentials |
| `pkl/TypesafeExperiment.test.pkl` | Divergence contract (no I/O): facts that must hold, plus examples snapshotted in `-expected.pcf` |

## Bootstrap an agent

Each agent (`hypervisor`, `manager`, `worker`) gets its own Proton Pass vault,
`typesafe-experiment-<agent>`, holding a `journal` item with real custom fields
(`working_on`, `current_hypothesis`, `evidence`, `uncertain_about`,
`next_action`, `possible_conflicts`, in that priority order). The fields are fixed when the item is
created: `item update` can edit a field but not add one. A vault, not an item,
is the unit of access, so an agent can also create new items in its own vault.

Bootstrapping is owner-only. It creates vaults, tokens and grants, which PAT
sessions cannot do, and the script refuses to run from one. Log in as yourself
first (`pass-cli login`), then:

```sh
make bootstrap                    # the default agent (worker)
make bootstrap AGENT=manager
make hypervisor manager worker    # any subset, in any order
```

Per agent it creates or reuses the vault, the journal, and a credential
`typesafe-experiment-<agent>`, then grants:

- the agent `editor` on its own vault
- the agent `viewer` on each other agent's vault that exists, and each other
  agent's credential `viewer` on this vault (so order does not matter)
- the agent `viewer` on `infra/typesafe.ai` so `make capture` works as that
  agent (`GRANT_TYPESAFE=0` to skip)

A new credential's token is printed once by `pass-cli`. Save it then; nothing
is written to the repo. Re-running reuses what exists and does not mint a new
token. `AGENT_EXPIRATION` takes `1d`, `1w`, `1m`, `3m`, `6m` or `1y`; note `3m`
is three months.

Bare `make` only prints help.

## Run the TypeSafe experiment

Needs `pkl`, `jq`, `curl`, and `pass-cli` logged in with access to
`pass://infra/typesafe.ai/TYPESAFE_API_KEY`.

```sh
make capture   # paid TypeSafe calls; writes build/typesafe-observed.json
make check     # verifies the most recent capture; no network I/O
```

Override capture repetitions with `TYPESAFE_RUNS=5 make capture`.

The key is read inside the capture script and passed to curl on stdin; it is
never written to `build/` or printed.

## What counts as divergence

- Resolved model differs from `baselineModel` (fails on purpose; re-pin after reviewing the diff).
- A mean score leaves its sanity band, the urgency ranking changes, or a mean drifts more than `tolerance` (0.05).
- Spread across one capture's runs exceeds `spreadTolerance` (0.10).

Baseline recorded 2026-10-25 on `jev-1.14.0`. The quickstart docs show 0.99 on
`jev-1.13.0` for the `api-500s` sentence versus ~0.78 observed; that gap is kept
in the spec as `docsExample`.

To re-pin after a deliberate model change: update `baselineModel` / `baselineMean`
in the spec, then `pkl test --overwrite pkl/TypesafeExperiment.test.pkl`.
