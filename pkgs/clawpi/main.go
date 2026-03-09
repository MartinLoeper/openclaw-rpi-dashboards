package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"clawpi/internal/config"
	"clawpi/internal/eww"
	"clawpi/internal/gateway"
	"clawpi/internal/web"
)

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
	log.Println("clawpi starting")

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	// Start web server early so the landing page is available
	// even if eww or gateway setup fails
	go func() {
		if err := web.Serve(cfg.WebAddr); err != nil {
			log.Fatalf("web server: %v", err)
		}
	}()

	ewwConfigDir := os.Getenv("CLAWPI_EWW_CONFIG")
	if ewwConfigDir == "" {
		log.Fatal("CLAWPI_EWW_CONFIG not set")
	}

	ctrl := eww.NewController(ewwConfigDir)
	if err := ctrl.StartDaemon(); err != nil {
		log.Printf("eww: %v (overlays disabled)", err)
	}

	ctrl.SetState(eww.StateDisconnected)

	client := gateway.NewClient(cfg.GatewayURL, cfg.Token)

	client.OnConnect = func() {
		ctrl.SetState(eww.StateIdle)
	}

	client.OnDisconnect = func() {
		ctrl.SetState(eww.StateDisconnected)
	}

	client.OnStateChange = func(state gateway.AgentState, toolName string) {
		switch state {
		case gateway.StateIdle:
			ctrl.SetState(eww.StateIdle)
		case gateway.StateThinking:
			ctrl.SetState(eww.StateThinking)
		case gateway.StateResponding:
			ctrl.SetState(eww.StateResponding)
		case gateway.StateToolUse:
			ctrl.SetToolName(toolName)
			ctrl.SetState(eww.StateToolUse)
		case gateway.StateDisconnected:
			ctrl.SetState(eww.StateDisconnected)
		}
	}

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		sig := <-sigCh
		log.Printf("received %v, shutting down", sig)
		ctrl.SetState(eww.StateIdle)
		ctrl.Shutdown()
		os.Exit(0)
	}()

	log.Fatal(client.Run())
}
