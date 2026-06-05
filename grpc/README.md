# macos-vision gRPC service

A thin gRPC front end for local, on-device inference with Apple's Vision
framework. The server (`visiond`) shells out to the signed `macos-vision` CLI
with `--no-stream`, parses its JSON envelope, and returns structured proto
responses. No network calls, no cloud — everything runs on-device.

Server reflection is enabled, so generic clients (`grpcurl`, the KVQ Dispatcher,
etc.) can discover and call the service without a compiled stub.

## Service

`macosvision.VisionService` (see [`../proto/vision.proto`](../proto/vision.proto)):

| RPC | Backing CLI invocation | Result |
|-----|------------------------|--------|
| `RecognizeText` | `ocr` | OCR observations (text + quad + confidence) and joined text |
| `ComputeImageFeaturePrint` | `classify --operation feature-print` | Image embedding (`repeated float`) + dimensions |
| `ClassifyImage` | `classify --operation classify` | Scene/object labels + confidences |
| `RecognizeAnimals` | `classify --operation animals` | Animal bounding boxes + labels |
| `DetectFaces` | `face --operation face-rectangles` | Face bounding boxes + confidence |
| `GetCapabilities` | — | Self-description of exposed capabilities |

Requests carry the image as either raw `image_bytes` or a server-local `path`.
Coordinates are normalized to `[0,1]` with the origin at the **top-left**.

## Build

```bash
# 1. Build (and code-sign) the macos-vision CLI from the repo root:
make            # produces .build/debug/macos-vision

# 2. Build the gRPC service:
cd grpc
make build      # or: go build ./...
```

## Run

```bash
# Convenience script: builds the CLI if missing, then serves on :50051.
./run.sh                 # or ./run.sh :50077

# Or directly:
go run ./cmd/visiond --addr :50051 --cli ../.build/debug/macos-vision
```

`--cli` defaults to resolving `macos-vision` on `PATH` (i.e. after `make install`).

## Try it with grpcurl

```bash
grpcurl -plaintext localhost:50051 list macosvision.VisionService

# OCR from a server-local path:
grpcurl -plaintext \
  -d '{"image":{"path":"/abs/path/to/image.png"}}' \
  localhost:50051 macosvision.VisionService.RecognizeText

# Image embedding from inlined bytes:
B64=$(base64 < image.png)
grpcurl -plaintext \
  -d "{\"image\":{\"image_bytes\":\"$B64\"}}" \
  localhost:50051 macosvision.VisionService.ComputeImageFeaturePrint
```

## Regenerating bindings

Generated code lives under `gen/macosvisionpb/` and should not be hand-edited.

```bash
make proto   # requires protoc, protoc-gen-go, protoc-gen-go-grpc
```
