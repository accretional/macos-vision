#!/usr/bin/env bash
# Build the macos-vision CLI (if needed) and run the gRPC server against it.
#
# Usage: ./run.sh [addr]
#   addr  host:port to listen on (default :50051)
set -euo pipefail

ADDR="${1:-:50051}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/.build/debug/macos-vision"

if [[ ! -x "$CLI" ]]; then
  echo "Building macos-vision CLI..." >&2
  (cd "$ROOT" && make build)
fi

echo "Starting visiond on $ADDR (cli: $CLI)" >&2
exec go run "$ROOT/grpc/cmd/visiond" --addr "$ADDR" --cli "$CLI"
