package main

import (
	"regexp"
	"strconv"
	"strings"
)

type reading struct {
	co2         float64
	humidity    float64
	temperature float64
}

var readingPattern = regexp.MustCompile(`^CO2=(\d+),HUM=(\d+(?:\.\d+)?),TMP=(-?\d+(?:\.\d+)?)$`)

// parseReading は UD-CO2S が STA の後に流す "CO2=<ppm>,HUM=<%>,TMP=<℃>" の行を読む。
func parseReading(line string) (reading, bool) {
	m := readingPattern.FindStringSubmatch(strings.TrimRight(line, "\r"))
	if m == nil {
		return reading{}, false
	}
	var v [3]float64
	for i := range v {
		f, err := strconv.ParseFloat(m[i+1], 64)
		if err != nil {
			return reading{}, false
		}
		v[i] = f
	}
	return reading{co2: v[0], humidity: v[1], temperature: v[2]}, true
}
