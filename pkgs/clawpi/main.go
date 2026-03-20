package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"

	"clawpi/internal/config"
	"clawpi/internal/quickshell"
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

	ctrl := quickshell.NewController(stateFile)

	client := gateway.NewClient(cfg.GatewayURL, cfg.Token)

	// Start web server with controller + gateway client for interrupt API
	go func() {
		if err := web.Serve(cfg.WebAddr, cfg.CanvasDir, cfg.CanvasArchiveDir, ctrl, client); err != nil {
			log.Fatalf("web server: %v", err)
		}
	}()
	client.Debug = cfg.Debug

	client.OnConnect = func() {
		ctrl.SetState(quickshell.StateIdle)
	}

	client.OnDisconnect = func() {
		ctrl.SetState(quickshell.StateDisconnected)
	}

	client.OnMessage = func(text string) {
		ctrl.SetMessage(text)
	}

	client.OnStateChange = func(state gateway.AgentState, toolName string) {
		switch state {
		case gateway.StateIdle:
			ctrl.SetState(quickshell.StateIdle)
		case gateway.StateThinking:
			ctrl.SetMessage("")
			ctrl.SetState(quickshell.StateThinking)
		case gateway.StateResponding:
			ctrl.SetState(quickshell.StateResponding)
		case gateway.StateToolUse:
			ctrl.SetToolName(toolName)
			ctrl.SetState(quickshell.StateToolUse)
		case gateway.StateDisconnected:
			ctrl.SetState(quickshell.StateDisconnected)
		}
	}

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		sig := <-sigCh
		log.Printf("received %v, shutting down", sig)
		ctrl.SetState(quickshell.StateIdle)
		os.Exit(0)
	}()

	log.Fatal(client.Run())
}
