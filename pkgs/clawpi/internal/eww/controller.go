package eww

import (
	"encoding/json"
	"log"
	"os"
	"sync"
)

type State string

const (
	StateIdle         State = "idle"
	StateTranscribing State = "transcribing"
	StateDelivering   State = "delivering"
	StateThinking     State = "thinking"
	StateResponding   State = "responding"
	StateToolUse      State = "tool_use"
	StateError        State = "error"
	StateDisconnected State = "disconnected"
)

type Controller struct {
	stateFile  string
	mu         sync.Mutex
	state      State
	toolName   string
	ttsPlaying bool
	recording  bool
	message    string
}

func NewController(stateFile string) *Controller {
	c := &Controller{
		stateFile: stateFile,
		state:     StateIdle,
	}
	// Write idle state on startup to clear any stale state from a previous run
	c.writeStateFile()
	return c
}

func (c *Controller) SetState(state State) {
	c.mu.Lock()
	prev := c.state
	c.state = state
	c.mu.Unlock()

	if state == prev {
		return
	}

	log.Printf("state: %s -> %s", prev, state)
	c.writeStateFile()
}

func (c *Controller) SetToolName(name string) {
	c.mu.Lock()
	c.toolName = name
	c.mu.Unlock()
	c.writeStateFile()
}

func (c *Controller) SetMessage(msg string) {
	c.mu.Lock()
	c.message = msg
	c.mu.Unlock()
	c.writeStateFile()
}

func (c *Controller) SetTTSPlaying(playing bool) {
	c.mu.Lock()
	c.ttsPlaying = playing
	c.mu.Unlock()
	c.writeStateFile()
}

func (c *Controller) SetRecording(recording bool) {
	c.mu.Lock()
	c.recording = recording
	c.mu.Unlock()
	c.writeStateFile()
}

func (c *Controller) writeStateFile() {
	c.mu.Lock()
	data, err := json.Marshal(map[string]any{
		"state":      string(c.state),
		"toolName":   c.toolName,
		"ttsPlaying": c.ttsPlaying,
		"recording":  c.recording,
		"message":    c.message,
	})
	path := c.stateFile
	c.mu.Unlock()

	if err != nil {
		log.Printf("eww: marshal state: %v", err)
		return
	}
	if path == "" {
		return
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		log.Printf("eww: write state file: %v", err)
	}
}
