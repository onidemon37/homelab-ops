# Mirrors Taskfile.yaml, so use whichever you prefer: `make validate` == `task validate`.
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash

# Cluster to render (atlantis | galactica | pegasus | all) and optional kube context.
CLUSTER ?= all
CONTEXT ?=
KUBECTL_CTX := $(if $(CONTEXT),--context $(CONTEXT),)

.PHONY: help validate lint lint-yaml lint-shell lint-terraform flux-status flux-reconcile

help:
	@echo "Usage:"
	@echo "  make validate [CLUSTER=pegasus]     # render clusters with kustomize"
	@echo "  make lint                           # yaml, shell and terraform linters"
	@echo "  make lint-yaml | lint-shell | lint-terraform"
	@echo "  make flux-status [CONTEXT=ctx]      # show Kustomizations and HelmReleases"
	@echo "  make flux-reconcile [CONTEXT=ctx]   # reconcile git source and root Kustomization"

validate:
	scripts/render-all.sh $(CLUSTER)

lint: lint-yaml lint-shell lint-terraform

lint-yaml:
	find . -type f \( -name '*.yaml' -o -name '*.yml' \) -not -path './.git/*' -not -path '*/.terraform/*' -print0 \
		| xargs -0 yamllint -d relaxed --no-warnings

lint-shell:
	@if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh; \
	else echo "shellcheck not installed; falling back to bash -n"; for f in scripts/*.sh; do bash -n "$$f"; done; fi

lint-terraform:
	@tf=$$(command -v tofu || command -v terraform || true); \
	if [ -z "$$tf" ]; then echo "tofu/terraform not installed; skipping"; else $$tf fmt -check -recursive terraform; fi

flux-status:
	kubectl $(KUBECTL_CTX) get kustomizations,helmreleases -A

flux-reconcile:
	flux $(KUBECTL_CTX) reconcile source git flux-system
	flux $(KUBECTL_CTX) reconcile kustomization flux-system --with-source
