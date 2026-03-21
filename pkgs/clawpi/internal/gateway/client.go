package gateway

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// AgentState represents the current state of the agent as derived from gateway events.
type AgentState string

const (
	StateIdle         AgentState = "idle"
	StateThinking     AgentState = "thinking"
	StateResponding   AgentState = "responding"
	StateToolUse      AgentState = "tool_use"
	StateDisconnected AgentState = "disconnected"
)

type Client struct {
	url           string
	token         string
	Debug         bool
	OnStateChange func(state AgentState, toolName string)
	OnMessage     func(text string)
	OnDisconnect  func()
	OnConnect     func()

	mu         sync.Mutex
	conn       *websocket.Conn
	sessionKey string
}

func NewClient(url, token string) *Client {
	return &Client{url: url, token: token}
}

func (c *Client) emitState(state AgentState, toolName string) {
	if c.OnStateChange != nil {
		c.OnStateChange(state, toolName)
	}
}

// Abort cancels the active agent run for the current session and clears queued
// followups. Uses chat.abort which preserves conversation history.
func (c *Client) Abort() error {
	c.mu.Lock()
	conn := c.conn
	sk := c.sessionKey
	c.mu.Unlock()

	if conn == nil {
		return fmt.Errorf("not connected")
	}
	if sk == "" {
		sk = "main"
	}

	req := map[string]any{
		"type":   "req",
		"id":     randomID(),
		"method": "chat.abort",
		"params": map[string]any{
			"sessionKey": sk,
		},
	}

	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal abort request: %w", err)
	}

	c.mu.Lock()
	err = conn.WriteMessage(websocket.TextMessage, data)
	c.mu.Unlock()

	if err != nil {
		return fmt.Errorf("send abort: %w", err)
	}

	log.Printf("abort: sent chat.abort for %q", sk)
	return nil
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

		if c.OnDisconnect != nil {
			c.OnDisconnect()
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
	defer func() {
		c.mu.Lock()
		c.conn = nil
		c.mu.Unlock()
		conn.Close()
	}()

	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

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
				c.mu.Lock()
				err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(10*time.Second))
				c.mu.Unlock()
				if err != nil {
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

		if c.Debug {
			log.Printf("[ws-raw] %s", string(data))
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

			c.mu.Lock()
			err = conn.WriteMessage(websocket.TextMessage, reqData)
			c.mu.Unlock()
			if err != nil {
				return fmt.Errorf("send connect request: %w", err)
			}

			authenticated = true
			log.Printf("connect request sent")
			// Reset backoff on successful auth
			if c.OnConnect != nil {
				c.OnConnect()
			}
			continue
		}

		c.handleEvent(&msg, data)
	}
}

func (c *Client) handleEvent(msg *GatewayMessage, raw []byte) {
	// Skip noisy periodic events
	if msg.Event == "tick" || msg.Event == "health" {
		return
	}

	// Log all non-trivial events
	logMessage(msg, raw)

	if msg.Event != "agent" {
		return
	}

	// The gateway may deliver agent event data in either the "data" or
	// "payload" field depending on the protocol version.  Try both.
	eventData := msg.Data
	if len(eventData) == 0 {
		eventData = msg.Payload
	}
	if len(eventData) == 0 {
		return
	}

	var agentEvent AgentEventData
	if err := json.Unmarshal(eventData, &agentEvent); err != nil {
		return
	}

	// Track session key for abort
	if agentEvent.SessionKey != "" {
		c.mu.Lock()
		c.sessionKey = agentEvent.SessionKey
		c.mu.Unlock()
	}

	switch agentEvent.Stream {
	case "lifecycle":
		var lc LifecycleData
		if err := json.Unmarshal(agentEvent.Data, &lc); err != nil {
			return
		}
		switch lc.Phase {
		case "start":
			c.emitState(StateThinking, "")
		case "end":
			c.emitState(StateIdle, "")
		}

	case "assistant":
		c.emitState(StateResponding, "")
		var assistant AssistantEventData
		if err := json.Unmarshal(agentEvent.Data, &assistant); err == nil && assistant.Text != "" {
			if c.OnMessage != nil {
				c.OnMessage(assistant.Text)
			}
		}

	case "tool_use":
		var tool ToolEventData
		if err := json.Unmarshal(agentEvent.Data, &tool); err == nil && tool.Name != "" {
			c.emitState(StateToolUse, tool.Name)
		} else {
			c.emitState(StateToolUse, "tool")
		}

	case "tool_result":
		// Tool finished — agent likely goes back to thinking
		c.emitState(StateThinking, "")
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
