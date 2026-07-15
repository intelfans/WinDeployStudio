GOLANGCI_LINT_VERSION := v2.6.2
GOLANGCI_LINT_PATH := $(HOME)/.local/bin/golangci-lint-$(subst v,,$(GOLANGCI_LINT_VERSION))
COVERAGE_PROFILE := /tmp/go-ext4fs-coverage.out

# Linker flags for macOS compatibility with Go < 1.24 (LC_UUID issue)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    LDFLAGS := -ldflags="-linkmode=external"
endif

.PHONY: lint tests coverage bench fuzz all

all: fmt lint tests

tests:
	@echo "===> Running end-to-end tests"
	go test $(LDFLAGS) -v -count=1 ./...

coverage:
	@echo "===> Running tests with coverage"
	go test $(LDFLAGS) -v -coverprofile=$(COVERAGE_PROFILE) -covermode=atomic ./...
	@echo ""
	@echo "===> Coverage report"
	go tool cover -func=$(COVERAGE_PROFILE)

$(GOLANGCI_LINT_PATH):
	@echo "===> Installing golangci-lint $(GOLANGCI_LINT_VERSION)"
	@mkdir -p $(HOME)/.local/bin
	@curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b /tmp $(GOLANGCI_LINT_VERSION)
	@mv /tmp/golangci-lint $(GOLANGCI_LINT_PATH)

lint: $(GOLANGCI_LINT_PATH)
	@echo "===> Running lint"
	@$(GOLANGCI_LINT_PATH) run

fmt: $(GOLANGCI_LINT_PATH)
	@echo "===> Running fmt"
	@$(GOLANGCI_LINT_PATH) fmt

bench:
	@echo "===> Running benchmarks"
	go test -bench=. -benchmem -run=^$ ./...

fuzz:
	@echo "===> Fuzzing (60s)"
	go test $(LDFLAGS) -run=^$$ -fuzz=FuzzOps -fuzztime=60s .
