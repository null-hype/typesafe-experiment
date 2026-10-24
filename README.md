# typesafe-experiment

Tracks a small experiment against the [TypeSafe AI](https://typesafe.ai) API so
that changes in its behaviour are detected: four messages are scored by the
`is_urgent` noul question on `jev-latest`, and the scores are compared with a
pinned baseline.

| File | Role |
| --- | --- |
| `pkl/TypesafeExperiment.pkl` | Spec: endpoint, messages, sanity bands, pinned baseline, tolerances |
| `scripts/capture.sh` | The only thing that touches the network; writes `build/typesafe-observed.json` |
| `pkl/TypesafeExperiment.test.pkl` | Divergence contract (no I/O): facts that must hold, plus examples snapshotted in `-expected.pcf` |

## Run

Needs `pkl`, `jq`, `curl`, and `pass-cli` logged in with access to
`pass://infra/typesafe.ai/TYPESAFE_API_KEY` (paid API calls; `TYPESAFE_RUNS`,
default 3, sets repetitions).

```sh
bash scripts/capture.sh
pkl test pkl/TypesafeExperiment.test.pkl
```

The key is read inside the script and passed to curl on stdin; it is never
written to `build/` or printed.

## What counts as divergence

- Resolved model differs from `baselineModel` (fails on purpose; re-pin after reviewing the diff).
- A mean score leaves its sanity band, the urgency ranking changes, or a mean drifts more than `tolerance` (0.05).
- Spread across one capture's runs exceeds `spreadTolerance` (0.10).

Baseline recorded 2026-10-25 on `jev-1.14.0`. The quickstart docs show 0.99 on
`jev-1.13.0` for the `api-500s` sentence versus ~0.78 observed; that gap is kept
in the spec as `docsExample`.

To re-pin after a deliberate model change: update `baselineModel` / `baselineMean`
in the spec, then `pkl test --overwrite pkl/TypesafeExperiment.test.pkl`.
