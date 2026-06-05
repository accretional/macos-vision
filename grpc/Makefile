# Build and run the macos-vision gRPC service.
#
# The server shells out to the signed `macos-vision` CLI, so build/install that
# first (see the repo root Makefile: `make` or `make install`).

PROTO_DIR  := ../proto
GEN_DIR    := gen/macosvisionpb
ADDR       ?= :50051
CLI        ?=

.PHONY: all proto build run test clean

all: build

# Regenerate Go bindings from proto/vision.proto. Requires protoc,
# protoc-gen-go, and protoc-gen-go-grpc on PATH.
proto:
	protoc \
		-I $(PROTO_DIR) \
		--go_out=$(GEN_DIR) --go_opt=paths=source_relative \
		--go-grpc_out=$(GEN_DIR) --go-grpc_opt=paths=source_relative \
		$(PROTO_DIR)/vision.proto

build:
	go build ./...

# Run the server. Override ADDR / CLI as needed, e.g.
#   make run ADDR=:50077 CLI=../.build/debug/macos-vision
run:
	go run ./cmd/visiond --addr $(ADDR) $(if $(CLI),--cli $(CLI),)

test:
	go test ./...

clean:
	go clean ./...
