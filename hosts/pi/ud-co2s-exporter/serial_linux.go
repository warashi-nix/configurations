package main

import (
	"io"
	"os"
	"syscall"
	"unsafe"
)

// openSerial は UD-CO2S の 115200 8N1 で raw モードに設定する。O_NONBLOCK は、CLOCAL を立てる
// 前の open がキャリア検出を待って止まらないようにするため。
func openSerial(path string) (io.ReadWriteCloser, error) {
	f, err := os.OpenFile(path, os.O_RDWR|syscall.O_NOCTTY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	raw, err := f.SyscallConn()
	if err != nil {
		f.Close()
		return nil, err
	}
	var ioctlErr error
	err = raw.Control(func(fd uintptr) {
		var t syscall.Termios
		if ioctlErr = ioctl(fd, syscall.TCGETS, &t); ioctlErr != nil {
			return
		}
		t.Iflag &^= syscall.IGNBRK | syscall.BRKINT | syscall.PARMRK | syscall.ISTRIP |
			syscall.INLCR | syscall.IGNCR | syscall.ICRNL | syscall.IXON
		t.Oflag &^= syscall.OPOST
		t.Lflag &^= syscall.ECHO | syscall.ECHONL | syscall.ICANON | syscall.ISIG | syscall.IEXTEN
		t.Cflag &^= syscall.CSIZE | syscall.PARENB | syscall.CSTOPB | cbaud
		t.Cflag |= syscall.CS8 | syscall.CREAD | syscall.CLOCAL | syscall.B115200
		t.Ispeed = syscall.B115200
		t.Ospeed = syscall.B115200
		t.Cc[syscall.VMIN] = 1
		t.Cc[syscall.VTIME] = 0
		ioctlErr = ioctl(fd, syscall.TCSETS, &t)
	})
	if err == nil {
		err = ioctlErr
	}
	if err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

// syscall は CBAUD を持たず、golang.org/x/sys に依存しないため、amd64 と arm64 で共通の
// asm-generic の値を置く。
const cbaud = 0x100f

func ioctl(fd, req uintptr, t *syscall.Termios) error {
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(unsafe.Pointer(t))); errno != 0 {
		return errno
	}
	return nil
}
