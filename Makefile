NODE_IMAGE  ?= node:20-alpine

# Pinned by digest, not :latest
# This is floci-gcp 0.6.0.
FLOCI_IMAGE ?= floci/floci-gcp@sha256:fe61b4824d52de128846384c33a94600c1c63aeafe92c3319ee723f59a16d4c1
ENV         ?= staging

# npm runs in a container so its Node version is pinned and nothing has to be
# installed on the host. Same image the services are built from.
NPM = docker run --rm --user "$(shell id -u):$(shell id -g)" \
	-v "$(CURDIR)/starter:/app" -w /app $(NODE_IMAGE) npm

.PHONY: help install test build floci-up floci-down deploy integration-test \
        test-secrets verify clean

help:
	@echo "make install                 install dependencies"
	@echo "make test                    run unit tests"
	@echo "make build                   compile all workspaces"
	@echo "make floci-up                start the GCP emulator"
	@echo "make floci-down              stop it"
	@echo "make deploy ENV=staging      deploy one environment"
	@echo "make integration-test ENV=staging"
	@echo "make test-secrets            check services fail closed"
	@echo "make verify ENV=staging      floci-up + deploy + both test suites"

install: starter/node_modules

# A file target, so the install only runs when the directory is not there. On a
# fresh clone `make test` would otherwise fail with "cannot find package tsx".
starter/node_modules:
	$(NPM) ci

test: starter/node_modules
	$(NPM) test

build: starter/node_modules
	$(NPM) run build

# The Docker socket is mounted because floci starts Cloud Run containers through
# the host daemon. Safe to run twice.
# Checks whether it is *running*, not whether it exists: after a reboot the
# container is still there but stopped, and starting it again would be skipped.
floci-up:
	@docker inspect -f '{{.State.Running}}' floci-gcp 2>/dev/null | grep -q true || { \
		docker rm -f floci-gcp >/dev/null 2>&1 || true; \
		docker run -d --name floci-gcp -p 4588:4588 \
			-v /var/run/docker.sock:/var/run/docker.sock $(FLOCI_IMAGE); \
	}
	@for _ in $$(seq 1 30); do \
		curl -sf http://localhost:4588/v1/projects/readiness-probe/secrets >/dev/null && \
			echo "floci is ready" && exit 0; \
		sleep 2; \
	done; \
	echo "floci did not become ready" >&2; docker logs floci-gcp; exit 1

floci-down:
	-docker rm -f floci-gcp

deploy:
	./scripts/deploy.sh $(ENV)

integration-test:
	./scripts/integration-test.sh $(ENV)

test-secrets:
	./scripts/test-missing-secret.sh

verify: floci-up deploy integration-test test-secrets

clean: floci-down
	-rm -f .deploy-*.env
