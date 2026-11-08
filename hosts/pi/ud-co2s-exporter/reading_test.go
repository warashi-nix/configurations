package main

import "testing"

func TestParseReadingAcceptsDeviceLine(t *testing.T) {
	cases := map[string]reading{
		"CO2=812,HUM=45.2,TMP=23.1":  {co2: 812, humidity: 45.2, temperature: 23.1},
		"CO2=400,HUM=0,TMP=-3.5\r":   {co2: 400, humidity: 0, temperature: -3.5},
		"CO2=10000,HUM=100.0,TMP=50": {co2: 10000, humidity: 100, temperature: 50},
	}
	for line, want := range cases {
		got, ok := parseReading(line)
		if !ok {
			t.Errorf("parseReading(%q) rejected the line", line)
			continue
		}
		if got != want {
			t.Errorf("parseReading(%q) = %+v, want %+v", line, got, want)
		}
	}
}

func TestParseReadingRejectsOtherLines(t *testing.T) {
	for _, line := range []string{
		"",
		"OK STA",
		"OK STP",
		"NG",
		"CO2=812,HUM=45.2",
		"CO2=abc,HUM=45.2,TMP=23.1",
		"CO2=812,HUM=45.2,TMP=23.1,X=1",
	} {
		if got, ok := parseReading(line); ok {
			t.Errorf("parseReading(%q) = %+v, want rejection", line, got)
		}
	}
}
