package main

import (
	"net"
	"os"
	"strconv"
	"time"
)

// notify は sd_notify(3) と同じく NOTIFY_SOCKET に状態を 1 データグラムで送る。
func notify(msg string) error {
	path := os.Getenv("NOTIFY_SOCKET")
	if path == "" {
		return nil
	}
	conn, err := net.DialUnix("unixgram", nil, &net.UnixAddr{Name: path, Net: "unixgram"})
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write([]byte(msg))
	return err
}

// watchdogInterval は systemd の WatchdogSec に対し、sd_watchdog_enabled(3) の勧めどおり半分の間隔を返す。
func watchdogInterval() (time.Duration, bool) {
	usec, err := strconv.ParseInt(os.Getenv("WATCHDOG_USEC"), 10, 64)
	if err != nil || usec <= 0 {
		return 0, false
	}
	return time.Duration(usec) * time.Microsecond / 2, true
}
