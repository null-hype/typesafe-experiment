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

## Bootstrap agent journals

The intended collaboration topology is three agent-local journals: `hypervisor`,
`manager`, and `worker`. Each agent can edit its own journal and read the other
two, but cannot edit them.

With `pass-cli` logged in as the human/owner account:

```sh
make bootstrap
```

That creates or reuses the `typesafe-experiment-agents` vault, creates the three
journal notes if needed, creates one scoped credential per role, and applies the
item-level grants.

To use an existing vault instead:

```sh
make bootstrap SHARE_ID=...
```

New Proton Pass credentials are printed once by `pass-cli`. Save each credential
when it is created; the bootstrap does not write bearer tokens into the repo.
Re-running bootstrap reuses existing vaults, journals, and named credentials.

Useful overrides:

```sh
make bootstrap VAULT_NAME=my-agent-journals
make bootstrap AGENT_PREFIX=my-loop AGENT_EXPIRATION=1m
```

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
