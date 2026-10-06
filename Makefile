ifneq ($(wildcard $(CURDIR)/.tofu-mirror/tofurc),)
export TF_CLI_CONFIG_FILE := $(CURDIR)/.tofu-mirror/tofurc
endif

.PHONY: fmt fmt-check bootstrap-validate bootstrap-test modules-test stack-validate stack-test test validate ci-test e2e ministack-up ministack-forward ministack-down

fmt:
	tofu fmt -recursive

fmt-check:
	tofu fmt -check -recursive

bootstrap-validate:
	tofu -chdir=bootstrap init -backend=false -input=false
	tofu -chdir=bootstrap validate

bootstrap-test:
	tofu -chdir=bootstrap init -backend=false -input=false
	tofu -chdir=bootstrap test

modules-test:
	tofu -chdir=modules/bucket init -backend=false -input=false
	tofu -chdir=modules/bucket test
	tofu -chdir=modules/team init -backend=false -input=false
	tofu -chdir=modules/team test

stack-validate:
	tofu -chdir=stacks/team init -backend=false -input=false
	tofu -chdir=stacks/team validate

stack-test:
	tofu -chdir=stacks/team init -backend=false -input=false
	tofu -chdir=stacks/team test

test: bootstrap-test modules-test stack-test

validate: bootstrap-validate stack-validate

# Tests for the pull request checks.
ci-test:
	tests/ci/run.sh

# End-to-end test. First: make ministack-up, and make ministack-forward in another terminal.
e2e:
	tests/e2e/run.sh

KIND_CONTEXT ?= kind-adam

ministack-up:
	kubectl --context $(KIND_CONTEXT) apply -k deploy/ministack
	kubectl --context $(KIND_CONTEXT) -n aws-emulator rollout status deploy/ministack --timeout=180s

ministack-forward: # keeps running; use its own terminal
	kubectl --context $(KIND_CONTEXT) -n aws-emulator port-forward svc/ministack 4566:4566

ministack-down:
	kubectl --context $(KIND_CONTEXT) delete -k deploy/ministack
