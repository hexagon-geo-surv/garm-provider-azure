SHELL := bash

ROOTDIR=$(dir $(abspath $(lastword $(MAKEFILE_LIST))))
GOPATH ?= $(shell go env GOPATH)
GO ?= go

IMAGE_TAG = garm-provider-build

IMAGE_BUILDER=$(shell (which docker || which podman))
USER_ID=$(shell (($(IMAGE_BUILDER) --version | grep -q podman) && echo "0" || id -u))
USER_GROUP=$(shell (($(IMAGE_BUILDER) --version | grep -q podman) && echo "0" || id -g))
GARM_PROVIDER_NAME := garm-provider-azure

default: build

.PHONY : build build-static test install-lint-deps lint go-test fmt fmtcheck verify-vendor verify create-release-files release

build:
	@$(GO) build .

clean: ## Clean up build artifacts
	@rm -rf ./bin ./build ./release

build-static:
	@echo Building
	$(IMAGE_BUILDER) build --tag $(IMAGE_TAG) .
	mkdir -p build
	$(IMAGE_BUILDER) run --rm -e GARM_PROVIDER_NAME=$(GARM_PROVIDER_NAME) -e USER_ID=$(USER_ID) -e USER_GROUP=$(USER_GROUP) -v $(PWD)/build:/build/output:z -v $(PWD):/build/$(GARM_PROVIDER_NAME):z -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt $(IMAGE_TAG) /build-static.sh
	@echo Binaries are available in $(PWD)/build

test: install-lint-deps verify go-test

install-lint-deps:
	@$(GO) install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.63.4

lint:
	@golangci-lint run --timeout=8m --build-tags testing

go-test:
	@$(GO) test -race -mod=vendor -tags testing -v $(TEST_ARGS) -timeout=15m -parallel=4 -count=1 ./...

fmt:
	@$(GO) fmt $$(go list ./...)

fmtcheck:
	@gofmt -l -s $$(go list ./... | sed -n 's/github.com\/cloudbase\/'$(GARM_PROVIDER_NAME)'\/\(.*\)/\1/p') | grep ".*\.go"; if [ "$$?" -eq 0 ]; then echo "gofmt check failed; please tun gofmt -w -s"; exit 1;fi

verify-vendor: ## verify if all the go.mod/go.sum files are up-to-date
	$(eval TMPDIR := $(shell mktemp -d))
	@cp -R ${ROOTDIR} ${TMPDIR}
	@(cd ${TMPDIR}/$(GARM_PROVIDER_NAME) && ${GO} mod tidy)
	@diff -r -u -q ${ROOTDIR} ${TMPDIR}/$(GARM_PROVIDER_NAME) >/dev/null 2>&1; if [ "$$?" -ne 0 ];then echo "please run: go mod tidy && go mod vendor"; exit 1; fi
	@rm -rf ${TMPDIR}

verify: verify-vendor lint fmtcheck

##@ Release
create-release-files:
	./scripts/make-release.sh

release: build-static create-release-files ## Create a release
