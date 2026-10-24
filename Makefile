SHELL := /usr/bin/env bash

.PHONY: run capture test help

TYPESAFE_RUNS ?= 3

run: capture test

capture:
	@SHARE_ID="$(SHARE_ID)" TYPESAFE_RUNS="$(TYPESAFE_RUNS)" bash scripts/capture.sh

test:
	@if command -v mise >/dev/null 2>&1 && mise exec -- pkl --version >/dev/null 2>&1; then \
		mise exec -- pkl test pkl/TypesafeExperiment.test.pkl; \
	else \
		pkl test pkl/TypesafeExperiment.test.pkl; \
	fi

help:
	@printf '%s\n' \
		'make run                         capture and verify using the default Proton Pass vault lookup' \
		'SHARE_ID=... make run            capture and verify using an explicit Proton Pass share ID' \
		'make run SHARE_ID=...            same as above' \
		'TYPESAFE_RUNS=5 make run         override capture repetitions' \
		'make capture                     only call TypeSafe and write build/typesafe-observed.json' \
		'make test                        only verify the last captured observation'
