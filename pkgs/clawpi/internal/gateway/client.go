package gateway

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
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
	wsURL := fmt.Sprintf("%s/?clientId=gateway-client&clientMode=gateway-client", c.url)
	log.Printf("connecting to %s", c.url)

	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}
	defer conn.Close()

	log.Printf("connected, waiting for challenge...")

	// Start periodic pings
	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second)); err != nil {
					return
				}
			case <-done:
				return
			}
		}
	}()

	authenticated := false

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

		// Handle connect.challenge — respond with auth token
		if msg.Event == "connect.challenge" && !authenticated {
			var challenge ChallengePayload
			if err := json.Unmarshal(msg.Payload, &challenge); err != nil {
				log.Printf("failed to parse challenge payload: %v", err)
				continue
			}

			log.Printf("received challenge (nonce=%s), authenticating...", truncate(challenge.Nonce, 16))

			connectReq := ConnectRequest{
				Type:   "req",
				ID:     randomID(),
				Method: "connect",
				Params: ConnectParams{
					MinProtocol: 3,
					MaxProtocol: 3,
					Client: ConnectClient{
						ID:       "gateway-client",
						Version:  "0.1.0",
						Platform: "linux",
						Mode:     "backend",
					},
					Caps:   []string{"tool-events"},
					Auth:   &ConnectAuth{Token: c.token},
					Role:   "operator",
					Scopes: []string{"operator.admin"},
				},
			}

			reqData, err := json.Marshal(connectReq)
			if err != nil {
				return fmt.Errorf("marshal connect request: %w", err)
			}

			if err := conn.WriteMessage(websocket.TextMessage, reqData); err != nil {
				return fmt.Errorf("send connect request: %w", err)
			}

			authenticated = true
			log.Printf("connect request sent")
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
	if dataStr == "" && len(msg.Payload) > 0 {
		dataStr = truncate(string(msg.Payload), 300)
	}

	if dataStr != "" {
		log.Printf("[event] %s data=%s", fields, dataStr)
	} else {
		log.Printf("[event] %s | raw=%s", fields, truncate(string(raw), 500))
	}
}

func randomID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
