// Command visiond serves the macos-vision Apple Vision capabilities over gRPC.
//
// It enables server reflection so generic gRPC clients (grpcurl, the KVQ
// Dispatcher, etc.) can discover and invoke the VisionService without a
// compiled stub.
package main

import (
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	grpcsvc "github.com/accretional/macos-vision/grpc"
	pb "github.com/accretional/macos-vision/grpc/gen/macosvisionpb"
)

func main() {
	addr := flag.String("addr", ":50051", "host:port to listen on")
	cliPath := flag.String("cli", "", "path to the macos-vision binary (default: resolve on PATH)")
	flag.Parse()

	lis, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatalf("listen on %s: %v", *addr, err)
	}

	srv := grpc.NewServer()
	pb.RegisterVisionServiceServer(srv, grpcsvc.NewServer(*cliPath))
	reflection.Register(srv)

	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
		<-sig
		log.Println("shutting down")
		srv.GracefulStop()
	}()

	log.Printf("macos-vision gRPC server listening on %s", *addr)
	if err := srv.Serve(lis); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
