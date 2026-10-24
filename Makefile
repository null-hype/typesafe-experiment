SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

AGENTS := hypervisor manager worker
.PHONY: help bootstrap $(AGENTS) capture check test

AGENT ?= worker
AGENT_PREFIX ?= typesafe-experiment
AGENT_EXPIRATION ?= 3m
GRANT_TYPESAFE ?= 1
TYPESAFE_RUNS ?= 3

help:
	@printf '%s\n' \
		'Usage:' \
		'  make bootstrap [AGENT=worker]     owner only: create the agent'"'"'s vault, journal, credential, grants' \
		'  make hypervisor manager worker    bootstrap those agents (any subset, any order)' \
		'  make capture                      capture the TypeSafe experiment (paid API calls)' \
		'  make check                        verify the most recent capture; no network I/O' \
		'' \
		'Bootstrap options:' \
		'  AGENT=worker                      one of: $(AGENTS)' \
		'  AGENT_PREFIX=typesafe-experiment  vaults and credentials are named <prefix>-<agent>' \
		'  AGENT_EXPIRATION=3m               1d, 1w, 1m, 3m, 6m or 1y (months, not minutes)' \
		'  GRANT_TYPESAFE=1                  also give the agent read access to infra/typesafe.ai; 0 to skip'

bootstrap:
	@AGENT="$(AGENT)" \
	 AGENT_PREFIX="$(AGENT_PREFIX)" \
	 AGENT_EXPIRATION="$(AGENT_EXPIRATION)" \
	 GRANT_TYPESAFE="$(GRANT_TYPESAFE)" \
	 bash scripts/bootstrap.sh

$(AGENTS):
	@$(MAKE) --no-print-directory bootstrap AGENT=$@

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
