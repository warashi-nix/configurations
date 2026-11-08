package main

import (
	"context"
	"errors"
	"io"
	"log"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeDevice は UD-CO2S の代わりに、受け取ったコマンドを記録し、test が書いた行を返す。
type fakeDevice struct {
	r        *io.PipeReader
	w        *io.PipeWriter
	commands chan string
	closed   chan struct{}
	once     sync.Once
}

func newFakeDevice() *fakeDevice {
	r, w := io.Pipe()
	return &fakeDevice{r: r, w: w, commands: make(chan string, 16), closed: make(chan struct{})}
}

func (d *fakeDevice) Read(p []byte) (int, error) { return d.r.Read(p) }

func (d *fakeDevice) Write(p []byte) (int, error) {
	for _, c := range strings.Split(strings.TrimSuffix(string(p), "\r\n"), "\r\n") {
		d.commands <- c
	}
	return len(p), nil
}

func (d *fakeDevice) Close() error {
	d.once.Do(func() {
		d.r.Close()
		d.w.Close()
		close(d.closed)
	})
	return nil
}

func (d *fakeDevice) send(line string) { d.w.Write([]byte(line + "\r\n")) }

// answer は STP と STA に OK を返し、STA の後に lines を流す。
func (d *fakeDevice) answer(t *testing.T, lines ...string) {
	go func() {
		for c := range d.commands {
			switch c {
			case "STP":
				d.send("OK STP")
			case "STA":
				d.send("OK STA")
				for _, l := range lines {
					d.send(l)
				}
			default:
				t.Errorf("unexpected command %q", c)
			}
		}
	}()
}

func startReader(t *testing.T, r *reader) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		r.run(ctx)
		close(done)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

func eventually(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(time.Millisecond)
	}
}

func opener(devices ...*fakeDevice) (func() (io.ReadWriteCloser, error), *atomic.Int32) {
	var calls atomic.Int32
	return func() (io.ReadWriteCloser, error) {
		i := int(calls.Add(1)) - 1
		if i >= len(devices) {
			return nil, errors.New("no more devices")
		}
		return devices[i], nil
	}, &calls
}

func TestReaderStopsThenStartsTheDeviceAndRecordsReadings(t *testing.T) {
	dev := newFakeDevice()
	open, _ := opener(dev)
	var s state
	cmds := make(chan string, 16)
	go func() {
		for c := range dev.commands {
			cmds <- c
			switch c {
			case "STP":
				dev.send("CO2=999,HUM=1,TMP=1")
				dev.send("OK STP")
			case "STA":
				dev.send("OK STA")
				dev.send("CO2=812,HUM=45.2,TMP=23.1")
			}
		}
	}()
	startReader(t, &reader{open: open, state: &s, silence: time.Second, retry: time.Millisecond, ping: func() {}, pingEvery: time.Hour})

	eventually(t, "a reading", func() bool { return strings.Contains(s.render(), "ud_co2s_co2_ppm 812\n") })
	if got := []string{<-cmds, <-cmds}; got[0] != "STP" || got[1] != "STA" {
		t.Errorf("commands = %v, want [STP STA]", got)
	}
	if strings.Contains(s.render(), "ud_co2s_co2_ppm 999\n") {
		t.Errorf("recorded a reading sent before STA")
	}
}

func TestReaderReopensTheDeviceWhenReadingsStop(t *testing.T) {
	silent, alive := newFakeDevice(), newFakeDevice()
	silent.answer(t, "CO2=700,HUM=40,TMP=20")
	alive.answer(t, "CO2=812,HUM=45.2,TMP=23.1")
	open, calls := opener(silent, alive)
	var s state
	startReader(t, &reader{open: open, state: &s, silence: 50 * time.Millisecond, retry: time.Millisecond, ping: func() {}, pingEvery: time.Hour})

	eventually(t, "a reading from the reopened device", func() bool { return strings.Contains(s.render(), "ud_co2s_co2_ppm 812\n") })
	select {
	case <-silent.closed:
	default:
		t.Errorf("the silent device was not closed")
	}
	if got := calls.Load(); got != 2 {
		t.Errorf("opened %d times, want 2", got)
	}
	if !strings.Contains(s.render(), "ud_co2s_device_reopens_total 1\n") {
		t.Errorf("reopens were not counted:\n%s", s.render())
	}
}

func TestReaderRetriesWhenTheDeviceCannotBeOpened(t *testing.T) {
	dev := newFakeDevice()
	dev.answer(t, "CO2=812,HUM=45.2,TMP=23.1")
	var calls atomic.Int32
	open := func() (io.ReadWriteCloser, error) {
		if calls.Add(1) == 1 {
			return nil, errors.New("no such device")
		}
		return dev, nil
	}
	var s state
	startReader(t, &reader{open: open, state: &s, silence: time.Second, retry: time.Millisecond, ping: func() {}, pingEvery: time.Hour})

	eventually(t, "a reading after the failed open", func() bool { return strings.Contains(s.render(), "ud_co2s_co2_ppm 812\n") })
	if !strings.Contains(s.render(), "ud_co2s_device_reopens_total 1\n") {
		t.Errorf("the failed open was not counted:\n%s", s.render())
	}
}

func TestReaderPingsTheWatchdogWhileTheDeviceIsSilent(t *testing.T) {
	dev := newFakeDevice()
	dev.answer(t)
	open, _ := opener(dev)
	var s state
	var pings atomic.Int32
	startReader(t, &reader{open: open, state: &s, silence: time.Hour, retry: time.Millisecond, ping: func() { pings.Add(1) }, pingEvery: time.Millisecond})

	eventually(t, "watchdog pings", func() bool { return pings.Load() >= 3 })
}

type syncBuffer struct {
	mu sync.Mutex
	b  strings.Builder
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.String()
}

func TestReaderLogsCommandsAndLinesThatAreNotReadings(t *testing.T) {
	var logs syncBuffer
	log.SetOutput(&logs)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })

	dev := newFakeDevice()
	dev.answer(t, "HELLO", "CO2=812,HUM=45.2,TMP=23.1")
	open, _ := opener(dev)
	var s state
	startReader(t, &reader{open: open, state: &s, silence: time.Hour, retry: time.Millisecond, ping: func() {}, pingEvery: time.Hour})

	eventually(t, "a reading", func() bool { return strings.Contains(s.render(), "ud_co2s_co2_ppm 812\n") })
	for _, want := range []string{`sent STP`, `received "OK STP"`, `sent STA`, `received "OK STA"`, `received "HELLO"`} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("logs lack %q:\n%s", want, logs.String())
		}
	}
	if strings.Contains(logs.String(), "CO2=812") {
		t.Errorf("logged a reading, which would flood the journal every 2 seconds:\n%s", logs.String())
	}
}

func TestReaderClosesTheDeviceWhenStopped(t *testing.T) {
	dev := newFakeDevice()
	dev.answer(t, "CO2=812,HUM=45.2,TMP=23.1")
	open, _ := opener(dev)
	var s state
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		(&reader{open: open, state: &s, silence: time.Hour, retry: time.Millisecond, ping: func() {}, pingEvery: time.Hour}).run(ctx)
		close(done)
	}()
	eventually(t, "a reading", func() bool { return strings.Contains(s.render(), "ud_co2s_co2_ppm 812\n") })

	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("run did not return after the context was cancelled")
	}
	select {
	case <-dev.closed:
	default:
		t.Errorf("the device was left open")
	}
}
