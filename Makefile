SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap capture check test

VAULT_NAME ?= typesafe-experiment-agents
AGENT_PREFIX ?= typesafe-experiment
AGENT_EXPIRATION ?= 3m
TYPESAFE_RUNS ?= 3

help:
	@printf '%s\n' \
		'Usage:' \
		'  make bootstrap                    create/reuse the Pass vault, journals, credentials, and grants' \
		'  make bootstrap SHARE_ID=...       bootstrap into an existing Proton Pass vault share' \
		'  make capture                      capture the TypeSafe experiment (paid API calls)' \
		'  make check                        verify the most recent capture; no network I/O' \
		'' \
		'Bootstrap options:' \
		'  VAULT_NAME=typesafe-experiment-agents' \
		'  SHARE_ID=...                      use an existing vault instead of creating/resolving by name' \
		'  AGENT_PREFIX=typesafe-experiment  prefix for hypervisor/manager/worker credentials' \
		'  AGENT_EXPIRATION=3m               expiration for newly-created credentials'

bootstrap:
	@VAULT_NAME="$(VAULT_NAME)" \
	 SHARE_ID="$(SHARE_ID)" \
	 AGENT_PREFIX="$(AGENT_PREFIX)" \
	 AGENT_EXPIRATION="$(AGENT_EXPIRATION)" \
	 bash scripts/bootstrap.sh

capture:
	@TYPESAFE_RUNS="$(TYPESAFE_RUNS)" bash scripts/capture.sh

check:
	@if command -v mise >/dev/null 2>&1 && mise exec -- pkl --version >/dev/null 2>&1; then \
		mise exec -- pkl test pkl/TypesafeExperiment.test.pkl; \
	else \
		pkl test pkl/TypesafeExperiment.test.pkl; \
	fi

# Familiar alias for people who reach for `make test`.
test: check
