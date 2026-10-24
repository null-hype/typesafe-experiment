SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help run capture check test

TYPESAFE_RUNS ?= 3

help:
	@printf '%s\n' \
		'Usage:' \
		'  make run                    capture from TypeSafe and verify the result' \
		'  make run SHARE_ID=...       same, selecting the Proton Pass vault by share ID' \
		'  make capture                capture only (makes paid API calls)' \
		'  make check                  verify the most recent capture; no network I/O' \
		'' \
		'Options:' \
		'  SHARE_ID=...                optional Proton Pass vault share ID' \
		'  TYPESAFE_RUNS=3             number of repeated captures (default: 3)'

run: capture check

capture:
	@SHARE_ID="$(SHARE_ID)" TYPESAFE_RUNS="$(TYPESAFE_RUNS)" bash scripts/capture.sh

check:
	@if command -v mise >/dev/null 2>&1 && mise exec -- pkl --version >/dev/null 2>&1; then \
		mise exec -- pkl test pkl/TypesafeExperiment.test.pkl; \
	else \
		pkl test pkl/TypesafeExperiment.test.pkl; \
	fi

# Familiar alias for people who reach for `make test`.
test: check
