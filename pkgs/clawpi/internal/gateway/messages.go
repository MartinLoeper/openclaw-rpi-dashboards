package gateway

import "encoding/json"

// GatewayMessage represents a message received from the OpenClaw gateway WebSocket.
// The exact schema is not fully documented, so we capture the raw payload for logging
// and parse known fields defensively.
type GatewayMessage struct {
	Stream        string          `json:"stream,omitempty"`
	Type          string          `json:"type,omitempty"`
	Event         string          `json:"event,omitempty"`
	SessionKey    string          `json:"sessionKey,omitempty"`
	SessionUpdate string          `json:"sessionUpdate,omitempty"`
	Data          json.RawMessage `json:"data,omitempty"`
}
