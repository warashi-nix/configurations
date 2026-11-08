package main

import (
	"bufio"
	"context"
	"io"
	"log"
	"strings"
	"time"
)

// reader はデバイスの異常をプロセスの中で直す。値が silence の間来なければ、ポートを閉じて
// 開き直し、STP → STA から始め直す。プロセス自体の異常(このループが止まること)は、
// ping が途絶えたのを systemd の watchdog が検知して再起動する。
type reader struct {
	open      func() (io.ReadWriteCloser, error)
	state     *state
	silence   time.Duration
	retry     time.Duration
	ping      func()
	pingEvery time.Duration
}

func (r *reader) run(ctx context.Context) {
	for first := true; ctx.Err() == nil; first = false {
		if !first {
			r.state.reopened()
		}
		r.session(ctx)
	}
}

func (r *reader) session(ctx context.Context) {
	port, err := r.open()
	if err != nil {
		log.Printf("open device: %v", err)
		r.wait(ctx, r.retry)
		return
	}
	done := make(chan struct{})
	defer close(done)
	defer port.Close()

	lines := make(chan string)
	go func() {
		defer close(lines)
		sc := bufio.NewScanner(port)
		for sc.Scan() {
			select {
			case lines <- strings.TrimRight(sc.Text(), "\r"):
			case <-done:
				return
			}
		}
	}()

	// 計測中に繋ぎ直すこともあるので、STP の応答までに流れてくる値は読み捨てる。
	if !r.command(port, "STP") {
		return
	}
	started := false

	silence := time.NewTimer(r.silence)
	defer silence.Stop()
	ping := time.NewTicker(r.pingEvery)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ping.C:
			r.ping()
		case <-silence.C:
			log.Printf("no reading for %s, reopening the device", r.silence)
			return
		case line, ok := <-lines:
			if !ok {
				log.Printf("device stopped sending")
				return
			}
			if !started {
				if strings.HasPrefix(line, "OK") || strings.HasPrefix(line, "NG") {
					if !r.command(port, "STA") {
						return
					}
					started = true
				}
				continue
			}
			if v, ok := parseReading(line); ok {
				r.state.record(v, time.Now())
				silence.Reset(r.silence)
			}
		}
	}
}

func (r *reader) command(port io.Writer, c string) bool {
	if _, err := io.WriteString(port, c+"\r\n"); err != nil {
		log.Printf("send %s: %v", c, err)
		return false
	}
	return true
}

func (r *reader) wait(ctx context.Context, d time.Duration) {
	end := time.NewTimer(d)
	defer end.Stop()
	ping := time.NewTicker(r.pingEvery)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-end.C:
			return
		case <-ping.C:
			r.ping()
		}
	}
}
