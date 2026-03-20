package web

import (
	"embed"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"

	"clawpi/internal/gateway"
	"clawpi/internal/quickshell"
)

//go:embed landing-page
var landingFS embed.FS

var quickshellController *quickshell.Controller
var gatewayClient *gateway.Client

func Serve(addr string, canvasDir string, canvasArchiveDir string, ctrl *quickshell.Controller, gw *gateway.Client) error {
	quickshellController = ctrl
	gatewayClient = gw

	sub, err := fs.Sub(landingFS, "landing-page")
	if err != nil {
		return err
	}

	if err := os.MkdirAll(canvasDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(canvasArchiveDir, 0755); err != nil {
		return err
	}
	log.Printf("canvas directory: %s", canvasDir)
	log.Printf("canvas archive directory: %s", canvasArchiveDir)

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.Handle("/canvas/", http.StripPrefix("/canvas/", http.FileServer(http.Dir(canvasDir))))

	// Show the TTS stop button overlay
	mux.HandleFunc("POST /api/tts/playing", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts: playback started")
		if quickshellController != nil {
			quickshellController.SetTTSPlaying(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Kill any active pw-play process and hide the stop button
	mux.HandleFunc("POST /api/tts/stop", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts stop: request received")
		out, err := exec.Command("/run/current-system/sw/bin/pkill", "-f", "pw-play").CombinedOutput()
		if err != nil {
			log.Printf("tts stop: pkill: %v (%s)", err, string(out))
		} else {
			log.Println("tts stop: killed pw-play")
		}
		if quickshellController != nil {
			quickshellController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Interrupt: abort the active agent run, kill TTS, reset state
	mux.HandleFunc("POST /api/interrupt", func(w http.ResponseWriter, r *http.Request) {
		log.Println("interrupt: request received")

		// Kill any active TTS playback
		if out, err := exec.Command("/run/current-system/sw/bin/pkill", "-f", "pw-play").CombinedOutput(); err != nil {
			log.Printf("interrupt: pkill pw-play: %v (%s)", err, string(out))
		}

		// Abort the agent run via gateway
		if gatewayClient != nil {
			if err := gatewayClient.Abort(); err != nil {
				log.Printf("interrupt: abort: %v", err)
			}
		}

		// Reset UI state
		if quickshellController != nil {
			quickshellController.SetTTSPlaying(false)
			quickshellController.SetMessage("")
			quickshellController.SetState(quickshell.StateIdle)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the TTS stop button (called when playback ends naturally)
	mux.HandleFunc("POST /api/tts/stopped", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts: playback ended")
		if quickshellController != nil {
			quickshellController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Show the recording indicator overlay
	mux.HandleFunc("POST /api/recording/start", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: started")
		if quickshellController != nil {
			quickshellController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the recording indicator overlay
	mux.HandleFunc("POST /api/recording/stop", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: stopped")
		if quickshellController != nil {
			quickshellController.SetRecording(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Voice pipeline state callbacks (called by voice-pipeline.py via _notify_state)
	mux.HandleFunc("POST /api/voice/listening", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: listening (recording speech)")
		if quickshellController != nil {
			quickshellController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/transcribing", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: transcribing")
		if quickshellController != nil {
			quickshellController.SetRecording(false)
			quickshellController.SetState(quickshell.StateTranscribing)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/delivering", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: delivering to agent")
		if quickshellController != nil {
			quickshellController.SetState(quickshell.StateDelivering)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/not_understood", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: not understood (empty transcript)")
		if quickshellController != nil {
			quickshellController.SetMessage("Didn't catch that")
			quickshellController.SetState(quickshell.StateError)
			go func() {
				time.Sleep(3 * time.Second)
				quickshellController.SetState(quickshell.StateIdle)
			}()
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/idle", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: idle")
		if quickshellController != nil {
			quickshellController.SetRecording(false)
			quickshellController.SetState(quickshell.StateIdle)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	log.Printf("web server listening on %s", addr)
	return http.Serve(ln, mux)
}
