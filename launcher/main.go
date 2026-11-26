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
	patchesDirName   = "patches"
	clientExeName    = "WorldWarPixel-Client.exe"
	clientPckName    = "WorldWarPixel-Client.pck"
	versionFileName  = "version.txt"
	patchNotesName   = "PATCH_NOTES.md"
	userAgent        = "WorldWarPixel-Launcher/2.0"
	checkTimeout     = 4 * time.Second
	downloadTimeout  = 10 * time.Minute
	maxPayloadBytes  = int64(512 << 20)
	maxChecksumsSize = int64(1 << 20)
)

type updateKind int

const (
	updateNone updateKind = iota
	updateFullClient
	updatePackReplace
	updateDeltaPatch
)

type ghAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
}

type ghRelease struct {
	TagName     string    `json:"tag_name"`
	Name        string    `json:"name"`
	Body        string    `json:"body"`
	PublishedAt string    `json:"published_at"`
	Assets      []ghAsset `json:"assets"`
}

type updatePlan struct {
	Kind         updateKind
	TagName      string
	LocalVersion string
	Payload      *ghAsset
	Checksum     *ghAsset
	ReleaseNotes string
	HasClient    bool
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
	OpenHub         bool
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

	skipUpdate, waitForChild, openHub, forwardArgs := parseArgs(args)
	if os.Getenv("WWP_SKIP_UPDATE") == "1" {
		skipUpdate = true
	}
	if os.Getenv("WWP_NO_HUB") == "1" {
		openHub = false
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
		OpenHub:         openHub,
		ForwardArgs:     forwardArgs,
	}

	// Interactive Launcher Hub window on normal double-click or --hub (unless --wait / --no-update / CLI game args are passed).
	if cfg.OpenHub || (!cfg.WaitForChild && !cfg.SkipUpdate && len(cfg.ForwardArgs) == 0 && os.Getenv("WWP_NO_HUB") != "1") {
		return runLauncherHub(cfg)
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

	return launchGameClient(cfg)
}

func launchGameClient(cfg launcherConfig) int {
	clientExePath := filepath.Join(cfg.GameDir, clientExeName)
	if !fileExists(clientExePath) {
		showErrorBox(
			"World War Pixel",
			fmt.Sprintf("Game binary missing:\n%s\n\nUse Install / Update in the Launcher or connect to the internet.", clientExePath),
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

func parseArgs(args []string) (skipUpdate bool, waitForChild bool, openHub bool, forwardArgs []string) {
	for _, arg := range args {
		switch arg {
		case "--no-update":
			skipUpdate = true
		case "--wait":
			waitForChild = true
		case "--hub":
			openHub = true
		default:
			forwardArgs = append(forwardArgs, arg)
		}
	}
	return skipUpdate, waitForChild, openHub, forwardArgs
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

func findChecksumForAsset(assets []ghAsset, assetName string) *ghAsset {
	for i := range assets {
		if strings.EqualFold(assets[i].Name, "SHA256SUMS.txt") {
			c := assets[i]
			return &c
		}
	}
	target := strings.ToLower(assetName) + ".sha256"
	for i := range assets {
		if strings.ToLower(assets[i].Name) == target {
			c := assets[i]
			return &c
		}
	}
	return nil
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
			if strings.HasSuffix(lower, ".zip") && !strings.Contains(lower, "patch") {
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

	return payload, findChecksumForAsset(assets, payload.Name)
}

// selectPatchOrClientAssets prefers lightweight .pck patches when the client runtime (.exe) is already installed.
func selectPatchOrClientAssets(assets []ghAsset, hasClientExe bool) (updateKind, *ghAsset, *ghAsset) {
	if hasClientExe {
		for i := range assets {
			lower := strings.ToLower(assets[i].Name)
			if strings.HasPrefix(lower, "worldwarpixel-delta-") && strings.HasSuffix(lower, ".pck") {
				c := assets[i]
				return updateDeltaPatch, &c, findChecksumForAsset(assets, c.Name)
			}
		}
		for i := range assets {
			lower := strings.ToLower(assets[i].Name)
			if lower == "worldwarpixel-patch.zip" || lower == "worldwarpixel-patch.pck" {
				c := assets[i]
				return updatePackReplace, &c, findChecksumForAsset(assets, c.Name)
			}
		}
	}

	payload, checksum := selectReleaseAssets(assets)
	if payload == nil {
		return updateNone, nil, nil
	}
	return updateFullClient, payload, checksum
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

func extractZipFiltered(zipPath, destDir string, maxBytes int64, requiredFile string) error {
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

	if requiredFile != "" && !fileExists(filepath.Join(absDest, requiredFile)) {
		return fmt.Errorf("archive does not contain %s", requiredFile)
	}
	return nil
}

func extractClientZip(zipPath, destDir string, maxBytes int64) error {
	return extractZipFiltered(zipPath, destDir, maxBytes, clientExeName)
}

func extractPatchZip(zipPath, destDir string, maxBytes int64) error {
	return extractZipFiltered(zipPath, destDir, maxBytes, clientPckName)
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

	// Base client replaced cleanly; clear old runtime delta patches.
	_ = os.RemoveAll(filepath.Join(gameDir, patchesDirName))

	if err := writeLocalVersion(gameDir, newVersion); err != nil {
		restoreBackup()
		return err
	}

	if hadExisting {
		_ = os.Remove(backupExe)
	}
	_ = os.RemoveAll(stageDir)
	return nil
}

func applyPackPatch(stageDir, gameDir, newVersion string) error {
	stagedPck := filepath.Join(stageDir, clientPckName)
	if !fileExists(stagedPck) {
		return fmt.Errorf("staged patch missing %s", clientPckName)
	}
	if err := os.MkdirAll(gameDir, 0755); err != nil {
		return err
	}

	destPck := filepath.Join(gameDir, clientPckName)
	backupPck := destPck + ".bak"
	_ = os.Remove(backupPck)

	hadExisting := false
	if fileExists(destPck) {
		if err := os.Rename(destPck, backupPck); err != nil {
			return fmt.Errorf("cannot replace running or locked pack file: %w", err)
		}
		hadExisting = true
	}

	restoreBackup := func() {
		if hadExisting {
			_ = os.Remove(destPck)
			_ = os.Rename(backupPck, destPck)
		}
	}

	if err := moveStageTree(stageDir, gameDir); err != nil {
		restoreBackup()
		return err
	}

	// Base .pck updated; remove old delta patches now superseded by full .pck.
	_ = os.RemoveAll(filepath.Join(gameDir, patchesDirName))

	if err := writeLocalVersion(gameDir, newVersion); err != nil {
		restoreBackup()
		return err
	}

	if hadExisting {
		_ = os.Remove(backupPck)
	}
	_ = os.RemoveAll(stageDir)
	return nil
}

func applyDeltaPatch(srcPckPath, gameDir, fileName, newVersion string) error {
	if !fileExists(srcPckPath) {
		return fmt.Errorf("delta patch missing: %s", srcPckPath)
	}
	patchesDir := filepath.Join(gameDir, patchesDirName)
	if err := os.MkdirAll(patchesDir, 0755); err != nil {
		return err
	}
	destPath := filepath.Join(patchesDir, filepath.Base(fileName))
	tmpPath := destPath + ".tmp"
	if err := copyFile(srcPckPath, tmpPath); err != nil {
		return err
	}
	_ = os.Remove(destPath)
	if err := os.Rename(tmpPath, destPath); err != nil {
		return err
	}
	return writeLocalVersion(gameDir, newVersion)
}

func writeLocalVersion(gameDir, newVersion string) error {
	normVersion := strings.TrimSpace(newVersion)
	if normVersion == "" {
		return nil
	}
	return os.WriteFile(filepath.Join(gameDir, versionFileName), []byte(normVersion+"\n"), 0644)
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

// buildUpdatePlan queries releases & patch notes without modifying files on disk.
func buildUpdatePlan(ctx context.Context, cfg launcherConfig) (updatePlan, error) {
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{}
	}
	if cfg.CheckTimeout <= 0 {
		cfg.CheckTimeout = checkTimeout
	}

	clientExePath := filepath.Join(cfg.GameDir, clientExeName)
	hasExistingClient := fileExists(clientExePath)
	localVersion := readLocalVersion(filepath.Join(cfg.GameDir, versionFileName))

	plan := updatePlan{
		Kind:         updateNone,
		LocalVersion: localVersion,
		HasClient:    hasExistingClient,
	}

	releases, statusCode, err := fetchReleases(ctx, client, cfg.APIBase, cfg.Repo, cfg.CheckTimeout)
	if err != nil || statusCode == http.StatusNotFound || len(releases) == 0 {
		plan.ReleaseNotes = formatPatchNotes(nil, cfg.GameDir, cfg.ExeDir)
		if err != nil {
			return plan, err
		}
		return plan, fmt.Errorf("no published release found in %s", cfg.Repo)
	}

	latest := releases[0]
	plan.TagName = latest.TagName
	plan.ReleaseNotes = formatPatchNotes(releases, cfg.GameDir, cfg.ExeDir)

	if hasExistingClient && localVersion != "" && compareSemver(latest.TagName, localVersion) <= 0 {
		return plan, nil
	}

	kind, payload, checksum := selectPatchOrClientAssets(latest.Assets, hasExistingClient)
	if payload == nil || kind == updateNone {
		return plan, fmt.Errorf("release %s does not include a downloadable Windows client or patch asset", latest.TagName)
	}
	plan.Kind = kind
	plan.Payload = payload
	plan.Checksum = checksum
	return plan, nil
}

func executeUpdatePlan(ctx context.Context, cfg launcherConfig, plan updatePlan, onStatus func(status string, pct int)) error {
	if plan.Kind == updateNone || plan.Payload == nil {
		return nil
	}
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

	actionVerb := "Updating"
	if !plan.HasClient {
		actionVerb = "Installing"
	} else if plan.Kind == updatePackReplace || plan.Kind == updateDeltaPatch {
		actionVerb = "Patching"
	}
	if onStatus != nil {
		onStatus(fmt.Sprintf("%s World War Pixel %s...", actionVerb, plan.TagName), 2)
	}

	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return err
	}
	payloadPath := filepath.Join(tmpDir, filepath.Base(plan.Payload.Name))
	if err := downloadFileWithProgress(ctx, client, plan.Payload.BrowserDownloadURL, payloadPath, cfg.DownloadTimeout, maxPayloadBytes, func(done, total int64) {
		pct := 15
		if total > 0 {
			pct = int((done * 80) / total)
			if pct > 80 {
				pct = 80
			}
		}
		if onStatus != nil {
			onStatus(formatDownloadProgress(plan.TagName, done, total), pct)
		}
	}); err != nil {
		return err
	}

	if plan.Checksum != nil {
		if onStatus != nil {
			onStatus(fmt.Sprintf("Verifying SHA-256 for %s...", plan.Payload.Name), 85)
		}
		sumsBody, err := fetchSmallBytes(ctx, client, plan.Checksum.BrowserDownloadURL, cfg.CheckTimeout, maxChecksumsSize)
		if err != nil {
			return fmt.Errorf("failed to download checksums: %w", err)
		}
		if err := verifySHA256(payloadPath, plan.Payload.Name, sumsBody); err != nil {
			return err
		}
	}

	if onStatus != nil {
		onStatus(fmt.Sprintf("Installing World War Pixel %s...", plan.TagName), 92)
	}

	switch plan.Kind {
	case updateDeltaPatch:
		if err := applyDeltaPatch(payloadPath, cfg.GameDir, plan.Payload.Name, plan.TagName); err != nil {
			return err
		}
	case updatePackReplace:
		if err := os.MkdirAll(stageDir, 0755); err != nil {
			return err
		}
		if strings.HasSuffix(strings.ToLower(plan.Payload.Name), ".zip") {
			if err := extractPatchZip(payloadPath, stageDir, maxPayloadBytes); err != nil {
				return err
			}
		} else {
			if err := copyFile(payloadPath, filepath.Join(stageDir, clientPckName)); err != nil {
				return err
			}
		}
		if err := applyPackPatch(stageDir, cfg.GameDir, plan.TagName); err != nil {
			return err
		}
	default:
		if err := os.MkdirAll(stageDir, 0755); err != nil {
			return err
		}
		if strings.HasSuffix(strings.ToLower(plan.Payload.Name), ".zip") {
			if err := extractClientZip(payloadPath, stageDir, maxPayloadBytes); err != nil {
				return err
			}
		} else {
			if err := copyFile(payloadPath, filepath.Join(stageDir, clientExeName)); err != nil {
				return err
			}
		}
		if err := applyStagedUpdate(stageDir, cfg.GameDir, plan.TagName); err != nil {
			return err
		}
	}

	if onStatus != nil {
		onStatus(fmt.Sprintf("Ready · World War Pixel %s installed.", plan.TagName), 100)
	}
	return nil
}

func checkAndUpdate(ctx context.Context, cfg launcherConfig, ui progressUI) error {
	plan, err := buildUpdatePlan(ctx, cfg)
	if err != nil {
		if plan.HasClient {
			return nil
		}
		return fmt.Errorf("unable to check for game updates: %w", err)
	}
	if plan.Kind == updateNone || plan.Payload == nil {
		return nil
	}

	ui.Show(fmt.Sprintf("Updating World War Pixel to %s...", plan.TagName))
	return executeUpdatePlan(ctx, cfg, plan, func(status string, _ int) {
		ui.SetStatus(status)
	})
}

func fetchReleases(ctx context.Context, client *http.Client, apiBase, repo string, timeout time.Duration) ([]ghRelease, int, error) {
	reqCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	endpoint := strings.TrimRight(apiBase, "/") + "/repos/" + repo + "/releases?per_page=5"
	req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", userAgent)

	resp, err := client.Do(req)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			body, readErr := io.ReadAll(io.LimitReader(resp.Body, maxChecksumsSize))
			if readErr == nil {
				var list []ghRelease
				if jsonErr := json.Unmarshal(body, &list); jsonErr == nil && len(list) > 0 && strings.TrimSpace(list[0].TagName) != "" {
					return list, resp.StatusCode, nil
				}
			}
		}
	}

	// Fallback to /releases/latest (also supports test servers stubbing only /releases/latest).
	latest, code, latestErr := fetchLatestRelease(ctx, client, apiBase, repo, timeout)
	if latestErr != nil || latest == nil {
		return nil, code, latestErr
	}
	return []ghRelease{*latest}, code, nil
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

func normalizeCRLFs(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return strings.ReplaceAll(s, "\n", "\r\n")
}

func formatPatchNotes(releases []ghRelease, gameDir, exeDir string) string {
	if len(releases) > 0 {
		var b strings.Builder
		for i, rel := range releases {
			if i > 0 {
				b.WriteString("\n----------------------------------------\n\n")
			}
			title := strings.TrimSpace(rel.Name)
			if title == "" {
				title = rel.TagName
			} else if !strings.Contains(title, rel.TagName) {
				title = rel.TagName + " — " + title
			}
			b.WriteString(title)
			if len(rel.PublishedAt) >= 10 {
				b.WriteString("  (" + rel.PublishedAt[:10] + ")")
			}
			b.WriteString("\n")
			body := strings.TrimSpace(rel.Body)
			if body != "" {
				b.WriteString(body + "\n")
			} else {
				b.WriteString("- Maintenance & performance improvements.\n")
			}
		}
		return normalizeCRLFs(b.String())
	}

	for _, candidate := range []string{
		filepath.Join(gameDir, patchNotesName),
		filepath.Join(exeDir, patchNotesName),
		filepath.Join(filepath.Dir(exeDir), patchNotesName),
	} {
		if raw, err := os.ReadFile(candidate); err == nil && len(bytes.TrimSpace(raw)) > 0 {
			return normalizeCRLFs(string(raw))
		}
	}
	return normalizeCRLFs("World War Pixel\nNo remote patch notes available offline.")
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
