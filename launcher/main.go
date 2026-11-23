package main

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	defaultRepo      = "realpeyaj/worldwarpixel"
	defaultAPIBase   = "https://api.github.com"
	gameDirName      = "game"
	clientExeName    = "WorldWarPixel-Client.exe"
	versionFileName  = "version.txt"
	userAgent        = "WorldWarPixel-Launcher/1.0"
	checkTimeout     = 4 * time.Second
	downloadTimeout  = 10 * time.Minute
	maxPayloadBytes  = int64(512 << 20)
	maxChecksumsSize = int64(1 << 20)
)

type ghAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
}

type ghRelease struct {
	TagName string    `json:"tag_name"`
	Assets  []ghAsset `json:"assets"`
}

type progressUI interface {
	Show(status string)
	SetStatus(status string)
	Close()
}

type launcherConfig struct {
	ExeDir          string
	GameDir         string
	Repo            string
	APIBase         string
	HTTPClient      *http.Client
	CheckTimeout    time.Duration
	DownloadTimeout time.Duration
	SkipUpdate      bool
	WaitForChild    bool
	ForwardArgs     []string
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	release, ok := acquireSingleInstance()
	if !ok {
		return 0
	}
	defer release()

	exePath, err := os.Executable()
	if err != nil {
		showErrorBox("World War Pixel", fmt.Sprintf("Failed to resolve launcher path: %v", err))
		return 1
	}
	exeDir := filepath.Dir(exePath)

	skipUpdate, waitForChild, forwardArgs := parseArgs(args)
	if os.Getenv("WWP_SKIP_UPDATE") == "1" {
		skipUpdate = true
	}

	repo := strings.TrimSpace(os.Getenv("WWP_GITHUB_REPO"))
	if repo == "" {
		repo = defaultRepo
	}
	apiBase := strings.TrimSpace(os.Getenv("WWP_API_BASE"))
	if apiBase == "" {
		apiBase = defaultAPIBase
	}

	cfg := launcherConfig{
		ExeDir:          exeDir,
		GameDir:         filepath.Join(exeDir, gameDirName),
		Repo:            repo,
		APIBase:         apiBase,
		HTTPClient:      &http.Client{},
		CheckTimeout:    checkTimeout,
		DownloadTimeout: downloadTimeout,
		SkipUpdate:      skipUpdate,
		WaitForChild:    waitForChild,
		ForwardArgs:     forwardArgs,
	}

	clientExePath := filepath.Join(cfg.GameDir, clientExeName)
	ui := newProgressUI()
	defer ui.Close()

	if !cfg.SkipUpdate {
		if err := checkAndUpdate(context.Background(), cfg, ui); err != nil {
			ui.Close()
			if !fileExists(clientExePath) {
				showErrorBox("World War Pixel - Update Error", err.Error())
				return 1
			}
		}
		ui.Close()
	}

	if !fileExists(clientExePath) {
		showErrorBox(
			"World War Pixel",
			fmt.Sprintf("Game binary missing:\n%s\n\nRe-download the release archive or connect to the internet to fetch the latest build.", clientExePath),
		)
		return 1
	}

	cmd := exec.Command(clientExePath, cfg.ForwardArgs...)
	cmd.Dir = cfg.GameDir
	if cfg.WaitForChild {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				return exitErr.ExitCode()
			}
			showErrorBox("World War Pixel", fmt.Sprintf("Failed to run game client: %v", err))
			return 1
		}
		return 0
	}

	if err := cmd.Start(); err != nil {
		showErrorBox("World War Pixel", fmt.Sprintf("Failed to launch game client: %v", err))
		return 1
	}
	return 0
}

func parseArgs(args []string) (skipUpdate bool, waitForChild bool, forwardArgs []string) {
	for _, arg := range args {
		switch arg {
		case "--no-update":
			skipUpdate = true
		case "--wait":
			waitForChild = true
		default:
			forwardArgs = append(forwardArgs, arg)
		}
	}
	return skipUpdate, waitForChild, forwardArgs
}

type parsedSemver struct {
	parts [3]int
	pre   string
}

func parseSemver(raw string) parsedSemver {
	s := strings.TrimSpace(raw)
	s = strings.TrimPrefix(strings.TrimPrefix(s, "v"), "V")
	if idx := strings.IndexByte(s, '+'); idx >= 0 {
		s = s[:idx]
	}
	core := s
	pre := ""
	if idx := strings.IndexByte(s, '-'); idx >= 0 {
		core = s[:idx]
		pre = s[idx+1:]
	}
	var res parsedSemver
	res.pre = pre
	fields := strings.Split(core, ".")
	for i := 0; i < len(fields) && i < 3; i++ {
		n, err := strconv.Atoi(fields[i])
		if err == nil && n >= 0 {
			res.parts[i] = n
		}
	}
	return res
}

func comparePrerelease(a, b string) int {
	if a == b {
		return 0
	}
	if a == "" {
		return 1
	}
	if b == "" {
		return -1
	}
	ap := strings.Split(a, ".")
	bp := strings.Split(b, ".")
	maxLen := len(ap)
	if len(bp) > maxLen {
		maxLen = len(bp)
	}
	for i := 0; i < maxLen; i++ {
		if i >= len(ap) {
			return -1
		}
		if i >= len(bp) {
			return 1
		}
		ai, aErr := strconv.Atoi(ap[i])
		bi, bErr := strconv.Atoi(bp[i])
		switch {
		case aErr == nil && bErr == nil:
			if ai != bi {
				if ai < bi {
					return -1
				}
				return 1
			}
		case aErr == nil:
			return -1
		case bErr == nil:
			return 1
		default:
			if ap[i] != bp[i] {
				if ap[i] < bp[i] {
					return -1
				}
				return 1
			}
		}
	}
	return 0
}

// compareSemver returns 1 if a > b, -1 if a < b, and 0 if equal.
func compareSemver(a, b string) int {
	pa := parseSemver(a)
	pb := parseSemver(b)
	for i := 0; i < 3; i++ {
		if pa.parts[i] != pb.parts[i] {
			if pa.parts[i] < pb.parts[i] {
				return -1
			}
			return 1
		}
	}
	return comparePrerelease(pa.pre, pb.pre)
}

func selectReleaseAssets(assets []ghAsset) (*ghAsset, *ghAsset) {
	var payload *ghAsset

	for i := range assets {
		if strings.EqualFold(assets[i].Name, "WorldWarPixel-Client.zip") {
			c := assets[i]
			payload = &c
			break
		}
	}
	if payload == nil {
		for i := range assets {
			lower := strings.ToLower(assets[i].Name)
			if strings.HasSuffix(lower, ".zip") && strings.Contains(lower, "worldwarpixel") && strings.Contains(lower, "windows") {
				c := assets[i]
				payload = &c
				break
			}
		}
	}
	if payload == nil {
		for i := range assets {
			lower := strings.ToLower(assets[i].Name)
			if strings.HasSuffix(lower, ".zip") {
				c := assets[i]
				payload = &c
				break
			}
		}
	}
	if payload == nil {
		for i := range assets {
			if strings.EqualFold(assets[i].Name, clientExeName) {
				c := assets[i]
				payload = &c
				break
			}
		}
	}
	if payload == nil {
		return nil, nil
	}

	var checksum *ghAsset
	for i := range assets {
		if strings.EqualFold(assets[i].Name, "SHA256SUMS.txt") {
			c := assets[i]
			checksum = &c
			break
		}
	}
	if checksum == nil {
		target := strings.ToLower(payload.Name) + ".sha256"
		for i := range assets {
			if strings.ToLower(assets[i].Name) == target {
				c := assets[i]
				checksum = &c
				break
			}
		}
	}

	return payload, checksum
}

func verifySHA256(filePath, expectedName string, sumsBody []byte) error {
	expectedHash, ok := findChecksumInManifest(expectedName, sumsBody)
	if !ok {
		return fmt.Errorf("checksum entry for %s not found", expectedName)
	}

	f, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer f.Close()

	hasher := sha256.New()
	if _, err := io.Copy(hasher, f); err != nil {
		return err
	}
	actual := hex.EncodeToString(hasher.Sum(nil))
	if !strings.EqualFold(actual, expectedHash) {
		return fmt.Errorf("sha256 mismatch for %s: got %s, want %s", expectedName, actual, expectedHash)
	}
	return nil
}

func isHex64(s string) bool {
	if len(s) != 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}

func findChecksumInManifest(expectedName string, sumsBody []byte) (string, bool) {
	trimmed := bytes.TrimPrefix(sumsBody, []byte{0xEF, 0xBB, 0xBF})
	scanner := bufio.NewScanner(bytes.NewReader(trimmed))
	var singleBareHash string
	nonCommentLines := 0

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		nonCommentLines++
		fields := strings.Fields(line)
		if len(fields) == 1 && isHex64(fields[0]) {
			singleBareHash = strings.ToLower(fields[0])
			continue
		}
		if len(fields) >= 2 && isHex64(fields[0]) {
			fileToken := strings.TrimPrefix(fields[len(fields)-1], "*")
			if strings.EqualFold(fileToken, expectedName) || strings.EqualFold(path.Base(strings.ReplaceAll(fileToken, "\\", "/")), expectedName) {
				return strings.ToLower(fields[0]), true
			}
		}
	}

	if nonCommentLines == 1 && singleBareHash != "" {
		return singleBareHash, true
	}
	return "", false
}

func extractClientZip(zipPath, destDir string, maxBytes int64) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	absDest, err := filepath.Abs(destDir)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(absDest, 0755); err != nil {
		return err
	}

	hasGameFolder := false
	for _, f := range r.File {
		norm, err := sanitizeZipPath(f.Name)
		if err != nil {
			return err
		}
		if !f.FileInfo().IsDir() && strings.HasPrefix(strings.ToLower(norm), gameDirName+"/") {
			hasGameFolder = true
		}
	}

	var totalWritten int64
	for _, f := range r.File {
		norm, err := sanitizeZipPath(f.Name)
		if err != nil {
			return err
		}
		if f.FileInfo().IsDir() || norm == "" || norm == "." {
			continue
		}

		rel := norm
		if hasGameFolder {
			if len(norm) <= len(gameDirName)+1 || !strings.HasPrefix(strings.ToLower(norm), gameDirName+"/") {
				continue
			}
			rel = norm[len(gameDirName)+1:]
		}
		if rel == "" || rel == "." {
			continue
		}

		targetPath := filepath.Join(absDest, filepath.FromSlash(rel))
		relCheck, err := filepath.Rel(absDest, targetPath)
		if err != nil || relCheck == ".." || strings.HasPrefix(relCheck, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("invalid archive path %q", f.Name)
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			return err
		}

		rc, err := f.Open()
		if err != nil {
			return err
		}

		remaining := maxBytes - totalWritten
		if remaining <= 0 {
			rc.Close()
			return fmt.Errorf("extracted archive exceeds %d byte safety limit", maxBytes)
		}

		mode := os.FileMode(0644)
		if strings.HasSuffix(strings.ToLower(rel), ".exe") {
			mode = 0755
		}
		outFile, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
		if err != nil {
			rc.Close()
			return err
		}

		n, copyErr := io.Copy(outFile, io.LimitReader(rc, remaining+1))
		closeErr := outFile.Close()
		rc.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
		totalWritten += n
		if totalWritten > maxBytes {
			return fmt.Errorf("extracted archive exceeds %d byte safety limit", maxBytes)
		}
	}

	if !fileExists(filepath.Join(absDest, clientExeName)) {
		return fmt.Errorf("archive does not contain %s", clientExeName)
	}
	return nil
}

func sanitizeZipPath(raw string) (string, error) {
	if strings.HasPrefix(raw, "/") || strings.HasPrefix(raw, `\`) {
		return "", fmt.Errorf("absolute path in archive: %q", raw)
	}
	slashed := strings.ReplaceAll(raw, `\`, "/")
	if strings.Contains(slashed, ":") {
		return "", fmt.Errorf("drive path in archive: %q", raw)
	}
	cleaned := path.Clean(strings.TrimPrefix(slashed, "./"))
	if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", fmt.Errorf("path traversal in archive: %q", raw)
	}
	return cleaned, nil
}

func applyStagedUpdate(stageDir, gameDir, newVersion string) error {
	stagedExe := filepath.Join(stageDir, clientExeName)
	if !fileExists(stagedExe) {
		return fmt.Errorf("staged update missing %s", clientExeName)
	}
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		return err
	}

	destExe := filepath.Join(gameDir, clientExeName)
	backupExe := destExe + ".bak"
	_ = os.Remove(backupExe)

	hadExisting := false
	if fileExists(destExe) {
		if err := os.Rename(destExe, backupExe); err != nil {
			return fmt.Errorf("cannot replace running or locked game binary: %w", err)
		}
		hadExisting = true
	}

	restoreBackup := func() {
		if hadExisting {
			_ = os.Remove(destExe)
			_ = os.Rename(backupExe, destExe)
		}
	}

	if err := moveStageTree(stageDir, gameDir); err != nil {
		restoreBackup()
		return err
	}

	normVersion := strings.TrimSpace(newVersion)
	if normVersion != "" {
		versionPath := filepath.Join(gameDir, versionFileName)
		if err := os.WriteFile(versionPath, []byte(normVersion+"\n"), 0644); err != nil {
			restoreBackup()
			return err
		}
	}

	if hadExisting {
		_ = os.Remove(backupExe)
	}
	_ = os.RemoveAll(stageDir)
	return nil
}

func moveStageTree(srcDir, dstDir string) error {
	return filepath.WalkDir(srcDir, func(srcPath string, d os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(srcDir, srcPath)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		dstPath := filepath.Join(dstDir, rel)
		if d.IsDir() {
			return os.MkdirAll(dstPath, 0755)
		}
		if err := os.MkdirAll(filepath.Dir(dstPath), 0755); err != nil {
			return err
		}
		_ = os.Remove(dstPath)
		if err := os.Rename(srcPath, dstPath); err != nil {
			if copyErr := copyFile(srcPath, dstPath); copyErr != nil {
				return copyErr
			}
			_ = os.Remove(srcPath)
		}
		return nil
	})
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	mode := os.FileMode(0644)
	if strings.HasSuffix(strings.ToLower(dst), ".exe") {
		mode = 0755
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	closeErr := out.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func checkAndUpdate(ctx context.Context, cfg launcherConfig, ui progressUI) error {
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{}
	}
	if cfg.CheckTimeout <= 0 {
		cfg.CheckTimeout = checkTimeout
	}
	if cfg.DownloadTimeout <= 0 {
		cfg.DownloadTimeout = downloadTimeout
	}

	tmpDir := filepath.Join(cfg.GameDir, ".update-tmp")
	stageDir := filepath.Join(cfg.GameDir, ".update-stage")
	_ = os.RemoveAll(tmpDir)
	_ = os.RemoveAll(stageDir)
	defer os.RemoveAll(tmpDir)
	defer os.RemoveAll(stageDir)

	clientExePath := filepath.Join(cfg.GameDir, clientExeName)
	hasExistingClient := fileExists(clientExePath)
	localVersion := readLocalVersion(filepath.Join(cfg.GameDir, versionFileName))

	release, statusCode, err := fetchLatestRelease(ctx, client, cfg.APIBase, cfg.Repo, cfg.CheckTimeout)
	if err != nil {
		if hasExistingClient {
			return nil
		}
		return fmt.Errorf("unable to check for game updates: %w", err)
	}
	if statusCode == http.StatusNotFound || release == nil {
		if hasExistingClient {
			return nil
		}
		return fmt.Errorf("no published release found in %s", cfg.Repo)
	}

	if hasExistingClient && localVersion != "" && compareSemver(release.TagName, localVersion) <= 0 {
		return nil
	}

	payload, checksum := selectReleaseAssets(release.Assets)
	if payload == nil {
		if hasExistingClient {
			return nil
		}
		return fmt.Errorf("release %s does not include a downloadable Windows client asset", release.TagName)
	}

	ui.Show(fmt.Sprintf("Updating World War Pixel to %s...", release.TagName))

	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return err
	}
	payloadPath := filepath.Join(tmpDir, filepath.Base(payload.Name))
	if err := downloadFileWithProgress(ctx, client, payload.BrowserDownloadURL, payloadPath, cfg.DownloadTimeout, maxPayloadBytes, func(done, total int64) {
		ui.SetStatus(formatDownloadProgress(release.TagName, done, total))
	}); err != nil {
		return err
	}

	if checksum != nil {
		ui.SetStatus(fmt.Sprintf("Verifying World War Pixel %s...", release.TagName))
		sumsBody, err := fetchSmallBytes(ctx, client, checksum.BrowserDownloadURL, cfg.CheckTimeout, maxChecksumsSize)
		if err != nil {
			return fmt.Errorf("failed to download checksums: %w", err)
		}
		if err := verifySHA256(payloadPath, payload.Name, sumsBody); err != nil {
			return err
		}
	}

	ui.SetStatus(fmt.Sprintf("Installing World War Pixel %s...", release.TagName))
	if err := os.MkdirAll(stageDir, 0755); err != nil {
		return err
	}
	if strings.HasSuffix(strings.ToLower(payload.Name), ".zip") {
		if err := extractClientZip(payloadPath, stageDir, maxPayloadBytes); err != nil {
			return err
		}
	} else {
		if err := copyFile(payloadPath, filepath.Join(stageDir, clientExeName)); err != nil {
			return err
		}
	}

	return applyStagedUpdate(stageDir, cfg.GameDir, release.TagName)
}

func fetchLatestRelease(ctx context.Context, client *http.Client, apiBase, repo string, timeout time.Duration) (*ghRelease, int, error) {
	reqCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	endpoint := strings.TrimRight(apiBase, "/") + "/repos/" + repo + "/releases/latest"
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, http.StatusNotFound, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, resp.StatusCode, fmt.Errorf("GitHub API returned HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxChecksumsSize))
	if err != nil {
		return nil, resp.StatusCode, err
	}
	var release ghRelease
	if err := json.Unmarshal(body, &release); err != nil {
		return nil, resp.StatusCode, err
	}
	if strings.TrimSpace(release.TagName) == "" {
		return nil, resp.StatusCode, errors.New("release tag_name missing")
	}
	return &release, resp.StatusCode, nil
}

func fetchSmallBytes(ctx context.Context, client *http.Client, url string, timeout time.Duration, maxBytes int64) ([]byte, error) {
	reqCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maxBytes {
		return nil, fmt.Errorf("response exceeds %d byte limit", maxBytes)
	}
	return data, nil
}

func downloadFileWithProgress(ctx context.Context, client *http.Client, url, destPath string, timeout time.Duration, maxBytes int64, onProgress func(done, total int64)) error {
	reqCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("download returned HTTP %d", resp.StatusCode)
	}
	if resp.ContentLength > maxBytes {
		return fmt.Errorf("download size %d exceeds %d byte limit", resp.ContentLength, maxBytes)
	}

	out, err := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer out.Close()

	buf := make([]byte, 32*1024)
	var written int64
	lastReport := time.Now().Add(-time.Second)

	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			written += int64(n)
			if written > maxBytes {
				return fmt.Errorf("download exceeds %d byte limit", maxBytes)
			}
			if _, writeErr := out.Write(buf[:n]); writeErr != nil {
				return writeErr
			}
			if onProgress != nil && time.Since(lastReport) >= 100*time.Millisecond {
				onProgress(written, resp.ContentLength)
				lastReport = time.Now()
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	if onProgress != nil {
		onProgress(written, resp.ContentLength)
	}
	return out.Close()
}

func formatDownloadProgress(tag string, done, total int64) string {
	doneMB := float64(done) / (1024.0 * 1024.0)
	if total > 0 {
		pct := (done * 100) / total
		if pct > 100 {
			pct = 100
		}
		totalMB := float64(total) / (1024.0 * 1024.0)
		return fmt.Sprintf("Downloading World War Pixel %s (%d%%, %.1f / %.1f MB)", tag, pct, doneMB, totalMB)
	}
	return fmt.Sprintf("Downloading World War Pixel %s (%.1f MB)", tag, doneMB)
}

func readLocalVersion(versionPath string) string {
	data, err := os.ReadFile(versionPath)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func fileExists(p string) bool {
	info, err := os.Stat(p)
	return err == nil && !info.IsDir()
}
