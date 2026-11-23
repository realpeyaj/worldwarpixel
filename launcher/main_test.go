package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type recordingProgressUI struct {
	shown   bool
	closed  bool
	updates []string
}

func (r *recordingProgressUI) Show(status string) {
	r.shown = true
	r.updates = append(r.updates, status)
}

func (r *recordingProgressUI) SetStatus(status string) {
	r.updates = append(r.updates, status)
}

func (r *recordingProgressUI) Close() {
	r.closed = true
}

func makeZipBytes(t *testing.T, entries map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range entries {
		fw, err := zw.Create(name)
		if err != nil {
			t.Fatalf("create zip entry %s: %v", name, err)
		}
		if _, err := fw.Write([]byte(body)); err != nil {
			t.Fatalf("write zip entry %s: %v", name, err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}
	return buf.Bytes()
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func TestCompareSemver(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"v1.0.0", "1.0.0", 0},
		{"v1.0.1", "v1.0.0", 1},
		{"v1.10.0", "v1.2.0", 1},
		{"v1.2.0", "v1.10.0", -1},
		{"v2.0.0", "v1.9.9", 1},
		{"v1.0.0", "v1.0.0-rc1", 1},
		{"v1.0.0-rc2", "v1.0.0-rc1", 1},
	}
	for _, tc := range cases {
		if got := compareSemver(tc.a, tc.b); got != tc.want {
			t.Errorf("compareSemver(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
}

func TestSelectReleaseAssets(t *testing.T) {
	assets := []ghAsset{
		{Name: "WorldWarPixel-Windows-v1.0.1.zip", BrowserDownloadURL: "https://example/bundle.zip"},
		{Name: "WorldWarPixel-Client.zip", BrowserDownloadURL: "https://example/client.zip"},
		{Name: "SHA256SUMS.txt", BrowserDownloadURL: "https://example/sums.txt"},
	}
	payload, checksum := selectReleaseAssets(assets)
	if payload == nil || payload.Name != "WorldWarPixel-Client.zip" {
		t.Fatalf("expected WorldWarPixel-Client.zip, got %#v", payload)
	}
	if checksum == nil || checksum.Name != "SHA256SUMS.txt" {
		t.Fatalf("expected SHA256SUMS.txt, got %#v", checksum)
	}

	bundleOnly := []ghAsset{
		{Name: "source.tar.gz", BrowserDownloadURL: "https://example/src.tar.gz"},
		{Name: "WorldWarPixel-Windows-v1.0.2.zip", BrowserDownloadURL: "https://example/bundle2.zip"},
	}
	payload, checksum = selectReleaseAssets(bundleOnly)
	if payload == nil || payload.Name != "WorldWarPixel-Windows-v1.0.2.zip" {
		t.Fatalf("expected windows bundle zip fallback, got %#v", payload)
	}
	if checksum != nil {
		t.Fatalf("expected nil checksum, got %#v", checksum)
	}

	exeOnly := []ghAsset{
		{Name: "WorldWarPixel-Client.exe", BrowserDownloadURL: "https://example/client.exe"},
		{Name: "WorldWarPixel-Client.exe.sha256", BrowserDownloadURL: "https://example/client.exe.sha256"},
	}
	payload, checksum = selectReleaseAssets(exeOnly)
	if payload == nil || payload.Name != "WorldWarPixel-Client.exe" {
		t.Fatalf("expected bare client exe fallback, got %#v", payload)
	}
	if checksum == nil || checksum.Name != "WorldWarPixel-Client.exe.sha256" {
		t.Fatalf("expected .sha256 fallback, got %#v", checksum)
	}
}

func TestUpdateSuccessWithSHA256(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("old-binary"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	zipBytes := makeZipBytes(t, map[string]string{
		clientExeName: "new-client-v1.0.1",
	})
	sums := fmt.Sprintf("%s  WorldWarPixel-Client.zip\n", sha256Hex(zipBytes))

	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases/latest":
			_ = json.NewEncoder(w).Encode(ghRelease{
				TagName: "v1.0.1",
				Assets: []ghAsset{
					{Name: "WorldWarPixel-Client.zip", BrowserDownloadURL: srv.URL + "/dl/client.zip"},
					{Name: "SHA256SUMS.txt", BrowserDownloadURL: srv.URL + "/dl/SHA256SUMS.txt"},
				},
			})
		case "/dl/client.zip":
			_, _ = w.Write(zipBytes)
		case "/dl/SHA256SUMS.txt":
			_, _ = w.Write([]byte(sums))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	ui := &recordingProgressUI{}
	cfg := launcherConfig{
		ExeDir:          tempDir,
		GameDir:         gameDir,
		Repo:            "owner/repo",
		APIBase:         srv.URL,
		HTTPClient:      srv.Client(),
		CheckTimeout:    2 * time.Second,
		DownloadTimeout: 10 * time.Second,
	}

	if err := checkAndUpdate(context.Background(), cfg, ui); err != nil {
		t.Fatalf("checkAndUpdate failed: %v", err)
	}
	if !ui.shown {
		t.Fatal("expected progress UI to be shown during update")
	}
	gotBin, err := os.ReadFile(filepath.Join(gameDir, clientExeName))
	if err != nil {
		t.Fatal(err)
	}
	if string(gotBin) != "new-client-v1.0.1" {
		t.Fatalf("updated binary mismatch: got %q", string(gotBin))
	}
	if gotVer := readLocalVersion(filepath.Join(gameDir, versionFileName)); gotVer != "v1.0.1" {
		t.Fatalf("version.txt = %q, want v1.0.1", gotVer)
	}
}

func TestUpdateFullBundleZipExtractsGameOnly(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("old-binary"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	zipBytes := makeZipBytes(t, map[string]string{
		"WorldWarPixel.exe":                "new-launcher-must-skip",
		"game/" + clientExeName:            "bundle-client-v1.1.0",
		"game/" + versionFileName:          "v1.1.0\n",
	})

	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases/latest":
			_ = json.NewEncoder(w).Encode(ghRelease{
				TagName: "v1.1.0",
				Assets: []ghAsset{
					{Name: "WorldWarPixel-Windows-v1.1.0.zip", BrowserDownloadURL: srv.URL + "/dl/bundle.zip"},
				},
			})
		case "/dl/bundle.zip":
			_, _ = w.Write(zipBytes)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	cfg := launcherConfig{
		ExeDir:          tempDir,
		GameDir:         gameDir,
		Repo:            "owner/repo",
		APIBase:         srv.URL,
		HTTPClient:      srv.Client(),
		CheckTimeout:    2 * time.Second,
		DownloadTimeout: 10 * time.Second,
	}

	if err := checkAndUpdate(context.Background(), cfg, &recordingProgressUI{}); err != nil {
		t.Fatalf("checkAndUpdate failed: %v", err)
	}
	if fileExists(filepath.Join(gameDir, "WorldWarPixel.exe")) {
		t.Fatal("launcher binary from full bundle should not be extracted into game/")
	}
	gotBin, err := os.ReadFile(filepath.Join(gameDir, clientExeName))
	if err != nil {
		t.Fatal(err)
	}
	if string(gotBin) != "bundle-client-v1.1.0" {
		t.Fatalf("got client binary %q, want bundle-client-v1.1.0", string(gotBin))
	}
}

func TestUpdateRejectsBadSHA256AndPreservesExisting(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("trusted-old-exe"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	zipBytes := makeZipBytes(t, map[string]string{
		clientExeName: "tampered-exe",
	})
	badSums := "0000000000000000000000000000000000000000000000000000000000000000  WorldWarPixel-Client.zip\n"

	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases/latest":
			_ = json.NewEncoder(w).Encode(ghRelease{
				TagName: "v1.0.2",
				Assets: []ghAsset{
					{Name: "WorldWarPixel-Client.zip", BrowserDownloadURL: srv.URL + "/dl/client.zip"},
					{Name: "SHA256SUMS.txt", BrowserDownloadURL: srv.URL + "/dl/SHA256SUMS.txt"},
				},
			})
		case "/dl/client.zip":
			_, _ = w.Write(zipBytes)
		case "/dl/SHA256SUMS.txt":
			_, _ = w.Write([]byte(badSums))
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	cfg := launcherConfig{
		ExeDir:          tempDir,
		GameDir:         gameDir,
		Repo:            "owner/repo",
		APIBase:         srv.URL,
		HTTPClient:      srv.Client(),
		CheckTimeout:    2 * time.Second,
		DownloadTimeout: 10 * time.Second,
	}

	err := checkAndUpdate(context.Background(), cfg, &recordingProgressUI{})
	if err == nil {
		t.Fatal("expected sha256 verification error, got nil")
	}

	gotBin, readErr := os.ReadFile(filepath.Join(gameDir, clientExeName))
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(gotBin) != "trusted-old-exe" {
		t.Fatalf("existing binary modified on bad checksum: %q", string(gotBin))
	}
	if gotVer := readLocalVersion(filepath.Join(gameDir, versionFileName)); gotVer != "v1.0.0" {
		t.Fatalf("version.txt modified on bad checksum: %q", gotVer)
	}
}

func TestExtractRejectsZipSlip(t *testing.T) {
	tempDir := t.TempDir()
	zipPath := filepath.Join(tempDir, "evil.zip")
	zipBytes := makeZipBytes(t, map[string]string{
		"../evil.txt": "pwned",
		clientExeName: "valid",
	})
	if err := os.WriteFile(zipPath, zipBytes, 0644); err != nil {
		t.Fatal(err)
	}

	destDir := filepath.Join(tempDir, "dest")
	if err := extractClientZip(zipPath, destDir, maxPayloadBytes); err == nil {
		t.Fatal("expected zip slip path error, got nil")
	}
	if fileExists(filepath.Join(tempDir, "evil.txt")) {
		t.Fatal("zip slip file was written outside destDir")
	}
}

func TestOfflineAnd404FallbackToExistingClient(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("existing-exe"), 0755); err != nil {
		t.Fatal(err)
	}

	srv404 := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	}))
	ui404 := &recordingProgressUI{}
	cfg404 := launcherConfig{
		ExeDir:          tempDir,
		GameDir:         gameDir,
		Repo:            "owner/repo",
		APIBase:         srv404.URL,
		HTTPClient:      srv404.Client(),
		CheckTimeout:    2 * time.Second,
		DownloadTimeout: 10 * time.Second,
	}
	if err := checkAndUpdate(context.Background(), cfg404, ui404); err != nil {
		t.Fatalf("expected nil on 404 with existing client, got %v", err)
	}
	if ui404.shown {
		t.Fatal("progress UI must not appear on 404 fallback")
	}
	srv404.Close()

	// Closed server simulates offline/unreachable host.
	uiOffline := &recordingProgressUI{}
	if err := checkAndUpdate(context.Background(), cfg404, uiOffline); err != nil {
		t.Fatalf("expected nil when offline with existing client, got %v", err)
	}
	if uiOffline.shown {
		t.Fatal("progress UI must not appear when offline")
	}
}
