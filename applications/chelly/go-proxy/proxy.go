package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
)

type kind int

const (
	kindList kind = iota
	kindLatest
	kindInfo
	kindMod
	kindZip
)

type request struct {
	mod     string
	kind    kind
	version string
}

type download struct {
	Info  string
	GoMod string
	Zip   string
}

type fetcher interface {
	Download(ctx context.Context, mod, query string) (*download, error)
	Versions(ctx context.Context, mod string) ([]string, error)
}

// notFoundError は module や version が取得できないことを表す。GOPROXY の protocol では
// 404 を返すと go が次の候補 (親の module path や次の proxy) を試す。
type notFoundError struct{ msg string }

func (e *notFoundError) Error() string { return e.msg }

type server struct {
	allow []string
	fetch fetcher
}

// allowed は GOPRIVATE と同じ規則で判定する。pattern と同じ要素数だけ取った module path の
// 先頭が path.Match で一致すれば、その下の module も許可する。
func allowed(patterns []string, mod string) bool {
	elems := strings.Split(mod, "/")
	for _, pattern := range patterns {
		pattern = strings.Trim(pattern, "/")
		n := strings.Count(pattern, "/") + 1
		if pattern == "" || len(elems) < n {
			continue
		}
		if ok, _ := path.Match(pattern, strings.Join(elems[:n], "/")); ok {
			return true
		}
	}
	return false
}

func parseRequest(p string) (request, error) {
	rest, ok := strings.CutPrefix(p, "/")
	if !ok {
		return request{}, errors.New("path must be absolute")
	}
	if escaped, ok := strings.CutSuffix(rest, "/@latest"); ok {
		mod, err := unescapeModule(escaped)
		return request{mod: mod, kind: kindLatest}, err
	}
	escaped, file, ok := strings.Cut(rest, "/@v/")
	if !ok || strings.Contains(file, "/") {
		return request{}, errors.New("not a module proxy path")
	}
	mod, err := unescapeModule(escaped)
	if err != nil {
		return request{}, err
	}
	if file == "list" {
		return request{mod: mod, kind: kindList}, nil
	}
	ext := filepath.Ext(file)
	k, ok := map[string]kind{".info": kindInfo, ".mod": kindMod, ".zip": kindZip}[ext]
	if !ok {
		return request{}, fmt.Errorf("unknown file %q", file)
	}
	version, err := unescapeVersion(strings.TrimSuffix(file, ext))
	return request{mod: mod, kind: k, version: version}, err
}

// unescape は module proxy の大文字の escape ("!x" → "X") を戻す。escape されていない
// 大文字は不正な path として扱う。
func unescape(s string) (string, error) {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '!':
			if i+1 >= len(s) || s[i+1] < 'a' || s[i+1] > 'z' {
				return "", fmt.Errorf("invalid escape in %q", s)
			}
			i++
			b.WriteByte(s[i] - 'a' + 'A')
		case 'A' <= c && c <= 'Z':
			return "", fmt.Errorf("unescaped upper case in %q", s)
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), nil
}

// go の引数に渡すので、option と誤読される先頭の '-' や、module path の外を指す要素を拒否する。
func unescapeModule(s string) (string, error) {
	mod, err := unescape(s)
	if err != nil {
		return "", err
	}
	if mod == "" || strings.HasPrefix(mod, "-") {
		return "", fmt.Errorf("invalid module path %q", mod)
	}
	for _, elem := range strings.Split(mod, "/") {
		if elem == "" || elem == "." || elem == ".." {
			return "", fmt.Errorf("invalid module path %q", mod)
		}
	}
	for _, c := range mod {
		if !isAlnum(c) && !strings.ContainsRune("-._~/", c) {
			return "", fmt.Errorf("invalid module path %q", mod)
		}
	}
	return mod, nil
}

func unescapeVersion(s string) (string, error) {
	version, err := unescape(s)
	if err != nil {
		return "", err
	}
	if version == "" || strings.HasPrefix(version, "-") {
		return "", fmt.Errorf("invalid version %q", version)
	}
	for _, c := range version {
		if !isAlnum(c) && !strings.ContainsRune("-._+", c) {
			return "", fmt.Errorf("invalid version %q", version)
		}
	}
	return version, nil
}

func isAlnum(c rune) bool {
	return 'a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9'
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	req, err := parseRequest(r.URL.Path)
	if err != nil {
		http.Error(w, "chelly-go-proxy: "+err.Error(), http.StatusNotFound)
		return
	}
	if !allowed(s.allow, req.mod) {
		http.Error(w, "chelly-go-proxy: "+req.mod+" is not in the allowed module list", http.StatusNotFound)
		return
	}
	if req.kind == kindList {
		versions, err := s.fetch.Versions(r.Context(), req.mod)
		if err != nil {
			writeError(w, err)
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, v := range versions {
			fmt.Fprintln(w, v)
		}
		return
	}
	query := req.version
	if req.kind == kindLatest {
		query = "latest"
	}
	d, err := s.fetch.Download(r.Context(), req.mod, query)
	if err != nil {
		writeError(w, err)
		return
	}
	file, contentType := d.Info, "application/json"
	switch req.kind {
	case kindMod:
		file, contentType = d.GoMod, "text/plain; charset=utf-8"
	case kindZip:
		file, contentType = d.Zip, "application/zip"
	}
	f, err := os.Open(file)
	if err != nil {
		writeError(w, err)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", contentType)
	io.Copy(w, f)
}

func writeError(w http.ResponseWriter, err error) {
	var nf *notFoundError
	if errors.As(err, &nf) {
		http.Error(w, "chelly-go-proxy: "+err.Error(), http.StatusNotFound)
		return
	}
	http.Error(w, "chelly-go-proxy: "+err.Error(), http.StatusInternalServerError)
}

// goCommand は本人の Git 認証を使う go で、許可した module だけを VCS から直接取得する。
type goCommand struct {
	bin      string
	cacheDir string
	allow    []string
}

func (g *goCommand) run(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, g.bin, args...)
	// module 外で実行し、cacheDir 直下に go.mod が無いことで作業中の module に左右されない。
	cmd.Dir = g.cacheDir
	// 本人の GOPROXY・GOINSECURE・GOFLAGS などを持ち込むと取得経路が変わるので、GO で
	// 始まる変数は捨てて必要なものだけ決める。
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "GO") {
			cmd.Env = append(cmd.Env, kv)
		}
	}
	cmd.Env = append(cmd.Env,
		"GOENV=off",
		"GOFLAGS=-mod=mod",
		"GOMODCACHE="+filepath.Join(g.cacheDir, "mod"),
		"GOPRIVATE="+strings.Join(g.allow, ","),
		"GOPROXY=direct",
		"GOTOOLCHAIN=local",
		"GOWORK=off",
		"GIT_TERMINAL_PROMPT=0",
	)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return out, &notFoundError{msg: msg}
	}
	return out, err
}

func (g *goCommand) Download(ctx context.Context, mod, query string) (*download, error) {
	out, runErr := g.run(ctx, "mod", "download", "-json", mod+"@"+query)
	var result struct {
		download
		Error string
	}
	if err := json.Unmarshal(out, &result); err != nil {
		if runErr != nil {
			return nil, runErr
		}
		return nil, fmt.Errorf("parsing go mod download output: %w", err)
	}
	if result.Error != "" {
		return nil, &notFoundError{msg: result.Error}
	}
	if runErr != nil {
		return nil, runErr
	}
	return &result.download, nil
}

func (g *goCommand) Versions(ctx context.Context, mod string) ([]string, error) {
	out, err := g.run(ctx, "list", "-m", "-versions", "-json", mod)
	if err != nil {
		return nil, err
	}
	var result struct{ Versions []string }
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, fmt.Errorf("parsing go list output: %w", err)
	}
	return result.Versions, nil
}
