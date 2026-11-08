package main

import (
	"net"
	"path/filepath"
	"testing"
	"time"
)

func TestNotifySendsTheStateToNotifySocket(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify")
	conn, err := net.ListenUnixgram("unixgram", &net.UnixAddr{Name: path, Net: "unixgram"})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	t.Setenv("NOTIFY_SOCKET", path)

	if err := notify("WATCHDOG=1"); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 64)
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	n, err := conn.Read(buf)
	if err != nil {
		t.Fatal(err)
	}
	if got := string(buf[:n]); got != "WATCHDOG=1" {
		t.Errorf("received %q, want %q", got, "WATCHDOG=1")
	}
}

func TestNotifyDoesNothingOutsideSystemd(t *testing.T) {
	t.Setenv("NOTIFY_SOCKET", "")
	if err := notify("WATCHDOG=1"); err != nil {
		t.Errorf("notify() = %v, want nil", err)
	}
}

func TestWatchdogIntervalIsHalfOfTheTimeout(t *testing.T) {
	t.Setenv("WATCHDOG_USEC", "120000000")
	if got, ok := watchdogInterval(); !ok || got != time.Minute {
		t.Errorf("watchdogInterval() = %v, %v, want 1m, true", got, ok)
	}

	t.Setenv("WATCHDOG_USEC", "")
	if _, ok := watchdogInterval(); ok {
		t.Errorf("watchdogInterval() reported a watchdog without WATCHDOG_USEC")
	}
}
