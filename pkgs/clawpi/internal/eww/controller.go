package eww

import (
	"fmt"
	"log"
	"os/exec"
	"strings"
	"sync"
)

type State string

const (
	StateIdle         State = "idle"
	StateThinking     State = "thinking"
	StateResponding   State = "responding"
	StateToolUse      State = "tool_use"
	StateError        State = "error"
	StateDisconnected State = "disconnected"
)

type Controller struct {
	configDir string
	mu        sync.Mutex
	state     State
	running   bool
}

func NewController(configDir string) *Controller {
	return &Controller{
		configDir: configDir,
		state:     StateIdle,
	}
}

func (c *Controller) StartDaemon() error {
	// Kill any existing eww daemon first
	c.ewwCmd("kill")

	if err := c.ewwCmd("daemon"); err != nil {
		return fmt.Errorf("start eww daemon: %w", err)
	}
	c.running = true
	log.Println("eww daemon started")
	return nil
}

func (c *Controller) OpenWindow(name string) {
	if err := c.ewwCmd("open", name); err != nil {
		log.Printf("eww open %s: %v", name, err)
	}
}

func (c *Controller) CloseWindow(name string) {
	if err := c.ewwCmd("close", name); err != nil {
		log.Printf("eww close %s: %v", name, err)
	}
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
	c.update("clawpi_state", string(state))

	if state == StateIdle {
		c.CloseWindow("status-overlay")
	} else if prev == StateIdle {
		c.OpenWindow("status-overlay")
	}
}

func (c *Controller) SetToolName(name string) {
	c.update("clawpi_tool_name", name)
}

func (c *Controller) SetMessage(msg string) {
	c.update("clawpi_message", msg)
}

func (c *Controller) Shutdown() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.running {
		c.ewwCmd("close", "status-overlay")
		c.ewwCmd("kill")
		c.running = false
		log.Println("eww daemon stopped")
	}
}

func (c *Controller) update(variable, value string) {
	arg := fmt.Sprintf("%s=%s", variable, value)
	if err := c.ewwCmd("update", arg); err != nil {
		log.Printf("eww update %s: %v", arg, err)
	}
}

func (c *Controller) ewwCmd(args ...string) error {
	fullArgs := append([]string{"--config", c.configDir}, args...)
	cmd := exec.Command("eww", fullArgs...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %s", strings.Join(args, " "), strings.TrimSpace(string(output)))
	}
	return nil
}
