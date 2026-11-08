package main

import (
	"fmt"
	"os"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

// openPty は UD-CO2S の代わりに、端末として振る舞う pty の対を開く。
func openPty(t *testing.T) (master *os.File, slave string) {
	t.Helper()
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		t.Skipf("no pty: %v", err)
	}
	t.Cleanup(func() { m.Close() })
	var unlock, n int32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), syscall.TIOCSPTLCK, uintptr(unsafe.Pointer(&unlock))); e != 0 {
		t.Fatal(e)
	}
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), syscall.TIOCGPTN, uintptr(unsafe.Pointer(&n))); e != 0 {
		t.Fatal(e)
	}
	return m, fmt.Sprintf("/dev/pts/%d", n)
}

func TestOpenSerialPassesDeviceLinesThroughUnchanged(t *testing.T) {
	master, slave := openPty(t)
	port, err := openSerial(slave)
	if err != nil {
		t.Fatal(err)
	}
	defer port.Close()

	master.Write([]byte("CO2=812,HUM=45.2,TMP=23.1\r\n"))
	want := "CO2=812,HUM=45.2,TMP=23.1\r\n"
	got := make([]byte, 0, len(want))
	buf := make([]byte, 64)
	for len(got) < len(want) {
		n, err := port.Read(buf)
		if err != nil {
			t.Fatal(err)
		}
		got = append(got, buf[:n]...)
	}
	if string(got) != want {
		t.Errorf("read %q, want %q", got, want)
	}
}

func TestOpenSerialLetsCloseInterruptABlockedRead(t *testing.T) {
	_, slave := openPty(t)
	port, err := openSerial(slave)
	if err != nil {
		t.Fatal(err)
	}

	done := make(chan error, 1)
	go func() {
		_, err := port.Read(make([]byte, 64))
		done <- err
	}()
	time.Sleep(50 * time.Millisecond)
	port.Close()
	select {
	case err := <-done:
		if err == nil {
			t.Errorf("Read returned no error after Close")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Read stayed blocked after Close")
	}
}
