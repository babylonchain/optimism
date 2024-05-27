GITCOMMIT ?= $(shell git rev-parse HEAD)
GITDATE ?= $(shell git show -s --format='%ct')
# Find the github tag that points to this commit. If none are found, set the version string to "untagged"
# Prioritizes release tag, if one exists, over tags suffixed with "-rc"
VERSION ?= $(shell tags=$$(git tag --points-at $(GITCOMMIT) | grep '^op-proposer/' | sed 's/op-proposer\///' | sort -V); \
             preferred_tag=$$(echo "$$tags" | grep -v -- '-rc' | tail -n 1); \
             if [ -z "$$preferred_tag" ]; then \
                 if [ -z "$$tags" ]; then \
                     echo "untagged"; \
                 else \
                     echo "$$tags" | tail -n 1; \
                 fi \
             else \
                 echo $$preferred_tag; \
             fi)

LDFLAGSSTRING +=-X main.GitCommit=$(GITCOMMIT)
LDFLAGSSTRING +=-X main.GitDate=$(GITDATE)
LDFLAGSSTRING +=-X main.Version=$(VERSION)
LDFLAGS := -ldflags "$(LDFLAGSSTRING)"

op-proposer:
	env GO111MODULE=on GOOS=$(TARGETOS) GOARCH=$(TARGETARCH) go build -v $(LDFLAGS) -o ./bin/op-proposer ./cmd

clean:
	rm bin/op-proposer

test:
	go test -v ./...

abis = ../packages/contracts-bedrock/snapshots/abi
artifacts = ../packages/contracts-bedrock/forge-artifacts
tmpfile = ./tmp.bin

bindings-upgrades:
	bash -c ' \
	set -euxo pipefail; \
	build_abi() { \
		local lowercase=$$(echo "$$1" | awk '"'"'{print tolower($$0)}'"'"'); \
		touch "$(tmpfile)"; \
		jq -r '.bytecode.object' < "$(artifacts)/$$1.sol/$$1.json" > "$(tmpfile)"; \
		abigen \
			--abi "$(abis)/$$1.json" \
			--bin "$(tmpfile)" \
			--pkg bindings \
			--out "bindings/$$lowercase.go" \
			--type $$1; \
		rm -f "$(tmpfile)"; \
	}; \
	build_abi L2OutputOracle \
	'

.PHONY: \
	clean \
	op-proposer \
	test \
	bindings-upgrades