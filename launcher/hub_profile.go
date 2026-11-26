package main

import (
	"bufio"
	"bytes"
	"fmt"
	"image"
	_ "image/png"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type hubPhase int

const (
	hubChecking hubPhase = iota
	hubReadyToPlay
	hubNeedsInstall
	hubNeedsPatch
	hubNeedsFullUpdate
	hubWorking
)

type localProfile struct {
	Username      string
	Token         string
	IsAccount     bool
	Avatar        image.Image
	AvatarHash    string
	AvatarFrames  int
	AvatarDelayMs int
	GamesPlayed   int
	Wins          int
	Elo           int
	RankTitle     string
}

type noteKind int

const (
	noteHeading noteKind = iota
	noteSubheading
	noteBullet
	noteBody
)

type noteLine struct {
	Kind noteKind
	Text string
}

type patchItem struct {
	Title string
	Body  string
}

type patchRelease struct {
	Version  string
	Title    string
	Date     string
	Items    []patchItem
	RawLines []string
}

// resolveGodotUserDir locates Godot's user data directory for World War Pixel.
func resolveGodotUserDir() string {
	appData := strings.TrimSpace(os.Getenv("APPDATA"))
	if appData == "" {
		home, _ := os.UserHomeDir()
		if home == "" {
			return ""
		}
		return filepath.Join(home, ".local", "share", "godot", "app_userdata", "World War Pixel")
	}
	return filepath.Join(appData, "Godot", "app_userdata", "World War Pixel")
}

// loadLocalGodotProfile reads saved username/account state & optional custom PFP from Godot user_data.
func loadLocalGodotProfile(userDir string) localProfile {
	prof := localProfile{
		Username:      "Commander",
		AvatarFrames:  1,
		AvatarDelayMs: 100,
	}
	if userDir == "" {
		return prof
	}

	cfgPath := filepath.Join(userDir, "player_profile.cfg")
	if raw, err := os.ReadFile(cfgPath); err == nil {
		section := ""
		acctUser := ""
		acctToken := ""
		guestName := ""
		scanner := bufio.NewScanner(bytes.NewReader(raw))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
				continue
			}
			if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
				section = strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
				continue
			}
			eq := strings.IndexByte(line, '=')
			if eq < 0 {
				continue
			}
			key := strings.TrimSpace(line[:eq])
			val := strings.TrimSpace(line[eq+1:])
			val = strings.Trim(val, `"`)
			switch section {
			case "account":
				switch key {
				case "username":
					if val != "" {
						acctUser = val
					}
				case "token":
					if val != "" {
						acctToken = val
					}
				case "avatar_hash":
					prof.AvatarHash = val
				case "avatar_frames":
					if n, convErr := strconv.Atoi(val); convErr == nil && n > 0 {
						prof.AvatarFrames = n
					}
				case "avatar_delay_ms":
					if n, convErr := strconv.Atoi(val); convErr == nil && n >= 40 {
						prof.AvatarDelayMs = n
					}
				}
			case "profile":
				if key == "player_name" && val != "" {
					guestName = val
				}
			}
		}
		if acctUser != "" {
			prof.Username = acctUser
			prof.Token = acctToken
			prof.IsAccount = acctToken != ""
		} else if guestName != "" {
			prof.Username = guestName
		}
	}

	avPath := filepath.Join(userDir, "custom_avatar.png")
	if rawAv, err := os.ReadFile(avPath); err == nil && len(rawAv) > 0 {
		if frame0 := decodeAvatarFrame0(rawAv); frame0 != nil {
			prof.Avatar = frame0
		}
	}
	return prof
}

func decodeAvatarFrame0(pngBytes []byte) image.Image {
	img, _, decErr := image.Decode(bytes.NewReader(pngBytes))
	if decErr != nil {
		return nil
	}
	b := img.Bounds()
	// custom_avatar.png stores a horizontal strip of square 64x64 frames; crop frame 0.
	h := b.Dy()
	if b.Dx() > h && h > 0 {
		sub := image.NewNRGBA(image.Rect(0, 0, h, h))
		for y := 0; y < h; y++ {
			for x := 0; x < h; x++ {
				sub.Set(x, y, img.At(b.Min.X+x, b.Min.Y+y))
			}
		}
		return sub
	}
	return img
}

// saveLocalGodotProfile persists account session & optional avatar strip PNG matching Godot ConfigFile format.
func saveLocalGodotProfile(userDir string, prof *localProfile, avatarPNG []byte) error {
	if userDir == "" || prof == nil {
		return nil
	}
	if err := os.MkdirAll(userDir, 0755); err != nil {
		return err
	}

	if len(avatarPNG) > 0 {
		avPath := filepath.Join(userDir, "custom_avatar.png")
		tmpAv := avPath + ".tmp"
		if err := os.WriteFile(tmpAv, avatarPNG, 0644); err != nil {
			return err
		}
		_ = os.Remove(avPath)
		if err := os.Rename(tmpAv, avPath); err != nil {
			return err
		}
		if frame0 := decodeAvatarFrame0(avatarPNG); frame0 != nil {
			prof.Avatar = frame0
		}
	}

	frames := prof.AvatarFrames
	if frames < 1 {
		frames = 1
	}
	delayMs := prof.AvatarDelayMs
	if delayMs < 40 {
		delayMs = 100
	}

	// Preserve all unrelated INI sections & keys from existing player_profile.cfg.
	type iniSection struct {
		name  string
		order []string
		vals  map[string]string
	}
	var sections []*iniSection
	secMap := map[string]*iniSection{}
	getSec := func(name string) *iniSection {
		low := strings.ToLower(name)
		if s, ok := secMap[low]; ok {
			return s
		}
		s := &iniSection{name: name, vals: map[string]string{}}
		secMap[low] = s
		sections = append(sections, s)
		return s
	}
	setKV := func(secName, key, formatted string) {
		s := getSec(secName)
		if _, exists := s.vals[key]; !exists {
			s.order = append(s.order, key)
		}
		s.vals[key] = formatted
	}

	cfgPath := filepath.Join(userDir, "player_profile.cfg")
	if existing, err := os.ReadFile(cfgPath); err == nil {
		curSec := "profile"
		scanner := bufio.NewScanner(bytes.NewReader(existing))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
				continue
			}
			if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
				curSec = strings.TrimSpace(line[1 : len(line)-1])
				getSec(curSec)
				continue
			}
			if eq := strings.IndexByte(line, '='); eq > 0 {
				k := strings.TrimSpace(line[:eq])
				v := strings.TrimSpace(line[eq+1:])
				setKV(curSec, k, v)
			}
		}
	}

	quoteINI := func(s string) string {
		esc := strings.ReplaceAll(s, `\`, `\\`)
		esc = strings.ReplaceAll(esc, `"`, `\"`)
		return `"` + esc + `"`
	}

	acctUser := ""
	if prof.IsAccount && prof.Username != "" {
		acctUser = prof.Username
	}
	setKV("account", "token", quoteINI(prof.Token))
	setKV("account", "username", quoteINI(acctUser))
	setKV("account", "avatar_hash", quoteINI(prof.AvatarHash))
	setKV("account", "avatar_frames", strconv.Itoa(frames))
	setKV("account", "avatar_delay_ms", strconv.Itoa(delayMs))
	if acctUser != "" {
		setKV("profile", "player_name", quoteINI(acctUser))
	}

	var out bytes.Buffer
	for i, sec := range sections {
		if len(sec.order) == 0 {
			continue
		}
		if i > 0 && out.Len() > 0 {
			out.WriteByte('\n')
		}
		fmt.Fprintf(&out, "[%s]\n\n", sec.name)
		for _, k := range sec.order {
			fmt.Fprintf(&out, "%s=%s\n", k, sec.vals[k])
		}
	}

	tmpCfg := cfgPath + ".tmp"
	if err := os.WriteFile(tmpCfg, out.Bytes(), 0644); err != nil {
		return err
	}
	_ = os.Remove(cfgPath)
	return os.Rename(tmpCfg, cfgPath)
}

// probeServerPing measures TCP handshake latency in ms to addr (returns -1 on failure).
func probeServerPing(addr string, timeout time.Duration) int {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return -1
	}
	_ = conn.Close()
	ms := int(time.Since(start).Milliseconds())
	if ms < 1 {
		ms = 1
	}
	return ms
}

// parsePatchNotesLines turns markdown-like release notes into structured styled lines.
func parsePatchNotesLines(raw string) []noteLine {
	norm := strings.ReplaceAll(raw, "\r\n", "\n")
	lines := strings.Split(norm, "\n")
	out := make([]noteLine, 0, len(lines))
	for _, rawL := range lines {
		l := strings.TrimSpace(rawL)
		if l == "" {
			continue
		}
		if strings.HasPrefix(l, "---") {
			continue
		}
		if strings.HasPrefix(l, "## ") {
			out = append(out, noteLine{Kind: noteSubheading, Text: strings.TrimSpace(strings.TrimPrefix(l, "## "))})
			continue
		}
		if strings.HasPrefix(l, "# ") {
			out = append(out, noteLine{Kind: noteHeading, Text: strings.TrimSpace(strings.TrimPrefix(l, "# "))})
			continue
		}
		if strings.HasPrefix(l, "- ") || strings.HasPrefix(l, "* ") {
			clean := strings.ReplaceAll(l[2:], "**", "")
			clean = strings.ReplaceAll(clean, "`", "")
			out = append(out, noteLine{Kind: noteBullet, Text: clean})
			continue
		}
		clean := strings.ReplaceAll(l, "**", "")
		clean = strings.ReplaceAll(clean, "`", "")
		out = append(out, noteLine{Kind: noteBody, Text: clean})
	}
	return out
}

// parsePatchReleases groups markdown or GitHub release logs into editorial release sections and feature cards.
func parsePatchReleases(raw string) []patchRelease {
	norm := strings.ReplaceAll(raw, "\r\n", "\n")
	lines := strings.Split(norm, "\n")

	var releases []patchRelease
	var cur *patchRelease

	flush := func() {
		if cur == nil {
			return
		}
		if cur.Version == "" {
			cur.Version = "LATEST"
		}
		if cur.Title == "" {
			cur.Title = "Release Notes"
		}
		releases = append(releases, *cur)
		cur = nil
	}

	ensureCur := func() {
		if cur == nil {
			cur = &patchRelease{Version: "PATCH", Title: "Release Notes"}
		}
	}

	for _, rawL := range lines {
		l := strings.TrimSpace(rawL)
		if l == "" {
			continue
		}
		if strings.HasPrefix(l, "---") {
			flush()
			continue
		}
		if strings.HasPrefix(l, "# ") && !strings.HasPrefix(l, "## ") {
			// Skip bare document banner like "# World War Pixel — Patch Notes" unless no section follows.
			heading := strings.TrimSpace(strings.TrimPrefix(l, "# "))
			if strings.Contains(strings.ToLower(heading), "patch notes") && strings.Contains(heading, "World War Pixel") {
				continue
			}
			flush()
			ver, title, date := splitReleaseHeading(heading)
			cur = &patchRelease{Version: ver, Title: title, Date: date}
			continue
		}
		if strings.HasPrefix(l, "## ") {
			flush()
			ver, title, date := splitReleaseHeading(strings.TrimSpace(strings.TrimPrefix(l, "## ")))
			cur = &patchRelease{Version: ver, Title: title, Date: date}
			continue
		}
		// Detect GitHub top-level header emitted by formatPatchNotes e.g. "v1.0.2 — Hotfix  (2026-11-26)"
		if !strings.HasPrefix(l, "-") && !strings.HasPrefix(l, "*") && cur == nil && (strings.HasPrefix(strings.ToLower(l), "v") || strings.Contains(l, "—")) {
			ver, title, date := splitReleaseHeading(l)
			cur = &patchRelease{Version: ver, Title: title, Date: date}
			continue
		}

		ensureCur()
		if strings.HasPrefix(l, "- ") || strings.HasPrefix(l, "* ") {
			bodyRaw := strings.TrimSpace(l[2:])
			item := splitBulletItem(bodyRaw)
			cur.Items = append(cur.Items, item)
			cur.RawLines = append(cur.RawLines, item.Title+": "+item.Body)
			continue
		}
		clean := strings.ReplaceAll(l, "**", "")
		clean = strings.ReplaceAll(clean, "`", "")
		if cur.Title == "Release Notes" && len(cur.Items) == 0 && !strings.Contains(clean, ".") {
			cur.Title = clean
		} else {
			cur.Items = append(cur.Items, patchItem{Title: "Update Note", Body: clean})
		}
		cur.RawLines = append(cur.RawLines, clean)
	}
	flush()

	if len(releases) == 0 {
		releases = append(releases, patchRelease{
			Version: "LOCAL",
			Title:   "World War Pixel",
			Items: []patchItem{
				{Title: "Release Notes Unavailable", Body: "Connect online or check the local changelog after updating."},
			},
		})
	}
	return releases
}

func splitReleaseHeading(s string) (version, title, date string) {
	clean := strings.TrimSpace(strings.ReplaceAll(s, "**", ""))
	if idx := strings.LastIndex(clean, "("); idx > 0 && strings.HasSuffix(clean, ")") {
		cand := strings.TrimSpace(clean[idx+1 : len(clean)-1])
		if len(cand) >= 8 && cand[0] >= '0' && cand[0] <= '9' {
			date = cand
			clean = strings.TrimSpace(clean[:idx])
		}
	}
	for _, sep := range []string{" — ", " - ", " – "} {
		if idx := strings.Index(clean, sep); idx > 0 {
			left := strings.TrimSpace(clean[:idx])
			right := strings.TrimSpace(clean[idx+len(sep):])
			if strings.HasPrefix(strings.ToLower(left), "v") || (len(left) > 0 && left[0] >= '0' && left[0] <= '9') {
				return left, right, date
			}
			return "RELEASE", clean, date
		}
	}
	fields := strings.Fields(clean)
	if len(fields) > 0 && (strings.HasPrefix(strings.ToLower(fields[0]), "v") || (fields[0][0] >= '0' && fields[0][0] <= '9')) {
		return fields[0], strings.TrimSpace(strings.TrimPrefix(clean, fields[0])), date
	}
	return "RELEASE", clean, date
}

func splitBulletItem(raw string) patchItem {
	// Parse markdown "**Headline**: description" cleanly before stripping markers.
	if strings.HasPrefix(raw, "**") {
		if end := strings.Index(raw[2:], "**"); end > 0 {
			head := strings.TrimSpace(raw[2 : 2+end])
			rest := strings.TrimSpace(raw[2+end+2:])
			rest = strings.TrimLeft(rest, ":—- ")
			rest = strings.ReplaceAll(rest, "**", "")
			rest = strings.ReplaceAll(rest, "`", "")
			return patchItem{Title: head, Body: rest}
		}
	}
	clean := strings.ReplaceAll(raw, "**", "")
	clean = strings.ReplaceAll(clean, "`", "")
	if idx := strings.Index(clean, ":"); idx > 2 && idx < 48 {
		return patchItem{
			Title: strings.TrimSpace(clean[:idx]),
			Body:  strings.TrimSpace(clean[idx+1:]),
		}
	}
	return patchItem{Title: "Highlight", Body: clean}
}
