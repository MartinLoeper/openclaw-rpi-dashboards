package gateway

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

type Client struct {
	url   string
	token string
}

func NewClient(url, token string) *Client {
	return &Client{url: url, token: token}
}

// Run connects to the gateway WebSocket and logs all received messages.
// It reconnects automatically with exponential backoff on disconnection.
// This function blocks forever unless a fatal error occurs.
func (c *Client) Run() error {
	backoff := time.Second
	const maxBackoff = 30 * time.Second

	for {
		err := c.connect()
		if err != nil {
			log.Printf("connection error: %v", err)
		}

		log.Printf("reconnecting in %v...", backoff)
		time.Sleep(backoff)
		backoff = min(backoff*2, maxBackoff)
	}
}

func (c *Client) connect() error {
	header := http.Header{}
	header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))

	wsURL := fmt.Sprintf("%s/?clientId=gateway-client&clientMode=gateway-client", c.url)
	log.Printf("connecting to %s", c.url)

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, header)
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}
	defer conn.Close()

	log.Printf("connected to gateway")

	// Set up ping/pong for connection health
	conn.SetPongHandler(func(string) error {
		return nil
	})

	// Start a goroutine to send periodic pings
	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second)); err != nil {
					log.Printf("ping failed: %v", err)
					return
				}
			case <-done:
				return
			}
		}
	}()

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			return fmt.Errorf("read: %w", err)
		}

		var msg GatewayMessage
		if err := json.Unmarshal(data, &msg); err != nil {
			log.Printf("unmarshal error: %v | raw: %s", err, truncate(string(data), 200))
			continue
		}

		logMessage(&msg, data)
	}
}

func logMessage(msg *GatewayMessage, raw []byte) {
	fields := fmt.Sprintf("stream=%q type=%q event=%q sessionUpdate=%q session=%q",
		msg.Stream, msg.Type, msg.Event, msg.SessionUpdate, msg.SessionKey)

	dataStr := ""
	if len(msg.Data) > 0 {
		dataStr = truncate(string(msg.Data), 300)
	}

	if dataStr != "" {
		log.Printf("[event] %s data=%s", fields, dataStr)
	} else {
		log.Printf("[event] %s", fields)
	}
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
