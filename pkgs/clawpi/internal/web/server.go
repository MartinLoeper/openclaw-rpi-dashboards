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

	"clawpi/internal/quickshell"
)

//go:embed landing-page
var landingFS embed.FS

// qsController is set by main to wire up the quickshell controller.
var qsController *quickshell.Controller

func Serve(addr string, canvasDir string, canvasArchiveDir string, ctrl *quickshell.Controller) error {
	qsController = ctrl

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
		if qsController != nil {
			qsController.SetTTSPlaying(true)
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
		if qsController != nil {
			qsController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the TTS stop button (called when playback ends naturally)
	mux.HandleFunc("POST /api/tts/stopped", func(w http.ResponseWriter, r *http.Request) {
		log.Println("tts: playback ended")
		if qsController != nil {
			qsController.SetTTSPlaying(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Show the recording indicator overlay
	mux.HandleFunc("POST /api/recording/start", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: started")
		if qsController != nil {
			qsController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Hide the recording indicator overlay
	mux.HandleFunc("POST /api/recording/stop", func(w http.ResponseWriter, r *http.Request) {
		log.Println("recording: stopped")
		if qsController != nil {
			qsController.SetRecording(false)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	// Voice pipeline state callbacks (called by voice-pipeline.py via _notify_state)
	mux.HandleFunc("POST /api/voice/listening", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: listening (recording speech)")
		if qsController != nil {
			qsController.SetRecording(true)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/transcribing", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: transcribing")
		if qsController != nil {
			qsController.SetRecording(false)
			qsController.SetState(quickshell.StateTranscribing)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/delivering", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: delivering to agent")
		if qsController != nil {
			qsController.SetState(quickshell.StateDelivering)
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/not_understood", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: not understood (empty transcript)")
		if qsController != nil {
			qsController.SetMessage("Didn't catch that")
			qsController.SetState(quickshell.StateError)
			go func() {
				time.Sleep(3 * time.Second)
				qsController.SetState(quickshell.StateIdle)
			}()
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})

	mux.HandleFunc("POST /api/voice/idle", func(w http.ResponseWriter, r *http.Request) {
		log.Println("voice: idle")
		if qsController != nil {
			qsController.SetRecording(false)
			qsController.SetState(quickshell.StateIdle)
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
