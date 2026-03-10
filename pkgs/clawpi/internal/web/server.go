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

	"clawpi/internal/eww"
)

//go:embed landing-page
var landingFS embed.FS

// TTSStopFunc is called when the TTS stop endpoint is hit.
// Set by main to wire up the eww controller.
var ewwController *eww.Controller

func Serve(addr string, canvasDir string, canvasArchiveDir string, ctrl *eww.Controller) error {
	ewwController = ctrl

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
		if ewwController != nil {
			ewwController.SetTTSPlaying(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Kill any active pw-play process and hide the stop button
	mux.HandleFunc("POST /api/tts/stop", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts stop: request received")
		out, err := exec.Command("pkill", "-f", "pw-play").CombinedOutput()
		if err != nil {
			log.Printf("tts stop: pkill: %v (%s)", err, string(out))
		} else {
			log.Println("tts stop: killed pw-play")
		}
		if ewwController != nil {
			ewwController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the TTS stop button (called when playback ends naturally)
	mux.HandleFunc("POST /api/tts/stopped", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts: playback ended")
		if ewwController != nil {
			ewwController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Show the recording indicator overlay
	mux.HandleFunc("POST /api/recording/start", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: started")
		if ewwController != nil {
			ewwController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the recording indicator overlay
	mux.HandleFunc("POST /api/recording/stop", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: stopped")
		if ewwController != nil {
			ewwController.SetRecording(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Voice pipeline state callbacks (called by voice-pipeline.py via _notify_state)
	mux.HandleFunc("POST /api/voice/listening", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: listening (recording speech)")
		if ewwController != nil {
			ewwController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/transcribing", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: transcribing")
		if ewwController != nil {
			ewwController.SetRecording(false)
			ewwController.SetState(eww.StateTranscribing)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/delivering", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: delivering to agent")
		if ewwController != nil {
			ewwController.SetState(eww.StateDelivering)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/not_understood", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: not understood (empty transcript)")
		if ewwController != nil {
			ewwController.SetMessage("Didn't catch that")
			ewwController.SetState(eww.StateError)
			go func() {
				time.Sleep(3 * time.Second)
				ewwController.SetState(eww.StateIdle)
			}()
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/idle", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: idle")
		if ewwController != nil {
			ewwController.SetRecording(false)
			ewwController.SetState(eww.StateIdle)
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
