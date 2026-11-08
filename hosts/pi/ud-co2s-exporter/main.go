package main

import (
	"context"
	"flag"
	"io"
	"log"
	"net"
	"net/http"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	device := flag.String("device", "/dev/ttyACM0", "UD-CO2S serial device")
	listen := flag.String("listen", "127.0.0.1:9126", "address to serve /metrics on")
	silence := flag.Duration("silence", time.Minute, "reopen the device when no reading arrives for this long")
	retry := flag.Duration("retry", 5*time.Second, "wait before reopening after the device failed to open")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var s state
	mux := http.NewServeMux()
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		io.WriteString(w, s.render())
	})
	ln, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		if err := server.Serve(ln); err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()

	ping, pingEvery := func() {}, time.Minute
	if every, ok := watchdogInterval(); ok {
		pingEvery = every
		ping = func() {
			if err := notify("WATCHDOG=1"); err != nil {
				log.Printf("notify watchdog: %v", err)
			}
		}
	}
	if err := notify("READY=1"); err != nil {
		log.Printf("notify ready: %v", err)
	}

	r := &reader{
		open:      func() (io.ReadWriteCloser, error) { return openSerial(*device) },
		state:     &s,
		silence:   *silence,
		retry:     *retry,
		ping:      ping,
		pingEvery: pingEvery,
	}
	r.run(ctx)

	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	server.Shutdown(shutdown)
}
