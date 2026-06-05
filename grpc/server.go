// Package grpcsvc implements a gRPC front end for the macos-vision CLI.
//
// Each RPC shells out to the signed `macos-vision` binary with `--no-stream`,
// reads the JSON envelope it prints to stdout, and maps it into the proto
// response types. All inference runs on-device via Apple's Vision framework.
package grpcsvc

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"math"
	"os"
	"os/exec"
	"path/filepath"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/accretional/macos-vision/grpc/gen/macosvisionpb"
)

// Server implements pb.VisionServiceServer by invoking the macos-vision CLI.
type Server struct {
	pb.UnimplementedVisionServiceServer

	// CLIPath is the path to the macos-vision binary. Defaults to "macos-vision"
	// (resolved on PATH) when empty.
	CLIPath string
}

// NewServer returns a Server. If cliPath is empty it resolves "macos-vision"
// on the PATH; if that fails it falls back to the literal name so the error
// surfaces clearly on first invocation.
func NewServer(cliPath string) *Server {
	if cliPath == "" {
		if p, err := exec.LookPath("macos-vision"); err == nil {
			cliPath = p
		} else {
			cliPath = "macos-vision"
		}
	}
	return &Server{CLIPath: cliPath}
}

func (s *Server) cli() string {
	if s.CLIPath == "" {
		return "macos-vision"
	}
	return s.CLIPath
}

// envelope mirrors the CLI's standard JSON envelope (see MVJsonEmit).
type envelope struct {
	CLIVersion string          `json:"cliVersion"`
	Subcommand string          `json:"subcommand"`
	Operation  string          `json:"operation"`
	Input      string          `json:"input"`
	Result     json.RawMessage `json:"result"`
}

// materialize writes the request image to a temp file when it carries bytes,
// or returns the supplied path. The returned cleanup func removes any temp file.
func materialize(img *pb.Image) (path string, cleanup func(), err error) {
	if img == nil {
		return "", func() {}, status.Error(codes.InvalidArgument, "image is required")
	}
	if len(img.GetImageBytes()) > 0 {
		f, err := os.CreateTemp("", "macos-vision-*.img")
		if err != nil {
			return "", func() {}, status.Errorf(codes.Internal, "create temp file: %v", err)
		}
		if _, err := f.Write(img.GetImageBytes()); err != nil {
			f.Close()
			os.Remove(f.Name())
			return "", func() {}, status.Errorf(codes.Internal, "write temp file: %v", err)
		}
		f.Close()
		return f.Name(), func() { os.Remove(f.Name()) }, nil
	}
	if p := img.GetPath(); p != "" {
		if _, err := os.Stat(p); err != nil {
			return "", func() {}, status.Errorf(codes.InvalidArgument, "image path not accessible: %v", err)
		}
		return p, func() {}, nil
	}
	return "", func() {}, status.Error(codes.InvalidArgument, "image must set image_bytes or path")
}

// run invokes the CLI and decodes the envelope's result into out. args must
// start with the subcommand; "--no-stream" is inserted right after it so the
// CLI never auto-switches to MJPEG stream mode when stdout is a pipe.
func (s *Server) run(ctx context.Context, out interface{}, args ...string) error {
	if len(args) == 0 {
		return status.Error(codes.Internal, "run: missing subcommand")
	}
	full := append([]string{args[0], "--no-stream"}, args[1:]...)
	cmd := exec.CommandContext(ctx, s.cli(), full...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return status.Errorf(codes.Internal, "macos-vision %v failed: %v: %s", args, err, stderr.String())
	}
	var env envelope
	if err := json.Unmarshal(stdout.Bytes(), &env); err != nil {
		return status.Errorf(codes.Internal, "parse CLI envelope: %v (stderr: %s)", err, stderr.String())
	}
	if len(env.Result) == 0 {
		return status.Errorf(codes.Internal, "CLI returned empty result (stderr: %s)", stderr.String())
	}
	if err := json.Unmarshal(env.Result, out); err != nil {
		return status.Errorf(codes.Internal, "decode CLI result: %v", err)
	}
	return nil
}

// ── JSON shapes emitted by the CLI ───────────────────────────────────────────

type jsonInfo struct {
	Filename string `json:"filename"`
	Filepath string `json:"filepath"`
	Width    int32  `json:"width"`
	Height   int32  `json:"height"`
}

func (j jsonInfo) toProto() *pb.ImageInfo {
	return &pb.ImageInfo{
		Filename: j.Filename,
		Filepath: j.Filepath,
		Width:    j.Width,
		Height:   j.Height,
	}
}

type jsonPoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

func (j jsonPoint) toProto() *pb.Point { return &pb.Point{X: j.X, Y: j.Y} }

type jsonBox struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

func (j jsonBox) toProto() *pb.BoundingBox {
	return &pb.BoundingBox{X: j.X, Y: j.Y, Width: j.Width, Height: j.Height}
}

type jsonQuad struct {
	TopLeft     jsonPoint `json:"topLeft"`
	TopRight    jsonPoint `json:"topRight"`
	BottomRight jsonPoint `json:"bottomRight"`
	BottomLeft  jsonPoint `json:"bottomLeft"`
}

func (j jsonQuad) toProto() *pb.Quad {
	return &pb.Quad{
		TopLeft:     j.TopLeft.toProto(),
		TopRight:    j.TopRight.toProto(),
		BottomRight: j.BottomRight.toProto(),
		BottomLeft:  j.BottomLeft.toProto(),
	}
}

type jsonLabel struct {
	Identifier string  `json:"identifier"`
	Confidence float32 `json:"confidence"`
}

func (j jsonLabel) toProto() *pb.Label {
	return &pb.Label{Identifier: j.Identifier, Confidence: j.Confidence}
}

// ── RecognizeText ────────────────────────────────────────────────────────────

func (s *Server) RecognizeText(ctx context.Context, req *pb.RecognizeTextRequest) (*pb.RecognizeTextResponse, error) {
	path, cleanup, err := materialize(req.GetImage())
	if err != nil {
		return nil, err
	}
	defer cleanup()

	args := []string{"ocr", "--input", path}
	if langs := req.GetRecognitionLanguages(); len(langs) > 0 {
		joined := langs[0]
		for _, l := range langs[1:] {
			joined += "," + l
		}
		args = append(args, "--rec-langs", joined)
	}

	var result struct {
		Info         jsonInfo `json:"info"`
		Texts        string   `json:"texts"`
		Observations []struct {
			Text       string   `json:"text"`
			Confidence float32  `json:"confidence"`
			Quad       jsonQuad `json:"quad"`
		} `json:"observations"`
	}
	if err := s.run(ctx, &result, args...); err != nil {
		return nil, err
	}

	resp := &pb.RecognizeTextResponse{Info: result.Info.toProto(), Text: result.Texts}
	for _, o := range result.Observations {
		resp.Observations = append(resp.Observations, &pb.TextObservation{
			Text:       o.Text,
			Confidence: o.Confidence,
			Quad:       o.Quad.toProto(),
		})
	}
	return resp, nil
}

// ── ComputeImageFeaturePrint ─────────────────────────────────────────────────

func (s *Server) ComputeImageFeaturePrint(ctx context.Context, req *pb.ComputeImageFeaturePrintRequest) (*pb.ComputeImageFeaturePrintResponse, error) {
	path, cleanup, err := materialize(req.GetImage())
	if err != nil {
		return nil, err
	}
	defer cleanup()

	var result struct {
		Info         jsonInfo `json:"info"`
		FeaturePrint struct {
			ElementType  string `json:"elementType"`
			ElementCount int32  `json:"elementCount"`
			Data         string `json:"data"`
		} `json:"featurePrint"`
	}
	if err := s.run(ctx, &result, "classify", "--input", path, "--operation", "feature-print"); err != nil {
		return nil, err
	}

	raw, err := base64.StdEncoding.DecodeString(result.FeaturePrint.Data)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "decode feature print base64: %v", err)
	}
	vec, err := decodeVector(raw, result.FeaturePrint.ElementType)
	if err != nil {
		return nil, err
	}

	return &pb.ComputeImageFeaturePrintResponse{
		Info:        result.Info.toProto(),
		Vector:      vec,
		Dimensions:  int32(len(vec)),
		ElementType: result.FeaturePrint.ElementType,
	}, nil
}

// decodeVector unpacks the raw little-endian element buffer Vision emits.
func decodeVector(raw []byte, elementType string) ([]float32, error) {
	switch elementType {
	case "", "float":
		if len(raw)%4 != 0 {
			return nil, status.Errorf(codes.Internal, "float buffer length %d not a multiple of 4", len(raw))
		}
		out := make([]float32, len(raw)/4)
		for i := range out {
			out[i] = math.Float32frombits(binary.LittleEndian.Uint32(raw[i*4:]))
		}
		return out, nil
	case "double":
		if len(raw)%8 != 0 {
			return nil, status.Errorf(codes.Internal, "double buffer length %d not a multiple of 8", len(raw))
		}
		out := make([]float32, len(raw)/8)
		for i := range out {
			out[i] = float32(math.Float64frombits(binary.LittleEndian.Uint64(raw[i*8:])))
		}
		return out, nil
	default:
		return nil, status.Errorf(codes.Internal, "unknown feature print element type %q", elementType)
	}
}

// ── ClassifyImage ────────────────────────────────────────────────────────────

func (s *Server) ClassifyImage(ctx context.Context, req *pb.ClassifyImageRequest) (*pb.ClassifyImageResponse, error) {
	path, cleanup, err := materialize(req.GetImage())
	if err != nil {
		return nil, err
	}
	defer cleanup()

	var result struct {
		Info            jsonInfo    `json:"info"`
		Classifications []jsonLabel `json:"classifications"`
	}
	if err := s.run(ctx, &result, "classify", "--input", path, "--operation", "classify"); err != nil {
		return nil, err
	}

	resp := &pb.ClassifyImageResponse{Info: result.Info.toProto()}
	for _, c := range result.Classifications {
		resp.Classifications = append(resp.Classifications, c.toProto())
	}
	return resp, nil
}

// ── RecognizeAnimals ─────────────────────────────────────────────────────────

func (s *Server) RecognizeAnimals(ctx context.Context, req *pb.RecognizeAnimalsRequest) (*pb.RecognizeAnimalsResponse, error) {
	path, cleanup, err := materialize(req.GetImage())
	if err != nil {
		return nil, err
	}
	defer cleanup()

	var result struct {
		Info    jsonInfo `json:"info"`
		Animals []struct {
			BoundingBox jsonBox     `json:"boundingBox"`
			Confidence  float32     `json:"confidence"`
			Labels      []jsonLabel `json:"labels"`
		} `json:"animals"`
	}
	if err := s.run(ctx, &result, "classify", "--input", path, "--operation", "animals"); err != nil {
		return nil, err
	}

	resp := &pb.RecognizeAnimalsResponse{Info: result.Info.toProto()}
	for _, a := range result.Animals {
		obs := &pb.AnimalObservation{
			BoundingBox: a.BoundingBox.toProto(),
			Confidence:  a.Confidence,
		}
		for _, l := range a.Labels {
			obs.Labels = append(obs.Labels, l.toProto())
		}
		resp.Animals = append(resp.Animals, obs)
	}
	return resp, nil
}

// ── DetectFaces ──────────────────────────────────────────────────────────────

func (s *Server) DetectFaces(ctx context.Context, req *pb.DetectFacesRequest) (*pb.DetectFacesResponse, error) {
	path, cleanup, err := materialize(req.GetImage())
	if err != nil {
		return nil, err
	}
	defer cleanup()

	var result struct {
		Info  jsonInfo `json:"info"`
		Faces []struct {
			BoundingBox jsonBox `json:"boundingBox"`
			Confidence  float32 `json:"confidence"`
		} `json:"faces"`
	}
	if err := s.run(ctx, &result, "face", "--input", path, "--operation", "face-rectangles"); err != nil {
		return nil, err
	}

	resp := &pb.DetectFacesResponse{Info: result.Info.toProto()}
	for _, f := range result.Faces {
		resp.Faces = append(resp.Faces, &pb.FaceObservation{
			BoundingBox: f.BoundingBox.toProto(),
			Confidence:  f.Confidence,
		})
	}
	return resp, nil
}

// ── GetCapabilities ──────────────────────────────────────────────────────────

func (s *Server) GetCapabilities(ctx context.Context, _ *pb.GetCapabilitiesRequest) (*pb.GetCapabilitiesResponse, error) {
	cliPath := s.cli()
	if abs, err := filepath.Abs(cliPath); err == nil {
		cliPath = abs
	}
	return &pb.GetCapabilitiesResponse{
		CliPath: cliPath,
		Capabilities: []*pb.Capability{
			{Rpc: "RecognizeText", CliInvocation: "ocr", Description: "On-device OCR / text recognition"},
			{Rpc: "ComputeImageFeaturePrint", CliInvocation: "classify feature-print", Description: "Image embedding / perceptual feature vector"},
			{Rpc: "ClassifyImage", CliInvocation: "classify classify", Description: "Scene / object classification labels"},
			{Rpc: "RecognizeAnimals", CliInvocation: "classify animals", Description: "Animal detection with bounding boxes and labels"},
			{Rpc: "DetectFaces", CliInvocation: "face face-rectangles", Description: "Face bounding-box detection"},
		},
	}, nil
}
