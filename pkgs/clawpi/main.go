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

	stateFile := os.Getenv("CLAWPI_STATE_FILE")
	if stateFile == "" {
		log.Fatal("CLAWPI_STATE_FILE not set")
	}

	ctrl := eww.NewController(stateFile)

	// Start web server with controller for TTS API
	go func() {
		if err := web.Serve(cfg.WebAddr, cfg.CanvasDir, cfg.CanvasArchiveDir, ctrl); err != nil {
			log.Fatalf("web server: %v", err)
		}
	}()

	client := gateway.NewClient(cfg.GatewayURL, cfg.Token)
	client.Debug = cfg.Debug

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
		os.Exit(0)
	}()

	log.Fatal(client.Run())
}
