// Command run_automation reads a chromerpc AutomationSequence textproto file,
// executes it against a running chromerpc gRPC server, and writes any
// screenshot step results to disk.
//
// Usage:
//
//	run_automation -addr localhost:50051 \
//	               -automation automations/smoke_test.textproto \
//	               -out screenshots/smoke_test.png
//
// The -out flag sets the destination for the last screenshot step's data.
// If the automation has multiple screenshot steps, -label selects which
// one to save (defaults to the last step labelled "screenshot").
package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
	"time"

	hbpb "github.com/accretional/chromerpc/proto/cdp/headlessbrowser"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/encoding/prototext"
)

func main() {
	addr := flag.String("addr", "localhost:50051", "chromerpc gRPC server address")
	automationFile := flag.String("automation", "", "path to .textproto automation file (required)")
	outFile := flag.String("out", "", "path to write screenshot PNG (required for screenshot steps)")
	screenshotLabel := flag.String("label", "screenshot", "step label whose screenshot_data to save")
	timeout := flag.Duration("timeout", 60*time.Second, "per-automation timeout")
	flag.Parse()

	if *automationFile == "" {
		die("--automation is required")
	}

	data, err := os.ReadFile(*automationFile)
	if err != nil {
		die("read %s: %v", *automationFile, err)
	}

	seq := &hbpb.AutomationSequence{}
	if err := prototext.Unmarshal(data, seq); err != nil {
		die("parse %s: %v", *automationFile, err)
	}

	if !serverReachable(*addr) {
		die("chromerpc not reachable at %s — start the server first (see LET_IT_RIP.sh)", *addr)
	}

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	conn, err := grpc.NewClient(*addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		die("dial %s: %v", *addr, err)
	}
	defer conn.Close()

	client := hbpb.NewHeadlessBrowserServiceClient(conn)

	fmt.Printf("running automation %q (%d steps) against %s\n", seq.Name, len(seq.Steps), *addr)

	res, err := client.RunAutomation(ctx, seq)
	if err != nil {
		die("RunAutomation: %v", err)
	}
	if !res.Success {
		die("automation failed: %s", res.Error)
	}

	fmt.Printf("automation succeeded — %d step results\n", len(res.StepResults))

	if *outFile == "" {
		return
	}

	// Find the target screenshot step result. We prefer an exact label match;
	// fall back to the last step that has screenshot data.
	var chosen []byte
	for _, sr := range res.StepResults {
		if len(sr.ScreenshotData) == 0 {
			continue
		}
		if sr.Label == *screenshotLabel {
			chosen = sr.ScreenshotData
		} else if chosen == nil {
			// Take the first screenshot we find as a fallback.
			chosen = sr.ScreenshotData
		}
	}

	if len(chosen) == 0 {
		die("no screenshot_data in step results (looked for label=%q)", *screenshotLabel)
	}

	if err := os.WriteFile(*outFile, chosen, 0o644); err != nil {
		die("write %s: %v", *outFile, err)
	}
	fmt.Printf("screenshot written to %s (%d bytes)\n", *outFile, len(chosen))
}

func serverReachable(addr string) bool {
	c, err := net.DialTimeout("tcp", addr, 500*time.Millisecond)
	if err != nil {
		return false
	}
	_ = c.Close()
	return true
}

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "run_automation: "+format+"\n", args...)
	os.Exit(1)
}
