package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestAllowedMatchesPatternsAsModulePathPrefixes(t *testing.T) {
	patterns := []string{"github.com/example/allowed", "git.example.com/team/*"}
	cases := map[string]bool{
		"github.com/example/allowed":         true,
		"github.com/example/allowed/v2":      true,
		"github.com/example/allowed/sub/pkg": true,
		"github.com/example/allowedx":        false,
		"github.com/example/other":           false,
		"github.com/example":                 false,
		"git.example.com/team/anything":      true,
		"git.example.com/team/anything/sub":  true,
		"git.example.com/team":               false,
		"git.example.com/other/repo":         false,
	}
	for mod, want := range cases {
		if got := allowed(patterns, mod); got != want {
			t.Errorf("allowed(%q) = %v, want %v", mod, got, want)
		}
	}
}

func TestParseRequestUnescapesModuleAndVersion(t *testing.T) {
	cases := []struct {
		path string
		want request
	}{
		{"/github.com/!example/repo/@v/list", request{mod: "github.com/Example/repo", kind: kindList}},
		{"/github.com/example/repo/@latest", request{mod: "github.com/example/repo", kind: kindLatest}},
		{"/github.com/example/repo/@v/v1.2.3.info", request{mod: "github.com/example/repo", kind: kindInfo, version: "v1.2.3"}},
		{"/github.com/example/repo/@v/v1.2.3-!r!c1.mod", request{mod: "github.com/example/repo", kind: kindMod, version: "v1.2.3-RC1"}},
		{"/github.com/example/repo/v2/@v/v2.0.0+incompatible.zip", request{mod: "github.com/example/repo/v2", kind: kindZip, version: "v2.0.0+incompatible"}},
		{"/github.com/example/repo/@v/main.info", request{mod: "github.com/example/repo", kind: kindInfo, version: "main"}},
	}
	for _, c := range cases {
		got, err := parseRequest(c.path)
		if err != nil {
			t.Errorf("parseRequest(%q) error: %v", c.path, err)
			continue
		}
		if got != c.want {
			t.Errorf("parseRequest(%q) = %+v, want %+v", c.path, got, c.want)
		}
	}
}

func TestParseRequestRejectsMalformedPaths(t *testing.T) {
	for _, path := range []string{
		"/",
		"/github.com/example/repo",
		"/github.com/example/repo/@v/",
		"/github.com/example/repo/@v/v1.0.0",
		"/github.com/example/repo/@v/v1.0.0.txt",
		"/github.com/Example/repo/@v/list",
		"/github.com/example/../repo/@v/list",
		"/github.com//repo/@v/list",
		"/-github.com/example/repo/@v/list",
		"/github.com/example/repo/@v/-v1.0.0.info",
		"/github.com/example/repo/@v/v1.0.0!.info",
		"/github.com/example/repo/@v/v1 0.info",
		"/github.com/example/repo/@v/list/extra",
	} {
		if got, err := parseRequest(path); err == nil {
			t.Errorf("parseRequest(%q) = %+v, want error", path, got)
		}
	}
}

type fakeFetcher struct {
	calls    []string
	dir      string
	versions []string
	err      error
}

func (f *fakeFetcher) Download(_ context.Context, mod, query string) (*download, error) {
	f.calls = append(f.calls, "download "+mod+"@"+query)
	if f.err != nil {
		return nil, f.err
	}
	write := func(name, content string) string {
		p := filepath.Join(f.dir, name)
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			panic(err)
		}
		return p
	}
	return &download{
		Info:  write("info", `{"Version":"v1.2.3"}`),
		GoMod: write("mod", "module "+mod+"\n"),
		Zip:   write("zip", "zip-bytes"),
	}, nil
}

func (f *fakeFetcher) Versions(_ context.Context, mod string) ([]string, error) {
	f.calls = append(f.calls, "versions "+mod)
	if f.err != nil {
		return nil, f.err
	}
	return f.versions, nil
}

func serve(t *testing.T, fetch *fakeFetcher, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	s := &server{allow: []string{"github.com/example/allowed"}, fetch: fetch}
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func TestServerServesAllowedModuleFiles(t *testing.T) {
	cases := map[string]string{
		"/github.com/example/allowed/@v/v1.2.3.info": `{"Version":"v1.2.3"}`,
		"/github.com/example/allowed/@latest":        `{"Version":"v1.2.3"}`,
		"/github.com/example/allowed/@v/v1.2.3.mod":  "module github.com/example/allowed\n",
		"/github.com/example/allowed/@v/v1.2.3.zip":  "zip-bytes",
	}
	for path, want := range cases {
		fetch := &fakeFetcher{dir: t.TempDir()}
		rec := serve(t, fetch, http.MethodGet, path)
		if rec.Code != http.StatusOK || rec.Body.String() != want {
			t.Errorf("GET %s = %d %q, want 200 %q", path, rec.Code, rec.Body.String(), want)
		}
	}
}

func TestServerListsAllowedModuleVersions(t *testing.T) {
	fetch := &fakeFetcher{versions: []string{"v1.0.0", "v1.1.0"}}
	rec := serve(t, fetch, http.MethodGet, "/github.com/example/allowed/v2/@v/list")
	if rec.Code != http.StatusOK || rec.Body.String() != "v1.0.0\nv1.1.0\n" {
		t.Errorf("list = %d %q", rec.Code, rec.Body.String())
	}
	if len(fetch.calls) != 1 || fetch.calls[0] != "versions github.com/example/allowed/v2" {
		t.Errorf("calls = %v", fetch.calls)
	}
}

func TestServerDoesNotFetchModulesOutsideTheAllowList(t *testing.T) {
	for _, path := range []string{
		"/github.com/example/other/@v/list",
		"/github.com/example/other/@latest",
		"/github.com/example/other/@v/v1.0.0.info",
		"/github.com/example/other/@v/v1.0.0.mod",
		"/github.com/example/other/@v/v1.0.0.zip",
		"/github.com/example/allowedx/@v/list",
	} {
		fetch := &fakeFetcher{dir: t.TempDir()}
		rec := serve(t, fetch, http.MethodGet, path)
		if rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", path, rec.Code)
		}
		if len(fetch.calls) != 0 {
			t.Errorf("GET %s fetched %v", path, fetch.calls)
		}
	}
}

func TestServerRejectsMalformedRequestsWithoutFetching(t *testing.T) {
	fetch := &fakeFetcher{dir: t.TempDir()}
	rec := serve(t, fetch, http.MethodGet, "/github.com/example/allowed/../other/@v/list")
	if rec.Code != http.StatusNotFound || len(fetch.calls) != 0 {
		t.Errorf("malformed = %d, calls %v", rec.Code, fetch.calls)
	}
	rec = serve(t, fetch, http.MethodPost, "/github.com/example/allowed/@v/list")
	if rec.Code != http.StatusMethodNotAllowed || len(fetch.calls) != 0 {
		t.Errorf("POST = %d, calls %v", rec.Code, fetch.calls)
	}
}

func TestServerReportsFetchFailuresAsNotFoundWithReason(t *testing.T) {
	fetch := &fakeFetcher{err: &notFoundError{msg: "unknown revision v9.9.9"}}
	rec := serve(t, fetch, http.MethodGet, "/github.com/example/allowed/@v/v9.9.9.info")
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "unknown revision v9.9.9") {
		t.Errorf("not found = %d %q", rec.Code, rec.Body.String())
	}
	fetch = &fakeFetcher{err: errors.New("exec: go: not found")}
	rec = serve(t, fetch, http.MethodGet, "/github.com/example/allowed/@v/v1.0.0.info")
	if rec.Code != http.StatusInternalServerError {
		t.Errorf("internal = %d %q", rec.Code, rec.Body.String())
	}
}

// fakeGo は引数と Go 関連の環境変数を記録し、指定の JSON を返す go の代わり。
func fakeGo(t *testing.T, stdout string, exit int) (bin, record string) {
	t.Helper()
	dir := t.TempDir()
	record = filepath.Join(dir, "record")
	out := filepath.Join(dir, "stdout")
	if err := os.WriteFile(out, []byte(stdout), 0o644); err != nil {
		t.Fatal(err)
	}
	bin = filepath.Join(dir, "go")
	script := "#!/bin/sh\n" +
		"{ echo \"pwd=$(pwd)\"; echo \"args=$*\"; env | grep -E '^(GO|GIT_TERMINAL_PROMPT=)' | sort; } > '" + record + "'\n" +
		"cat '" + out + "'\n" +
		"exit " + strconv.Itoa(exit) + "\n"
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return bin, record
}

func readRecord(t *testing.T, record string) string {
	t.Helper()
	b, err := os.ReadFile(record)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestGoCommandFetchesDirectlyWithOnlyAllowedModulesPrivate(t *testing.T) {
	bin, record := fakeGo(t, `{"Info":"/c/i","GoMod":"/c/m","Zip":"/c/z"}`, 0)
	t.Setenv("GOPROXY", "https://proxy.example.com")
	t.Setenv("GOFLAGS", "-insecure")
	cache := t.TempDir()
	g := &goCommand{bin: bin, cacheDir: cache, allow: []string{"github.com/example/a", "github.com/example/b"}}
	got, err := g.Download(context.Background(), "github.com/example/a", "v1.0.0")
	if err != nil {
		t.Fatal(err)
	}
	if *got != (download{Info: "/c/i", GoMod: "/c/m", Zip: "/c/z"}) {
		t.Errorf("download = %+v", got)
	}
	rec := readRecord(t, record)
	for _, want := range []string{
		"pwd=" + cache + "\n",
		"args=mod download -json github.com/example/a@v1.0.0\n",
		"GOPROXY=direct\n",
		"GOPRIVATE=github.com/example/a,github.com/example/b\n",
		"GOFLAGS=-mod=mod\n",
		"GOTOOLCHAIN=local\n",
		"GOENV=off\n",
		"GOWORK=off\n",
		"GOMODCACHE=" + filepath.Join(cache, "mod") + "\n",
		"GIT_TERMINAL_PROMPT=0\n",
	} {
		if !strings.Contains(rec, want) {
			t.Errorf("record missing %q:\n%s", want, rec)
		}
	}
	if strings.Contains(rec, "proxy.example.com") || strings.Contains(rec, "-insecure") {
		t.Errorf("inherited Go settings leaked:\n%s", rec)
	}
}

func TestGoCommandReportsModuleErrorsAsNotFound(t *testing.T) {
	bin, _ := fakeGo(t, `{"Error":"github.com/example/a@v9.9.9: invalid version: unknown revision v9.9.9"}`, 1)
	g := &goCommand{bin: bin, cacheDir: t.TempDir(), allow: []string{"github.com/example/a"}}
	_, err := g.Download(context.Background(), "github.com/example/a", "v9.9.9")
	var nf *notFoundError
	if !errors.As(err, &nf) || !strings.Contains(err.Error(), "unknown revision v9.9.9") {
		t.Errorf("err = %v", err)
	}
}

func TestGoCommandListsVersions(t *testing.T) {
	bin, record := fakeGo(t, `{"Path":"github.com/example/a","Versions":["v1.0.0","v1.1.0"]}`, 0)
	g := &goCommand{bin: bin, cacheDir: t.TempDir(), allow: []string{"github.com/example/a"}}
	got, err := g.Versions(context.Background(), "github.com/example/a")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(got, ",") != "v1.0.0,v1.1.0" {
		t.Errorf("versions = %v", got)
	}
	if rec := readRecord(t, record); !strings.Contains(rec, "args=list -m -versions -json github.com/example/a\n") {
		t.Errorf("record:\n%s", rec)
	}
}

func TestGoCommandReportsListFailuresAsNotFound(t *testing.T) {
	bin, _ := fakeGo(t, "", 1)
	g := &goCommand{bin: bin, cacheDir: t.TempDir(), allow: []string{"github.com/example/a"}}
	_, err := g.Versions(context.Background(), "github.com/example/a")
	var nf *notFoundError
	if !errors.As(err, &nf) {
		t.Errorf("err = %v", err)
	}
}
