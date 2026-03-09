package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	GatewayURL string
	Token      string
	WebAddr    string
	CanvasDir  string
	Debug      bool
}

func Load() (*Config, error) {
	gatewayURL := os.Getenv("CLAWPI_GATEWAY_URL")
	if gatewayURL == "" {
		gatewayURL = "ws://localhost:18789"
	}

	token := os.Getenv("OPENCLAW_GATEWAY_TOKEN")
	if token == "" {
		token = os.Getenv("CLAWPI_TOKEN")
	}

	// Try reading from the gateway token env file
	if token == "" {
		tokenFile := os.Getenv("CLAWPI_TOKEN_FILE")
		if tokenFile == "" {
			tokenFile = "/var/lib/kiosk/.openclaw/gateway-token.env"
		}
		data, err := os.ReadFile(tokenFile)
		if err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if strings.HasPrefix(line, "OPENCLAW_GATEWAY_TOKEN=") {
					token = strings.TrimPrefix(line, "OPENCLAW_GATEWAY_TOKEN=")
					break
				}
			}
		}
	}

	if token == "" {
		return nil, fmt.Errorf("no gateway token found (set OPENCLAW_GATEWAY_TOKEN, CLAWPI_TOKEN, or CLAWPI_TOKEN_FILE)")
	}

	webAddr := os.Getenv("CLAWPI_WEB_ADDR")
	if webAddr == "" {
		webAddr = ":3100"
	}

	canvasDir := os.Getenv("CLAWPI_CANVAS_DIR")
	if canvasDir == "" {
		canvasDir = "/tmp/clawpi-canvas"
	}

	debug := os.Getenv("CLAWPI_DEBUG") == "1" || os.Getenv("CLAWPI_DEBUG") == "true"

	return &Config{
		GatewayURL: gatewayURL,
		Token:      token,
		WebAddr:    webAddr,
		CanvasDir:  canvasDir,
		Debug:      debug,
	}, nil
}
