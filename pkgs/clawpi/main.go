package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"clawpi/internal/config"
	"clawpi/internal/gateway"
)

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
	log.Println("clawpi starting")

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	client := gateway.NewClient(cfg.GatewayURL, cfg.Token)

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		sig := <-sigCh
		log.Printf("received %v, shutting down", sig)
		os.Exit(0)
	}()

	log.Fatal(client.Run())
}
