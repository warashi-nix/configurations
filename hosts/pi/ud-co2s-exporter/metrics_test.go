package main

import (
	"strings"
	"testing"
	"time"
)

func TestMetricsOmitReadingsBeforeTheFirstReading(t *testing.T) {
	var s state
	got := s.render()

	want := "# HELP ud_co2s_device_reopens_total Times the device was reopened after readings stopped or the port failed.\n" +
		"# TYPE ud_co2s_device_reopens_total counter\n" +
		"ud_co2s_device_reopens_total 0\n"
	if got != want {
		t.Errorf("render() =\n%s\nwant\n%s", got, want)
	}
}

func TestMetricsExposeTheLatestReading(t *testing.T) {
	var s state
	s.record(reading{co2: 812, humidity: 45.2, temperature: -3.5}, time.Unix(1700000000, 500000000))
	got := s.render()

	for _, line := range []string{
		"ud_co2s_co2_ppm 812\n",
		"ud_co2s_humidity_percent 45.2\n",
		"ud_co2s_temperature_celsius -3.5\n",
		"ud_co2s_last_reading_timestamp_seconds 1.7000000005e+09\n",
		"# TYPE ud_co2s_co2_ppm gauge\n",
		"# TYPE ud_co2s_last_reading_timestamp_seconds gauge\n",
	} {
		if !strings.Contains(got, line) {
			t.Errorf("render() lacks %q:\n%s", line, got)
		}
	}
}

func TestMetricsDropStaleReadingsButKeepTheirTime(t *testing.T) {
	var s state
	s.record(reading{co2: 812, humidity: 45.2, temperature: 23.1}, time.Unix(1700000000, 0))
	s.reopened()
	got := s.render()

	if strings.Contains(got, "ud_co2s_co2_ppm ") {
		t.Errorf("render() still exposes CO2 after the device was reopened:\n%s", got)
	}
	for _, line := range []string{
		"ud_co2s_last_reading_timestamp_seconds 1.7e+09\n",
		"ud_co2s_device_reopens_total 1\n",
	} {
		if !strings.Contains(got, line) {
			t.Errorf("render() lacks %q:\n%s", line, got)
		}
	}
}
