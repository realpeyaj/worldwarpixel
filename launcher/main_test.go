package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
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

func TestPatchPckUpdateSkipsExeReplacement(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("pinned-engine-exe"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientPckName), []byte("old-pck-v1.0.0"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	patchPck := []byte("new-pck-v1.0.1")
	sums := fmt.Sprintf("%s  WorldWarPixel-Patch.pck\n", sha256Hex(patchPck))

	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases":
			_ = json.NewEncoder(w).Encode([]ghRelease{{
				TagName: "v1.0.1",
				Body:    "- Fast .pck balance patch",
				Assets: []ghAsset{
					{Name: "WorldWarPixel-Client.zip", BrowserDownloadURL: srv.URL + "/dl/full.zip"},
					{Name: "WorldWarPixel-Patch.pck", BrowserDownloadURL: srv.URL + "/dl/patch.pck"},
					{Name: "SHA256SUMS.txt", BrowserDownloadURL: srv.URL + "/dl/SHA256SUMS.txt"},
				},
			}})
		case "/dl/patch.pck":
			_, _ = w.Write(patchPck)
		case "/dl/SHA256SUMS.txt":
			_, _ = w.Write([]byte(sums))
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
		t.Fatalf("checkAndUpdate patch pck failed: %v", err)
	}
	gotExe, _ := os.ReadFile(filepath.Join(gameDir, clientExeName))
	if string(gotExe) != "pinned-engine-exe" {
		t.Fatalf("expected existing .exe to remain untouched, got %q", string(gotExe))
	}
	gotPck, _ := os.ReadFile(filepath.Join(gameDir, clientPckName))
	if string(gotPck) != "new-pck-v1.0.1" {
		t.Fatalf("expected patched .pck, got %q", string(gotPck))
	}
	if ver := readLocalVersion(filepath.Join(gameDir, versionFileName)); ver != "v1.0.1" {
		t.Fatalf("version.txt = %q, want v1.0.1", ver)
	}
}

func TestPatchZipUpdateReplacesPckOnly(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("pinned-engine-exe"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientPckName), []byte("old-pck"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	patchZip := makeZipBytes(t, map[string]string{
		clientPckName:  "zip-patched-pck-v1.0.2",
		patchNotesName: "# Patch v1.0.2\n- Updated balance.",
	})
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases":
			_ = json.NewEncoder(w).Encode([]ghRelease{{
				TagName: "v1.0.2",
				Assets: []ghAsset{
					{Name: "WorldWarPixel-Patch.zip", BrowserDownloadURL: srv.URL + "/dl/patch.zip"},
				},
			}})
		case "/dl/patch.zip":
			_, _ = w.Write(patchZip)
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
		t.Fatalf("checkAndUpdate patch zip failed: %v", err)
	}
	gotPck, _ := os.ReadFile(filepath.Join(gameDir, clientPckName))
	if string(gotPck) != "zip-patched-pck-v1.0.2" {
		t.Fatalf("expected zip-patched .pck, got %q", string(gotPck))
	}
	if !fileExists(filepath.Join(gameDir, patchNotesName)) {
		t.Fatal("expected PATCH_NOTES.md to be extracted from WorldWarPixel-Patch.zip")
	}
}

func TestDeltaPckInstallIntoPatchesDir(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientExeName), []byte("pinned-engine-exe"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, clientPckName), []byte("base-pck"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(gameDir, versionFileName), []byte("v1.0.0\n"), 0644); err != nil {
		t.Fatal(err)
	}

	deltaName := "WorldWarPixel-Delta-v1.0.3.pck"
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/owner/repo/releases":
			_ = json.NewEncoder(w).Encode([]ghRelease{{
				TagName: "v1.0.3",
				Assets: []ghAsset{
					{Name: deltaName, BrowserDownloadURL: srv.URL + "/dl/" + deltaName},
				},
			}})
		case "/dl/" + deltaName:
			_, _ = w.Write([]byte("tiny-delta-pck"))
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
		t.Fatalf("checkAndUpdate delta failed: %v", err)
	}
	gotBase, _ := os.ReadFile(filepath.Join(gameDir, clientPckName))
	if string(gotBase) != "base-pck" {
		t.Fatalf("base .pck should stay intact on delta patch")
	}
	gotDelta, _ := os.ReadFile(filepath.Join(gameDir, patchesDirName, deltaName))
	if string(gotDelta) != "tiny-delta-pck" {
		t.Fatalf("expected delta file in patches/, got %q", string(gotDelta))
	}
}

func TestFormatPatchNotesAndLocalFallback(t *testing.T) {
	tempDir := t.TempDir()
	gameDir := filepath.Join(tempDir, gameDirName)
	_ = os.MkdirAll(gameDir, 0755)
	_ = os.WriteFile(filepath.Join(gameDir, patchNotesName), []byte("# Local Notes\n- Cached offline changelog."), 0644)

	offline := formatPatchNotes(nil, gameDir, tempDir)
	if !bytes.Contains([]byte(offline), []byte("Cached offline changelog")) {
		t.Fatalf("expected local PATCH_NOTES.md fallback, got %q", offline)
	}

	online := formatPatchNotes([]ghRelease{
		{TagName: "v1.0.2", Name: "Hotfix", PublishedAt: "2026-11-26T10:00:00Z", Body: "- Fixed radar icon"},
	}, gameDir, tempDir)
	if !bytes.Contains([]byte(online), []byte("v1.0.2")) || !bytes.Contains([]byte(online), []byte("Fixed radar icon")) {
		t.Fatalf("expected formatted GitHub release notes, got %q", online)
	}
}

func TestLoadLocalGodotProfile(t *testing.T) {
	dir := t.TempDir()
	cfg := "[profile]\nplayer_name=\"GuestCmd\"\n[account]\nusername=\"AdmiralPeyaj\"\ntoken=\"tok123\"\n"
	if err := os.WriteFile(filepath.Join(dir, "player_profile.cfg"), []byte(cfg), 0644); err != nil {
		t.Fatal(err)
	}
	// 128x64 2-frame PFP strip -> cropped cleanly to 64x64 frame 0
	strip := image.NewNRGBA(image.Rect(0, 0, 128, 64))
	var buf bytes.Buffer
	if err := png.Encode(&buf, strip); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "custom_avatar.png"), buf.Bytes(), 0644); err != nil {
		t.Fatal(err)
	}

	prof := loadLocalGodotProfile(dir)
	if prof.Username != "AdmiralPeyaj" || !prof.IsAccount {
		t.Fatalf("expected logged-in account AdmiralPeyaj, got %+v", prof)
	}
	if prof.Avatar == nil || prof.Avatar.Bounds().Dx() != 64 || prof.Avatar.Bounds().Dy() != 64 {
		t.Fatalf("expected 64x64 frame-0 avatar crop, got %v", prof.Avatar)
	}
}

func TestRiotHubRenderAndHitTesting(t *testing.T) {
	buf := make([]byte, hubWidth*hubHeight*4)
	states := []hubRenderState{
		{
			Phase:        hubReadyToPlay,
			LocalVersion: "v1.0.0",
			LatestTag:    "v1.0.0",
			HasExe:       true,
			StatusText:   "Up to date · Installed v1.0.0",
			ProgText:     "",
			ProgPct:      100,
			NotesRaw:     "# World War Pixel — Patch Notes\n## v1.0.0 — Global Expansion, Accounts & Custom PFPs\n- **Launcher Hub**: Editorial patch notes & account sync.\n- **Animated GIF PFP**: Upload custom avatars.",
			PingMs:       28,
			Profile:      localProfile{Username: "Commander", IsAccount: false},
			GameDir:      `C:\Games\WorldWarPixel\game`,
			Repo:         defaultRepo,
			InputUser:    "Admiral",
			FocusField:   "auth_user",
			CaretVisible: true,
			AuthMessage:  "Unable to reach game servers. Check your connection.",
			AuthIsError:  true,
		},
		{
			Phase:        hubNeedsPatch,
			LocalVersion: "v1.0.0",
			LatestTag:    "v1.0.1",
			HasExe:       true,
			StatusText:   "Installed v1.0.0 · Patch v1.0.1 available",
			ProgText:     "Patch v1.0.1 available",
			NotesRaw:     "# World War Pixel — Patch Notes\n## v1.0.1 — Balance Update\n- **Naval Trade**: Adjusted sea lane payouts.",
			PingMs:       -1,
			Profile:      localProfile{Username: "AdmiralPeyaj", IsAccount: true, Token: "tok"},
			GameDir:      `C:\Games\WorldWarPixel\game`,
			Repo:         defaultRepo,
			Friends:      []apiUserProfile{{Username: "AllyOne", Online: true, LastSeenText: "Online"}},
			Incoming:     []apiUserProfile{{Username: "Recruit", Online: false, LastSeenText: "2h ago"}},
			SearchResults: []apiUserProfile{{Username: "Scout99", Relation: "none"}},
		},
	}

	forbidden := []string{"151.242", "30041", "Ready to play", "READY TO PLAY", "Patch-Ready", "PATCH ENGINE"}

	for si, baseState := range states {
		for _, tab := range []hubTab{tabGame, tabNotes, tabAccount, tabSettings} {
			baseState.Tab = tab
			hits, texts, _ := renderHubFrame(buf, hubWidth*4, false, baseState)
			if len(texts) < 4 {
				t.Fatalf("state %d tab %d emitted too few text ops: %d", si, tab, len(texts))
			}
			for _, op := range texts {
				for _, bad := range forbidden {
					if strings.Contains(op.text, bad) {
						t.Fatalf("forbidden string %q leaked in state %d tab %d text %q", bad, si, tab, op.text)
					}
				}
			}
			seen := map[string]bool{}
			for _, h := range hits {
				seen[h.id] = true
			}
			for _, req := range []string{"tab_game", "tab_notes", "tab_account", "tab_settings", "open_account", "minimize", "close"} {
				if !seen[req] {
					t.Fatalf("state %d tab %d missing hit region %q", si, tab, req)
				}
			}
			if tab == tabGame && !seen["primary"] {
				t.Fatalf("game tab missing primary PLAY CTA hit region")
			}
			if tab == tabAccount && !baseState.Profile.IsAccount && !seen["auth_submit"] {
				t.Fatalf("signed-out account tab missing auth_submit hit region")
			}
			if tab == tabAccount && baseState.Profile.IsAccount && !seen["upload_avatar"] {
				t.Fatalf("signed-in account tab missing upload_avatar hit region")
			}
		}
	}
}

func TestAccountAPILoginRegisterAvatarAndProfileSync(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/auth/register":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"token": "tok_reg_123",
				"user": map[string]any{
					"username":        "CommanderAce",
					"online":          true,
					"avatar_frames":   1,
					"avatar_delay_ms": 100,
				},
			})
		case r.Method == http.MethodPost && r.URL.Path == "/api/auth/login":
			w.WriteHeader(http.StatusUnauthorized)
			_ = json.NewEncoder(w).Encode(map[string]any{"error": "invalid username or password"})
		case r.Method == http.MethodGet && r.URL.Path == "/api/friends":
			if r.Header.Get("Authorization") != "Bearer tok_reg_123" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			_ = json.NewEncoder(w).Encode(apiFriendsOverview{
				Friends: []apiUserProfile{{Username: "AllyPrime", Online: true, LastSeenText: "Online"}},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	client := newAccountAPIClient(srv.URL, srv.Client())
	tok, user, err := client.Register(context.Background(), "CommanderAce", "secret")
	if err != nil || tok != "tok_reg_123" || user.Username != "CommanderAce" {
		t.Fatalf("register failed: tok=%q user=%+v err=%v", tok, user, err)
	}

	_, _, badLoginErr := client.Login(context.Background(), "CommanderAce", "wrong")
	if got := sanitizeUserError(badLoginErr); got != "invalid username or password" {
		t.Fatalf("expected server message verbatim, got %q", got)
	}

	ov, err := client.FriendsOverview(context.Background(), tok)
	if err != nil || len(ov.Friends) != 1 || ov.Friends[0].Username != "AllyPrime" {
		t.Fatalf("friends overview mismatch: ov=%+v err=%v", ov, err)
	}

	// Verify profile INI persistence preserves existing unrelated sections/keys.
	userDir := t.TempDir()
	existing := "[audio]\nmaster_volume=0.8\n[profile]\nplayer_name=\"OldGuest\"\n"
	if err := os.WriteFile(filepath.Join(userDir, "player_profile.cfg"), []byte(existing), 0644); err != nil {
		t.Fatal(err)
	}
	strip := image.NewNRGBA(image.Rect(0, 0, 64, 64))
	var pngBuf bytes.Buffer
	_ = png.Encode(&pngBuf, strip)

	prof := localProfile{
		Username:      user.Username,
		Token:         tok,
		IsAccount:     true,
		AvatarHash:    "abc12345",
		AvatarFrames:  2,
		AvatarDelayMs: 90,
	}
	if err := saveLocalGodotProfile(userDir, &prof, pngBuf.Bytes()); err != nil {
		t.Fatalf("saveLocalGodotProfile failed: %v", err)
	}

	cfgSaved, _ := os.ReadFile(filepath.Join(userDir, "player_profile.cfg"))
	if !strings.Contains(string(cfgSaved), "master_volume=0.8") {
		t.Fatalf("saveLocalGodotProfile dropped existing [audio] section: %s", string(cfgSaved))
	}
	reloaded := loadLocalGodotProfile(userDir)
	if !reloaded.IsAccount || reloaded.Username != "CommanderAce" || reloaded.Token != "tok_reg_123" || reloaded.AvatarFrames != 2 {
		t.Fatalf("reloaded profile mismatch: %+v", reloaded)
	}

	// Verify transport errors never leak backend IP/port/URL.
	deadClient := newAccountAPIClient("http://151.242.136.36:30041", &http.Client{Timeout: 50 * time.Millisecond})
	_, _, deadErr := deadClient.Login(context.Background(), "a", "b")
	msg := sanitizeUserError(deadErr)
	if strings.Contains(msg, "151.242") || strings.Contains(msg, "30041") || strings.Contains(msg, "http") {
		t.Fatalf("sanitized error leaked backend origin: %q", msg)
	}
}

func TestParsePatchReleasesStructured(t *testing.T) {
	raw := `# World War Pixel — Patch Notes

## v1.1.0 — Tactical Client Update (2026-11-26)
- **Launcher Accounts**: Sign in, upload Photo/GIF avatars, and manage friends directly in the hub.
- **Foreground Game Launch**: Clicking Play brings the game window directly to the front.

## v1.0.0 — Global Expansion
- **1:1 World Grid**: Doubled territory resolution.
`
	rels := parsePatchReleases(raw)
	if len(rels) != 2 {
		t.Fatalf("expected 2 releases, got %d (%+v)", len(rels), rels)
	}
	if rels[0].Version != "v1.1.0" || rels[0].Date != "2026-11-26" || len(rels[0].Items) != 2 {
		t.Fatalf("unexpected release 0: %+v", rels[0])
	}
	if rels[0].Items[0].Title != "Launcher Accounts" {
		t.Fatalf("unexpected item title: %+v", rels[0].Items[0])
	}
}
