package main

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
)

// state は読み手と HTTP の間で共有する最新の値。
type state struct {
	mu      sync.Mutex
	latest  *reading
	readAt  time.Time
	reopens int
}

func (s *state) record(r reading, at time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.latest = &r
	s.readAt = at
}

// reopened は止まったデバイスの値を出し続けないよう、最新の値を捨てる。
// 系列が消えるので、Grafana Cloud 側は absent() で途絶を検知できる。
func (s *state) reopened() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.latest = nil
	s.reopens++
}

func (s *state) render() string {
	s.mu.Lock()
	defer s.mu.Unlock()

	var b strings.Builder
	write := func(name, kind, help string, v float64) {
		fmt.Fprintf(&b, "# HELP %s %s\n# TYPE %s %s\n%s %s\n", name, help, name, kind, name, strconv.FormatFloat(v, 'g', -1, 64))
	}
	if s.latest != nil {
		write("ud_co2s_co2_ppm", "gauge", "CO2 concentration.", s.latest.co2)
		write("ud_co2s_humidity_percent", "gauge", "Relative humidity.", s.latest.humidity)
		write("ud_co2s_temperature_celsius", "gauge", "Temperature.", s.latest.temperature)
	}
	if !s.readAt.IsZero() {
		write("ud_co2s_last_reading_timestamp_seconds", "gauge", "Unix time of the latest reading.", float64(s.readAt.UnixNano())/1e9)
	}
	write("ud_co2s_device_reopens_total", "counter", "Times the device was reopened after readings stopped or the port failed.", float64(s.reopens))
	return b.String()
}
