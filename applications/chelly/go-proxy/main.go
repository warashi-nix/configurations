// chelly-go-proxy は、専用 agent のコンテナに許可した Go module だけを渡す GOPROXY。
// 本人の Git 認証を持つ host で動き、許可しない module path では go も git も呼ばない。
// 本人の認証を扱うので、依存は標準ライブラリと本人が既に使う go・git だけに留める。
package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:3140", "address to listen on")
	allow := flag.String("allow", "", "comma-separated module path patterns, same syntax as GOPRIVATE")
	cacheDir := flag.String("cache-dir", "", "directory for the proxy's own module cache")
	goBin := flag.String("go", "go", "go command")
	flag.Parse()

	var patterns []string
	for _, p := range strings.Split(*allow, ",") {
		if p = strings.TrimSpace(p); p != "" {
			patterns = append(patterns, p)
		}
	}
	if len(patterns) == 0 || *cacheDir == "" {
		log.Fatal("chelly-go-proxy: -allow and -cache-dir are required")
	}
	bin, err := exec.LookPath(*goBin)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(*cacheDir, 0o700); err != nil {
		log.Fatal(err)
	}

	s := &server{
		allow: patterns,
		fetch: &goCommand{bin: bin, cacheDir: *cacheDir, allow: patterns},
	}
	log.Printf("chelly-go-proxy: listening on %s for %s", *listen, strings.Join(patterns, ","))
	log.Fatal(http.ListenAndServe(*listen, s))
}
