package web

import (
	"embed"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os/exec"

	"clawpi/internal/eww"
)

//go:embed landing-page
var landingFS embed.FS

// TTSStopFunc is called when the TTS stop endpoint is hit.
// Set by main to wire up the eww controller.
var ewwController *eww.Controller

func Serve(addr string, ctrl *eww.Controller) error {
	ewwController = ctrl

	sub, err := fs.Sub(landingFS, "landing-page")
	if err != nil {
		return err
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(sub)))

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

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	log.Printf("web server listening on %s", addr)
	return http.Serve(ln, mux)
}
