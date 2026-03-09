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
	Seq           *int            `json:"seq,omitempty"`
	Payload       json.RawMessage `json:"payload,omitempty"`
	Data          json.RawMessage `json:"data,omitempty"`
}

// ChallengePayload is the payload of a connect.challenge event.
type ChallengePayload struct {
	Nonce string `json:"nonce"`
}

// ConnectRequest is the request frame sent to authenticate with the gateway.
// The gateway expects: { type: "req", id: <uuid>, method: "connect", params: {...} }
type ConnectRequest struct {
	Type   string        `json:"type"`
	ID     string        `json:"id"`
	Method string        `json:"method"`
	Params ConnectParams `json:"params"`
}

type ConnectParams struct {
	MinProtocol int           `json:"minProtocol"`
	MaxProtocol int           `json:"maxProtocol"`
	Client      ConnectClient `json:"client"`
	Caps        []string      `json:"caps"`
	Auth        *ConnectAuth  `json:"auth,omitempty"`
	Role        string        `json:"role"`
	Scopes      []string      `json:"scopes"`
}

type ConnectClient struct {
	ID       string `json:"id"`
	Version  string `json:"version"`
	Platform string `json:"platform"`
	Mode     string `json:"mode"`
}

type ConnectAuth struct {
	Token string `json:"token,omitempty"`
}

// AgentEventData is the data payload for event="agent" messages.
type AgentEventData struct {
	RunID      string          `json:"runId"`
	Stream     string          `json:"stream"`
	SessionKey string          `json:"sessionKey"`
	Seq        int             `json:"seq"`
	Data       json.RawMessage `json:"data"`
}

// LifecycleData is the inner data for stream="lifecycle" agent events.
type LifecycleData struct {
	Phase string `json:"phase"`
}

// ToolEventData is the inner data for stream="tool_use"/"tool_result" agent events.
type ToolEventData struct {
	Name string `json:"name"`
}
