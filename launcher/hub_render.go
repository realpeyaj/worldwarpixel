package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"image"
	"image/color"
	_ "image/png"
	"math"
	"strings"
)

//go:embed assets/hero_banner.png
var heroBannerPNG []byte

//go:embed assets/emblem.png
var emblemPNG []byte

const (
	hubWidth  = 1120
	hubHeight = 660
	railWidth = 64
)

type hubTab int

const (
	tabGame hubTab = iota
	tabNotes
	tabAccount
	tabSettings
)

type hitItem struct {
	id     string
	rect   image.Rectangle
	cursor bool
}

type textAlign int

const (
	alignLeft textAlign = iota
	alignCenter
	alignRight
)

type textOp struct {
	text      string
	rect      image.Rectangle
	clip      image.Rectangle // optional GDI clip rect (for smooth scrolling regions)
	sizePx    int
	bold      bool
	display   bool // true -> Bahnschrift display face; false -> Segoe UI
	multiline bool // true -> DT_WORDBREAK top-left (no ellipsis clipping)
	col       color.NRGBA
	align     textAlign
	ellipsis  bool
}

type hubRenderState struct {
	Tab             hubTab
	Phase           hubPhase
	LocalVersion    string
	LatestTag       string
	HasExe          bool
	Busy            bool
	Launching       bool
	StatusText      string
	ProgText        string
	ProgPct         int
	NotesRaw        string
	NotesScroll     int
	SelectedRelease int
	PingMs          int
	Profile         localProfile
	GameDir         string
	Repo            string
	HoverID         string
	PressID         string

	// Account & Social Hub state
	AuthModeRegister bool
	FocusField       string // "auth_user", "auth_pass", "friend_search"
	CaretVisible     bool
	InputUser        string
	InputPass        string
	InputSearch      string
	AuthBusy         bool
	AuthMessage      string
	AuthIsError      bool
	Friends          []apiUserProfile
	Incoming         []apiUserProfile
	SearchResults    []apiUserProfile
}

type hubAssets struct {
	hero   image.Image
	emblem image.Image
}

var loadedHubAssets *hubAssets

func getHubAssets() *hubAssets {
	if loadedHubAssets != nil {
		return loadedHubAssets
	}
	a := &hubAssets{}
	if im, _, err := image.Decode(bytes.NewReader(heroBannerPNG)); err == nil {
		a.hero = im
	}
	if im, _, err := image.Decode(bytes.NewReader(emblemPNG)); err == nil {
		a.emblem = im
	}
	loadedHubAssets = a
	return a
}

// VALORANT / Riot tactical editorial palette (obsidian, warm ivory, voltage crimson, brass)
var (
	colBg         = color.NRGBA{11, 12, 14, 255}   // #0B0C0E
	colRail       = color.NRGBA{7, 8, 10, 255}     // #07080A
	colHeaderBar  = color.NRGBA{14, 16, 20, 255}   // #0E1014
	colSurface    = color.NRGBA{18, 20, 24, 255}   // #121418
	colSurfaceAlp = color.NRGBA{17, 19, 24, 228}   // Translucent panel over hero
	colElevated   = color.NRGBA{24, 27, 33, 255}   // #181B21
	colHoverSurf  = color.NRGBA{32, 36, 44, 255}   // Hover fill
	colBorder     = color.NRGBA{35, 38, 47, 255}   // #23262F
	colBorderHi   = color.NRGBA{56, 62, 76, 255}   // Focused hairline
	colIvory      = color.NRGBA{236, 232, 225, 255} // #ECE8E1
	colStone      = color.NRGBA{154, 156, 163, 255} // #9A9CA3
	colMuted      = color.NRGBA{98, 102, 112, 255}  // #626670
	colCrimson    = color.NRGBA{255, 70, 85, 255}   // #FF4655
	colCrimsonHi  = color.NRGBA{255, 94, 107, 255}  // #FF5E6B
	colCrimsonDn  = color.NRGBA{212, 50, 64, 255}   // #D43240
	colBrass      = color.NRGBA{216, 178, 92, 255}  // #D8B25C
	colEmerald    = color.NRGBA{59, 209, 138, 255}  // #3BD18A
	colWhite      = color.NRGBA{255, 255, 255, 255}
)

// renderHubFrame renders the 1120x660 tactical editorial launcher buffer + ClearType text overlays.
func renderHubFrame(dstPix []byte, stride int, bgraOrder bool, st hubRenderState) ([]hitItem, []textOp, int) {
	hits := make([]hitItem, 0, 28)
	texts := make([]textOp, 0, 84)
	assets := getHubAssets()

	c := canvasBuf{pix: dstPix, w: hubWidth, h: hubHeight, stride: stride, bgra: bgraOrder}

	// 1. Base Obsidian canvas & left navigation rail
	c.fillRect(image.Rect(0, 0, hubWidth, hubHeight), colBg)
	if st.Tab == tabGame && assets.hero != nil {
		c.blitImage(assets.hero, image.Rect(railWidth, 0, hubWidth, hubHeight))
	} else if st.Tab == tabAccount && !st.Profile.IsAccount && assets.hero != nil {
		// Split screen hero backdrop on signed-out Account screen
		c.blitImageRect(assets.hero, image.Rect(railWidth+420, 0, hubWidth, hubHeight), image.Rect(380, 0, 1056, 660))
		c.fillRect(image.Rect(railWidth+420, 0, hubWidth, hubHeight), color.NRGBA{11, 12, 14, 145})
	} else {
		c.fillRect(image.Rect(railWidth, 0, hubWidth, 72), colHeaderBar)
		c.fillRect(image.Rect(railWidth, 72, hubWidth, 73), colBorder)
	}

	c.fillRect(image.Rect(0, 0, railWidth, hubHeight), colRail)
	c.fillRect(image.Rect(railWidth, 0, railWidth+1, hubHeight), colBorder)

	// 2. Left Rail Emblem & Navigation
	if assets.emblem != nil {
		c.blitScaledAlpha(assets.emblem, image.Rect(14, 16, 50, 52))
	}
	c.fillRect(image.Rect(16, 66, 48, 67), colBorder)

	navTop := []struct {
		id  string
		tab hubTab
		y   int
	}{
		{"tab_game", tabGame, 88},
		{"tab_notes", tabNotes, 144},
		{"tab_account", tabAccount, 200},
	}
	for _, n := range navTop {
		r := image.Rect(10, n.y, 54, n.y+42)
		hits = append(hits, hitItem{id: n.id, rect: r, cursor: true})
		active := st.Tab == n.tab
		hovered := st.HoverID == n.id
		if active {
			c.fillRoundedRect(r, 3, colElevated)
			c.fillRect(image.Rect(0, n.y+8, 3, n.y+34), colCrimson)
		} else if hovered {
			c.fillRoundedRect(r, 3, color.NRGBA{20, 23, 29, 255})
		}
		icCol := colStone
		if active {
			icCol = colIvory
		} else if hovered {
			icCol = colWhite
		}
		switch n.tab {
		case tabGame:
			c.drawIconGlobeTarget(32, n.y+21, icCol)
		case tabNotes:
			c.drawIconNotes(32, n.y+21, icCol)
		case tabAccount:
			c.drawIconAccount(32, n.y+21, icCol)
			if len(st.Incoming) > 0 {
				c.fillCircle(44, n.y+11, 4, colCrimson)
			}
		}
	}

	// Bottom-pinned Settings icon + compact version stamp
	setRect := image.Rect(10, hubHeight-86, 54, hubHeight-44)
	hits = append(hits, hitItem{id: "tab_settings", rect: setRect, cursor: true})
	if st.Tab == tabSettings {
		c.fillRoundedRect(setRect, 3, colElevated)
		c.fillRect(image.Rect(0, setRect.Min.Y+8, 3, setRect.Max.Y-8), colCrimson)
	} else if st.HoverID == "tab_settings" {
		c.fillRoundedRect(setRect, 3, color.NRGBA{20, 23, 29, 255})
	}
	setCol := colStone
	if st.Tab == tabSettings {
		setCol = colIvory
	} else if st.HoverID == "tab_settings" {
		setCol = colWhite
	}
	c.drawIconGear(32, setRect.Min.Y+21, setCol)

	verLbl := st.LocalVersion
	if verLbl == "" {
		verLbl = st.LatestTag
	}
	if verLbl == "" {
		verLbl = "v1.0.0"
	}
	texts = append(texts, textOp{
		text:    verLbl,
		rect:    image.Rect(4, hubHeight-32, railWidth-4, hubHeight-12),
		sizePx:  11,
		display: true,
		col:     colMuted,
		align:   alignCenter,
	})

	// 3. Top-right Profile Button & Frameless Window Controls
	profLabel := "SIGN IN"
	if st.Profile.IsAccount && st.Profile.Username != "" {
		profLabel = st.Profile.Username
	}
	profW := 136
	if len(profLabel) > 9 {
		profW = 166
	}
	if len(profLabel) > 15 {
		profW = 196
	}
	profRect := image.Rect(hubWidth-98-profW, 14, hubWidth-98, 46)
	hits = append(hits, hitItem{id: "open_account", rect: profRect, cursor: true})
	profBg := color.NRGBA{16, 18, 23, 235}
	profStroke := colBorder
	if st.HoverID == "open_account" {
		profBg = colElevated
		profStroke = colBorderHi
	}
	c.fillRoundedRect(profRect, 3, profBg)
	c.strokeRoundedRect(profRect, 3, profStroke)

	avRect := image.Rect(profRect.Min.X+6, profRect.Min.Y+5, profRect.Min.X+28, profRect.Min.Y+27)
	if st.Profile.Avatar != nil {
		c.blitRoundedSquare(st.Profile.Avatar, avRect, 2)
	} else if assets.emblem != nil {
		c.blitScaledAlpha(assets.emblem, avRect)
	}
	if st.Profile.IsAccount {
		c.fillCircle(profRect.Min.X+27, profRect.Min.Y+25, 3, colEmerald)
	}
	texts = append(texts, textOp{
		text:     profLabel,
		rect:     image.Rect(profRect.Min.X+35, profRect.Min.Y+3, profRect.Max.X-10, profRect.Max.Y-3),
		sizePx:   13,
		bold:     true,
		display:  st.Profile.IsAccount == false,
		col:      colIvory,
		align:    alignLeft,
		ellipsis: true,
	})

	minRect := image.Rect(hubWidth-84, 14, hubWidth-50, 46)
	closeRect := image.Rect(hubWidth-44, 14, hubWidth-10, 46)
	hits = append(hits, hitItem{id: "minimize", rect: minRect, cursor: true})
	hits = append(hits, hitItem{id: "close", rect: closeRect, cursor: true})
	if st.HoverID == "minimize" {
		c.fillRoundedRect(minRect, 3, colElevated)
	}
	c.fillRect(image.Rect(minRect.Min.X+11, minRect.Min.Y+16, minRect.Max.X-11, minRect.Min.Y+18), colIvory)
	if st.HoverID == "close" {
		c.fillRoundedRect(closeRect, 3, colCrimson)
	}
	c.drawIconClose(closeRect.Min.X+17, closeRect.Min.Y+16, colIvory)

	// 4. Tab Body
	maxScroll := 0
	switch st.Tab {
	case tabGame:
		hits, texts = renderTabGame(&c, st, hits, texts)
	case tabNotes:
		hits, texts, maxScroll = renderTabNotes(&c, st, hits, texts)
	case tabAccount:
		hits, texts = renderTabAccount(&c, st, hits, texts)
	case tabSettings:
		hits, texts = renderTabSettings(&c, st, hits, texts)
	}

	// Crisp outer 1px window border
	c.strokeRect(image.Rect(0, 0, hubWidth, hubHeight), color.NRGBA{32, 35, 43, 255})
	return hits, texts, maxScroll
}

func renderTabGame(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp) {
	leftX := railWidth + 52

	// Version/Update overline — concise editorial metadata, no filler badges
	overline := "WORLD WAR PIXEL"
	overCol := colCrimson
	switch st.Phase {
	case hubChecking:
		overline = "CHECKING FOR UPDATES"
		overCol = colBrass
	case hubNeedsInstall:
		overline = fmt.Sprintf("CLIENT INSTALL · %s", strings.ToUpper(st.LatestTag))
		overCol = colCrimson
	case hubNeedsPatch:
		overline = fmt.Sprintf("UPDATE AVAILABLE · %s", strings.ToUpper(st.LatestTag))
		overCol = colBrass
	case hubNeedsFullUpdate:
		overline = fmt.Sprintf("UPDATE AVAILABLE · %s", strings.ToUpper(st.LatestTag))
		overCol = colBrass
	case hubWorking:
		overline = "INSTALLING UPDATE"
		overCol = colBrass
	default:
		if st.LocalVersion != "" {
			overline = "VERSION " + strings.ToUpper(st.LocalVersion)
			overCol = colBrass
		} else if st.HasExe {
			overline = "INSTALLED CLIENT"
			overCol = colBrass
		}
	}

	texts = append(texts,
		textOp{
			text:    overline,
			rect:    image.Rect(leftX, 88, leftX+420, 110),
			sizePx:  12,
			bold:    true,
			display: true,
			col:     overCol,
			align:   alignLeft,
		},
		textOp{
			text:    "WORLD WAR PIXEL",
			rect:    image.Rect(leftX, 114, leftX+700, 174),
			sizePx:  50,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignLeft,
		},
	)
	c.fillRect(image.Rect(leftX, 182, leftX+48, 185), colCrimson)
	texts = append(texts, textOp{
		text:   "Real-time global strategy across a living pixel-art Earth.",
		rect:   image.Rect(leftX, 196, leftX+640, 222),
		sizePx: 15,
		col:    colStone,
		align:  alignLeft,
	})

	// Primary Riot Action Row
	btnY := 254
	if st.Phase == hubWorking {
		progBox := image.Rect(leftX, btnY, leftX+460, btnY+52)
		c.fillRoundedRect(progBox, 3, colSurface)
		c.strokeRoundedRect(progBox, 3, colBorder)
		pct := st.ProgPct
		if pct < 0 {
			pct = 0
		}
		if pct > 100 {
			pct = 100
		}
		barBg := image.Rect(leftX+14, btnY+34, leftX+446, btnY+40)
		c.fillRect(barBg, colElevated)
		fw := (barBg.Dx() * pct) / 100
		if fw > 0 {
			c.fillRect(image.Rect(barBg.Min.X, barBg.Min.Y, barBg.Min.X+fw, barBg.Max.Y), colCrimson)
		}
		texts = append(texts,
			textOp{
				text:     st.ProgText,
				rect:     image.Rect(leftX+14, btnY+8, leftX+390, btnY+30),
				sizePx:   13,
				bold:     true,
				col:      colIvory,
				align:    alignLeft,
				ellipsis: true,
			},
			textOp{
				text:    fmt.Sprintf("%d%%", pct),
				rect:    image.Rect(leftX+392, btnY+8, leftX+446, btnY+30),
				sizePx:  13,
				bold:    true,
				display: true,
				col:     colCrimsonHi,
				align:   alignRight,
			},
		)
	} else {
		ctaR := image.Rect(leftX, btnY, leftX+224, btnY+52)
		hits = append(hits, hitItem{id: "primary", rect: ctaR, cursor: true})
		ctaCol := colCrimson
		if st.Phase == hubChecking || st.Launching {
			ctaCol = colElevated
		} else if st.PressID == "primary" {
			ctaCol = colCrimsonDn
		} else if st.HoverID == "primary" {
			ctaCol = colCrimsonHi
		}
		c.fillRoundedRect(ctaR, 3, ctaCol)
		if st.Phase == hubChecking || st.Launching {
			c.strokeRoundedRect(ctaR, 3, colBorderHi)
		}

		ctaLabel := "PLAY"
		isPlay := false
		if st.Launching {
			ctaLabel = "LAUNCHING..."
		} else {
			switch st.Phase {
			case hubChecking:
				ctaLabel = "CHECKING..."
			case hubNeedsInstall:
				ctaLabel = "INSTALL " + st.LatestTag
			case hubNeedsPatch, hubNeedsFullUpdate:
				ctaLabel = "UPDATE " + st.LatestTag
			default:
				ctaLabel = "PLAY"
				isPlay = true
			}
		}
		if isPlay {
			c.drawPlayTriangle(ctaR.Min.X+72, ctaR.Min.Y+26, colWhite)
			texts = append(texts, textOp{
				text:    ctaLabel,
				rect:    image.Rect(ctaR.Min.X+90, ctaR.Min.Y+2, ctaR.Max.X-16, ctaR.Max.Y-2),
				sizePx:  20,
				bold:    true,
				display: true,
				col:     colWhite,
				align:   alignLeft,
			})
		} else {
			texts = append(texts, textOp{
				text:    ctaLabel,
				rect:    ctaR,
				sizePx:  16,
				bold:    true,
				display: true,
				col:     colWhite,
				align:   alignCenter,
			})
		}

		chkR := image.Rect(ctaR.Max.X+12, btnY+4, ctaR.Max.X+156, btnY+48)
		hits = append(hits, hitItem{id: "check", rect: chkR, cursor: true})
		chkBg := colSurfaceAlp
		chkBorder := colBorder
		if st.HoverID == "check" {
			chkBg = colElevated
			chkBorder = colBorderHi
		}
		c.fillRoundedRect(chkR, 3, chkBg)
		c.strokeRoundedRect(chkR, 3, chkBorder)
		texts = append(texts, textOp{
			text:    "CHECK UPDATES",
			rect:    chkR,
			sizePx:  12,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignCenter,
		})

		if st.HasExe && st.Phase != hubReadyToPlay && !st.Launching {
			offR := image.Rect(chkR.Max.X+10, btnY+4, chkR.Max.X+144, btnY+48)
			hits = append(hits, hitItem{id: "offline", rect: offR, cursor: true})
			offBg := colSurfaceAlp
			offBorder := colBorder
			if st.HoverID == "offline" {
				offBg = colElevated
				offBorder = colBorderHi
			}
			c.fillRoundedRect(offR, 3, offBg)
			c.strokeRoundedRect(offR, 3, offBorder)
			texts = append(texts, textOp{
				text:    "PLAY OFFLINE",
				rect:    offR,
				sizePx:  12,
				bold:    true,
				display: true,
				col:     colStone,
				align:   alignCenter,
			})
		}
	}

	if st.StatusText != "" {
		texts = append(texts, textOp{
			text:     st.StatusText,
			rect:     image.Rect(leftX, 318, hubWidth-40, 340),
			sizePx:   13,
			col:      colStone,
			align:    alignLeft,
			ellipsis: true,
		})
	}

	// Lower Editorial Strip (y: 416..636)
	stripY := 416
	stripH := 218
	leftW := 668
	leftPane := image.Rect(leftX, stripY, leftX+leftW, stripY+stripH)
	rightPane := image.Rect(leftPane.Max.X+20, stripY, hubWidth-32, stripY+stripH)

	// Left Editorial Highlights
	c.fillRoundedRect(leftPane, 3, colSurfaceAlp)
	c.strokeRoundedRect(leftPane, 3, colBorder)
	texts = append(texts, textOp{
		text:    "LATEST PATCH NOTES",
		rect:    image.Rect(leftPane.Min.X+20, leftPane.Min.Y+14, leftPane.Min.X+300, leftPane.Min.Y+36),
		sizePx:  13,
		bold:    true,
		display: true,
		col:     colIvory,
		align:   alignLeft,
	})
	viewAllR := image.Rect(leftPane.Max.X-160, leftPane.Min.Y+12, leftPane.Max.X-16, leftPane.Min.Y+38)
	hits = append(hits, hitItem{id: "open_notes", rect: viewAllR, cursor: true})
	vaCol := colBrass
	if st.HoverID == "open_notes" {
		vaCol = colIvory
	}
	texts = append(texts, textOp{
		text:    "ALL PATCH NOTES →",
		rect:    viewAllR,
		sizePx:  12,
		bold:    true,
		display: true,
		col:     vaCol,
		align:   alignRight,
	})
	c.fillRect(image.Rect(leftPane.Min.X+20, leftPane.Min.Y+42, leftPane.Max.X-20, leftPane.Min.Y+43), colBorder)

	releases := parsePatchReleases(st.NotesRaw)
	var items []patchItem
	if len(releases) > 0 {
		items = releases[0].Items
	}
	maxItems := 4
	if len(items) < maxItems {
		maxItems = len(items)
	}
	cellW := (leftPane.Dx() - 56) / 2
	cellH := 74
	for i := 0; i < maxItems; i++ {
		colIdx := i % 2
		rowIdx := i / 2
		cx := leftPane.Min.X + 20 + colIdx*(cellW+16)
		cy := leftPane.Min.Y + 54 + rowIdx*(cellH+10)
		c.fillRect(image.Rect(cx, cy+2, cx+2, cy+cellH-6), colCrimson)
		texts = append(texts,
			textOp{
				text:     strings.ToUpper(items[i].Title),
				rect:     image.Rect(cx+12, cy, cx+cellW, cy+20),
				sizePx:   12,
				bold:     true,
				display:  true,
				col:      colIvory,
				align:    alignLeft,
				ellipsis: true,
			},
			textOp{
				text:      items[i].Body,
				rect:      image.Rect(cx+12, cy+22, cx+cellW, cy+cellH),
				sizePx:    12,
				multiline: true,
				col:       colStone,
				align:     alignLeft,
			},
		)
	}

	// Right Obsidian Status & Account Card (ZERO IPs)
	c.fillRoundedRect(rightPane, 3, colSurfaceAlp)
	c.strokeRoundedRect(rightPane, 3, colBorder)
	texts = append(texts, textOp{
		text:    "CONNECTION & ACCOUNT",
		rect:    image.Rect(rightPane.Min.X+18, rightPane.Min.Y+14, rightPane.Max.X-18, rightPane.Min.Y+36),
		sizePx:  13,
		bold:    true,
		display: true,
		col:     colIvory,
		align:   alignLeft,
	})
	c.fillRect(image.Rect(rightPane.Min.X+18, rightPane.Min.Y+42, rightPane.Max.X-18, rightPane.Min.Y+43), colBorder)

	pingDot := colMuted
	pingTxt := "Offline"
	if st.PingMs > 0 {
		pingTxt = fmt.Sprintf("%d ms", st.PingMs)
		if st.PingMs < 90 {
			pingDot = colEmerald
		} else {
			pingDot = colBrass
		}
	}
	texts = append(texts,
		textOp{
			text:    "SERVER REGION",
			rect:    image.Rect(rightPane.Min.X+18, rightPane.Min.Y+54, rightPane.Max.X-18, rightPane.Min.Y+72),
			sizePx:  11,
			bold:    true,
			display: true,
			col:     colMuted,
			align:   alignLeft,
		},
		textOp{
			text:   "Manila, PH",
			rect:   image.Rect(rightPane.Min.X+18, rightPane.Min.Y+72, rightPane.Max.X-110, rightPane.Min.Y+94),
			sizePx: 14,
			bold:   true,
			col:    colIvory,
			align:  alignLeft,
		},
	)
	c.fillCircle(rightPane.Max.X-78, rightPane.Min.Y+83, 4, pingDot)
	texts = append(texts, textOp{
		text:    pingTxt,
		rect:    image.Rect(rightPane.Max.X-70, rightPane.Min.Y+72, rightPane.Max.X-18, rightPane.Min.Y+94),
		sizePx:  13,
		bold:    true,
		display: true,
		col:     pingDot,
		align:   alignRight,
	})

	c.fillRect(image.Rect(rightPane.Min.X+18, rightPane.Min.Y+104, rightPane.Max.X-18, rightPane.Min.Y+105), colBorder)

	acctSummary := "Guest session · Sign in to sync"
	if st.Profile.IsAccount && st.Profile.Username != "" {
		onlineCnt := 0
		for _, fr := range st.Friends {
			if fr.Online {
				onlineCnt++
			}
		}
		acctSummary = fmt.Sprintf("@%s · %d online", st.Profile.Username, onlineCnt)
	}
	texts = append(texts,
		textOp{
			text:    "PLAYER ACCOUNT",
			rect:    image.Rect(rightPane.Min.X+18, rightPane.Min.Y+114, rightPane.Max.X-18, rightPane.Min.Y+132),
			sizePx:  11,
			bold:    true,
			display: true,
			col:     colMuted,
			align:   alignLeft,
		},
		textOp{
			text:     acctSummary,
			rect:     image.Rect(rightPane.Min.X+18, rightPane.Min.Y+132, rightPane.Max.X-18, rightPane.Min.Y+154),
			sizePx:   13,
			bold:     st.Profile.IsAccount,
			col:      colIvory,
			align:    alignLeft,
			ellipsis: true,
		},
	)

	// Two clean footer buttons: ACCOUNT | GAME FOLDER
	btnW := (rightPane.Dx() - 46) / 2
	acctBtn := image.Rect(rightPane.Min.X+18, rightPane.Max.Y-52, rightPane.Min.X+18+btnW, rightPane.Max.Y-16)
	folderBtn := image.Rect(acctBtn.Max.X+10, rightPane.Max.Y-52, rightPane.Max.X-18, rightPane.Max.Y-16)
	hits = append(hits,
		hitItem{id: "open_account", rect: acctBtn, cursor: true},
		hitItem{id: "open_folder", rect: folderBtn, cursor: true},
	)
	abBg := colElevated
	if st.HoverID == "open_account" {
		abBg = colHoverSurf
	}
	fbBg := colElevated
	if st.HoverID == "open_folder" {
		fbBg = colHoverSurf
	}
	c.fillRoundedRect(acctBtn, 3, abBg)
	c.strokeRoundedRect(acctBtn, 3, colBorder)
	c.fillRoundedRect(folderBtn, 3, fbBg)
	c.strokeRoundedRect(folderBtn, 3, colBorder)
	acctBtnLabel := "SIGN IN"
	if st.Profile.IsAccount {
		acctBtnLabel = "FRIENDS"
	}
	texts = append(texts,
		textOp{
			text:    acctBtnLabel,
			rect:    acctBtn,
			sizePx:  12,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignCenter,
		},
		textOp{
			text:    "GAME FOLDER",
			rect:    folderBtn,
			sizePx:  12,
			bold:    true,
			display: true,
			col:     colStone,
			align:   alignCenter,
		},
	)

	return hits, texts
}

func estimateWrappedLines(s string, widthPx, avgCharPx int) int {
	if s == "" {
		return 1
	}
	if widthPx <= 0 || avgCharPx <= 0 {
		return 1
	}
	maxChars := widthPx / avgCharPx
	if maxChars < 12 {
		maxChars = 12
	}
	words := strings.Fields(s)
	if len(words) == 0 {
		return 1
	}
	lines := 1
	curLen := 0
	for _, w := range words {
		wl := len([]rune(w))
		if curLen == 0 {
			curLen = wl
		} else if curLen+1+wl <= maxChars {
			curLen += 1 + wl
		} else {
			lines++
			curLen = wl
		}
	}
	return lines
}

// renderTabNotes renders a two-pane Riot editorial Patch Notes magazine layout.
func renderTabNotes(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp, int) {
	leftX := railWidth + 32
	texts = append(texts,
		textOp{
			text:    "PATCH NOTES",
			rect:    image.Rect(leftX, 16, leftX+420, 48),
			sizePx:  24,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignLeft,
		},
		textOp{
			text:   "Updates, balance adjustments, and client improvements",
			rect:   image.Rect(leftX, 46, leftX+540, 68),
			sizePx: 13,
			col:    colStone,
			align:  alignLeft,
		},
	)

	releases := parsePatchReleases(st.NotesRaw)
	sel := st.SelectedRelease
	if sel < 0 || sel >= len(releases) {
		sel = 0
	}

	// Left Release Index Sidebar (width: 224px)
	sideR := image.Rect(railWidth+1, 73, railWidth+228, hubHeight-1)
	c.fillRect(sideR, colHeaderBar)
	c.fillRect(image.Rect(sideR.Max.X, 73, sideR.Max.X+1, hubHeight-1), colBorder)
	texts = append(texts, textOp{
		text:    "RELEASES",
		rect:    image.Rect(sideR.Min.X+22, 92, sideR.Max.X-16, 112),
		sizePx:  11,
		bold:    true,
		display: true,
		col:     colMuted,
		align:   alignLeft,
	})

	ry := 120
	for idx, rel := range releases {
		if ry+58 > hubHeight-16 {
			break
		}
		itemR := image.Rect(sideR.Min.X+12, ry, sideR.Max.X-12, ry+54)
		hitID := fmt.Sprintf("rel_%d", idx)
		hits = append(hits, hitItem{id: hitID, rect: itemR, cursor: true})
		active := idx == sel
		if active {
			c.fillRoundedRect(itemR, 3, colElevated)
			c.fillRect(image.Rect(itemR.Min.X, itemR.Min.Y+8, itemR.Min.X+3, itemR.Max.Y-8), colCrimson)
		} else if st.HoverID == hitID {
			c.fillRoundedRect(itemR, 3, color.NRGBA{20, 22, 27, 255})
		}
		vCol := colStone
		if active {
			vCol = colIvory
		}
		texts = append(texts,
			textOp{
				text:     strings.ToUpper(rel.Version),
				rect:     image.Rect(itemR.Min.X+14, itemR.Min.Y+7, itemR.Max.X-10, itemR.Min.Y+27),
				sizePx:   14,
				bold:     true,
				display:  true,
				col:      vCol,
				align:    alignLeft,
				ellipsis: true,
			},
			textOp{
				text:     rel.Title,
				rect:     image.Rect(itemR.Min.X+14, itemR.Min.Y+28, itemR.Max.X-10, itemR.Max.Y-6),
				sizePx:   12,
				col:      colMuted,
				align:    alignLeft,
				ellipsis: true,
			},
		)
		ry += 62
	}

	// Right Editorial Article Viewport (scrollable)
	artX := sideR.Max.X + 28
	artR := image.Rect(artX, 92, hubWidth-32, hubHeight-20)
	rel := releases[sel]

	type block struct {
		isHeader bool
		item     patchItem
		h        int
	}
	var blocks []block
	bannerH := 112
	blocks = append(blocks, block{isHeader: true, h: bannerH + 18})
	bodyW := artR.Dx() - 48
	for _, it := range rel.Items {
		lines := estimateWrappedLines(it.Body, bodyW, 7)
		cardH := 42 + lines*21 + 14
		blocks = append(blocks, block{item: it, h: cardH + 12})
	}

	totalH := 8
	for _, b := range blocks {
		totalH += b.h
	}
	viewH := artR.Dy()
	maxScroll := totalH - viewH
	if maxScroll < 0 {
		maxScroll = 0
	}
	scroll := st.NotesScroll
	if scroll < 0 {
		scroll = 0
	}
	if scroll > maxScroll {
		scroll = maxScroll
	}

	assets := getHubAssets()
	y := artR.Min.Y - scroll
	for _, b := range blocks {
		if b.isHeader {
			bhR := image.Rect(artR.Min.X, y, artR.Max.X-12, y+bannerH)
			if bhR.Max.Y > artR.Min.Y && bhR.Min.Y < artR.Max.Y {
				visR := bhR.Intersect(artR)
				if assets.hero != nil {
					c.blitImageRect(assets.hero, visR, image.Rect(160, 120, 960, 320))
					c.fillRect(visR, color.NRGBA{11, 12, 14, 155})
				} else {
					c.fillRoundedRect(visR, 3, colSurface)
				}
				c.strokeRoundedRect(visR, 3, colBorder)
				c.fillRect(image.Rect(visR.Min.X, visR.Min.Y, visR.Min.X+4, visR.Max.Y), colCrimson)

				meta := strings.ToUpper(rel.Version)
				if rel.Date != "" {
					meta += " · " + rel.Date
				}
				texts = append(texts,
					textOp{
						text:    meta,
						rect:    image.Rect(bhR.Min.X+22, bhR.Min.Y+16, bhR.Max.X-20, bhR.Min.Y+36),
						clip:    artR,
						sizePx:  12,
						bold:    true,
						display: true,
						col:     colCrimsonHi,
						align:   alignLeft,
					},
					textOp{
						text:     rel.Title,
						rect:     image.Rect(bhR.Min.X+22, bhR.Min.Y+40, bhR.Max.X-20, bhR.Min.Y+82),
						clip:     artR,
						sizePx:   26,
						bold:     true,
						display:  true,
						col:      colIvory,
						align:    alignLeft,
						ellipsis: true,
					},
				)
			}
			y += b.h
			continue
		}

		cardH := b.h - 12
		cr := image.Rect(artR.Min.X, y, artR.Max.X-12, y+cardH)
		if cr.Max.Y > artR.Min.Y && cr.Min.Y < artR.Max.Y {
			vis := cr.Intersect(artR)
			c.fillRoundedRect(vis, 3, colSurface)
			c.strokeRoundedRect(vis, 3, colBorder)
			c.fillRect(image.Rect(vis.Min.X, vis.Min.Y, vis.Min.X+3, vis.Max.Y), colCrimson)

			texts = append(texts,
				textOp{
					text:    strings.ToUpper(b.item.Title),
					rect:    image.Rect(cr.Min.X+20, cr.Min.Y+14, cr.Max.X-20, cr.Min.Y+38),
					clip:    artR,
					sizePx:  15,
					bold:    true,
					display: true,
					col:     colBrass,
					align:   alignLeft,
				},
				textOp{
					text:      b.item.Body,
					rect:      image.Rect(cr.Min.X+20, cr.Min.Y+42, cr.Max.X-20, cr.Max.Y-10),
					clip:      artR,
					sizePx:    14,
					multiline: true,
					col:       colIvory,
					align:     alignLeft,
				},
			)
		}
		y += b.h
	}

	if maxScroll > 0 {
		track := image.Rect(hubWidth-26, artR.Min.Y, hubWidth-21, artR.Max.Y)
		c.fillRoundedRect(track, 2, colElevated)
		thumbH := (track.Dy() * viewH) / totalH
		if thumbH < 28 {
			thumbH = 28
		}
		thumbTop := track.Min.Y + ((track.Dy()-thumbH)*scroll)/maxScroll
		c.fillRoundedRect(image.Rect(track.Min.X, thumbTop, track.Max.X, thumbTop+thumbH), 2, colMuted)
	}

	return hits, texts, maxScroll
}

func renderTabAccount(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp) {
	if !st.Profile.IsAccount {
		return renderAccountSignedOut(c, st, hits, texts)
	}
	return renderAccountSignedIn(c, st, hits, texts)
}

func renderAccountSignedOut(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp) {
	// Left obsidian column (420px wide) + right tactical pitch
	colL := image.Rect(railWidth+1, 73, railWidth+420, hubHeight-1)
	c.fillRect(colL, colHeaderBar)
	c.fillRect(image.Rect(colL.Max.X, 73, colL.Max.X+1, hubHeight-1), colBorder)

	leftX := railWidth + 36
	texts = append(texts,
		textOp{
			text:    "ACCOUNT",
			rect:    image.Rect(leftX, 16, leftX+340, 48),
			sizePx:  24,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignLeft,
		},
		textOp{
			text:   "Permanent username, friends list, and synced custom avatar",
			rect:   image.Rect(leftX, 46, leftX+480, 68),
			sizePx: 13,
			col:    colStone,
			align:  alignLeft,
		},
	)

	// Sign In / Create Account tabs
	t1R := image.Rect(leftX, 108, leftX+150, 142)
	t2R := image.Rect(leftX+160, 108, leftX+340, 142)
	hits = append(hits,
		hitItem{id: "auth_mode_login", rect: t1R, cursor: true},
		hitItem{id: "auth_mode_register", rect: t2R, cursor: true},
	)
	lCol, rCol := colStone, colStone
	if !st.AuthModeRegister {
		lCol = colIvory
		c.fillRect(image.Rect(t1R.Min.X, t1R.Max.Y-2, t1R.Max.X, t1R.Max.Y), colCrimson)
	} else {
		rCol = colIvory
		c.fillRect(image.Rect(t2R.Min.X, t2R.Max.Y-2, t2R.Max.X, t2R.Max.Y), colCrimson)
	}
	c.fillRect(image.Rect(leftX, 142, colL.Max.X-36, 143), colBorder)
	texts = append(texts,
		textOp{text: "SIGN IN", rect: t1R, sizePx: 13, bold: true, display: true, col: lCol, align: alignLeft},
		textOp{text: "CREATE ACCOUNT", rect: t2R, sizePx: 13, bold: true, display: true, col: rCol, align: alignLeft},
	)

	// Username field
	fw := colL.Dx() - 72
	uBox := image.Rect(leftX, 186, leftX+fw, 228)
	hits = append(hits, hitItem{id: "auth_user", rect: uBox, cursor: true})
	uBorder := colBorder
	if st.FocusField == "auth_user" {
		uBorder = colCrimson
	} else if st.HoverID == "auth_user" {
		uBorder = colBorderHi
	}
	c.fillRoundedRect(uBox, 3, colSurface)
	c.strokeRoundedRect(uBox, 3, uBorder)

	userDisp := st.InputUser
	userCol := colIvory
	if userDisp == "" && st.FocusField != "auth_user" {
		userDisp = "3-20 chars (letters, digits, _ or -)"
		userCol = colMuted
	} else if st.FocusField == "auth_user" && st.CaretVisible {
		userDisp += "|"
	}
	texts = append(texts,
		textOp{text: "USERNAME", rect: image.Rect(leftX, 164, leftX+fw, 182), sizePx: 11, bold: true, display: true, col: colStone, align: alignLeft},
		textOp{text: userDisp, rect: image.Rect(uBox.Min.X+12, uBox.Min.Y+2, uBox.Max.X-12, uBox.Max.Y-2), sizePx: 14, col: userCol, align: alignLeft, ellipsis: true},
	)

	// Password field
	pBox := image.Rect(leftX, 272, leftX+fw, 314)
	hits = append(hits, hitItem{id: "auth_pass", rect: pBox, cursor: true})
	pBorder := colBorder
	if st.FocusField == "auth_pass" {
		pBorder = colCrimson
	} else if st.HoverID == "auth_pass" {
		pBorder = colBorderHi
	}
	c.fillRoundedRect(pBox, 3, colSurface)
	c.strokeRoundedRect(pBox, 3, pBorder)

	passDisp := strings.Repeat("•", len([]rune(st.InputPass)))
	passCol := colIvory
	if passDisp == "" && st.FocusField != "auth_pass" {
		passDisp = "Enter password"
		passCol = colMuted
	} else if st.FocusField == "auth_pass" && st.CaretVisible {
		passDisp += "|"
	}
	texts = append(texts,
		textOp{text: "PASSWORD", rect: image.Rect(leftX, 250, leftX+fw, 268), sizePx: 11, bold: true, display: true, col: colStone, align: alignLeft},
		textOp{text: passDisp, rect: image.Rect(pBox.Min.X+12, pBox.Min.Y+2, pBox.Max.X-12, pBox.Max.Y-2), sizePx: 14, col: passCol, align: alignLeft, ellipsis: true},
	)

	// Submit button
	subR := image.Rect(leftX, 344, leftX+fw, 392)
	hits = append(hits, hitItem{id: "auth_submit", rect: subR, cursor: true})
	subCol := colCrimson
	if st.AuthBusy {
		subCol = colElevated
	} else if st.HoverID == "auth_submit" {
		subCol = colCrimsonHi
	}
	c.fillRoundedRect(subR, 3, subCol)
	subTxt := "SIGN IN"
	if st.AuthBusy {
		subTxt = "CONNECTING..."
	} else if st.AuthModeRegister {
		subTxt = "CREATE ACCOUNT"
	}
	texts = append(texts, textOp{text: subTxt, rect: subR, sizePx: 15, bold: true, display: true, col: colWhite, align: alignCenter})

	if st.AuthMessage != "" {
		msgCol := colEmerald
		if st.AuthIsError {
			msgCol = colCrimsonHi
		}
		texts = append(texts, textOp{
			text:      st.AuthMessage,
			rect:      image.Rect(leftX, 408, leftX+fw, 464),
			sizePx:    13,
			multiline: true,
			col:       msgCol,
			align:     alignLeft,
		})
	}

	guestR := image.Rect(leftX, hubHeight-76, leftX+fw, hubHeight-44)
	hits = append(hits, hitItem{id: "tab_game", rect: guestR, cursor: true})
	gCol := colStone
	if st.HoverID == "tab_game" {
		gCol = colIvory
	}
	texts = append(texts, textOp{text: "← Return to Game Hub", rect: guestR, sizePx: 13, col: gCol, align: alignLeft})

	// Right atmospheric overview panel
	rx := colL.Max.X + 56
	texts = append(texts,
		textOp{text: "COMMANDER IDENTITY", rect: image.Rect(rx, 152, rx+460, 174), sizePx: 12, bold: true, display: true, col: colCrimson, align: alignLeft},
		textOp{text: "ONE ACCOUNT ACROSS LAUNCHER & GAME", rect: image.Rect(rx, 180, rx+540, 248), sizePx: 26, bold: true, display: true, multiline: true, col: colIvory, align: alignLeft},
	)
	perks := [][2]string{
		{"PERMANENT USERNAME", "Reserve a unique commander handle across multiplayer lobbies."},
		{"ANIMATED AVATARS", "Upload PNG, JPG, or animated GIF avatars directly from the launcher."},
		{"FRIENDS & PLAYER DATABASE", "Search registered commanders, manage friend requests, and view live status."},
	}
	py := 272
	for _, pk := range perks {
		c.fillRect(image.Rect(rx, py+2, rx+3, py+46), colCrimson)
		texts = append(texts,
			textOp{text: pk[0], rect: image.Rect(rx+16, py, rx+500, py+20), sizePx: 13, bold: true, display: true, col: colIvory, align: alignLeft},
			textOp{text: pk[1], rect: image.Rect(rx+16, py+22, rx+500, py+60), sizePx: 13, multiline: true, col: colStone, align: alignLeft},
		)
		py += 76
	}
	return hits, texts
}

func renderAccountSignedIn(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp) {
	leftX := railWidth + 32
	assets := getHubAssets()

	texts = append(texts,
		textOp{text: "ACCOUNT & FRIENDS", rect: image.Rect(leftX, 16, leftX+420, 48), sizePx: 24, bold: true, display: true, col: colIvory, align: alignLeft},
		textOp{text: "Synced profile, friends roster, and player database search", rect: image.Rect(leftX, 46, leftX+560, 68), sizePx: 13, col: colStone, align: alignLeft},
	)

	// Profile Header Strip
	hdrR := image.Rect(leftX, 92, hubWidth-32, 184)
	c.fillRoundedRect(hdrR, 3, colSurface)
	c.strokeRoundedRect(hdrR, 3, colBorder)
	c.fillRect(image.Rect(hdrR.Min.X, hdrR.Min.Y, hdrR.Min.X+3, hdrR.Max.Y), colCrimson)

	avR := image.Rect(hdrR.Min.X+20, hdrR.Min.Y+14, hdrR.Min.X+84, hdrR.Min.Y+78)
	if st.Profile.Avatar != nil {
		c.blitRoundedSquare(st.Profile.Avatar, avR, 3)
	} else if assets.emblem != nil {
		c.blitScaledAlpha(assets.emblem, avR)
	}
	c.strokeRoundedRect(avR, 3, colBorderHi)

	texts = append(texts,
		textOp{text: "@" + st.Profile.Username, rect: image.Rect(avR.Max.X+18, hdrR.Min.Y+18, hdrR.Min.X+460, hdrR.Min.Y+48), sizePx: 22, bold: true, display: true, col: colIvory, align: alignLeft},
		textOp{text: "SIGNED IN · SYNCED WITH GAME CLIENT", rect: image.Rect(avR.Max.X+18, hdrR.Min.Y+50, hdrR.Min.X+460, hdrR.Min.Y+72), sizePx: 12, bold: true, display: true, col: colEmerald, align: alignLeft},
	)

	upBtn := image.Rect(hdrR.Max.X-370, hdrR.Min.Y+28, hdrR.Max.X-230, hdrR.Min.Y+64)
	refBtn := image.Rect(hdrR.Max.X-220, hdrR.Min.Y+28, hdrR.Max.X-128, hdrR.Min.Y+64)
	outBtn := image.Rect(hdrR.Max.X-118, hdrR.Min.Y+28, hdrR.Max.X-18, hdrR.Min.Y+64)
	hits = append(hits,
		hitItem{id: "upload_avatar", rect: upBtn, cursor: true},
		hitItem{id: "refresh_friends", rect: refBtn, cursor: true},
		hitItem{id: "auth_logout", rect: outBtn, cursor: true},
	)
	for _, b := range []struct {
		id, txt string
		r       image.Rectangle
		col     color.NRGBA
	}{
		{"upload_avatar", "CHANGE AVATAR", upBtn, colIvory},
		{"refresh_friends", "REFRESH", refBtn, colStone},
		{"auth_logout", "SIGN OUT", outBtn, colCrimsonHi},
	} {
		bg := colElevated
		if st.HoverID == b.id {
			bg = colHoverSurf
		}
		c.fillRoundedRect(b.r, 3, bg)
		c.strokeRoundedRect(b.r, 3, colBorder)
		texts = append(texts, textOp{text: b.txt, rect: b.r, sizePx: 12, bold: true, display: true, col: b.col, align: alignCenter})
	}

	// Split Social Grid: Left (Friends + Requests) | Right (Player Search)
	gridY := 202
	gridH := hubHeight - gridY - 22
	leftPane := image.Rect(leftX, gridY, leftX+484, gridY+gridH)
	rightPane := image.Rect(leftPane.Max.X+18, gridY, hubWidth-32, gridY+gridH)

	// Left Pane: Incoming Friend Requests + Sorted Friends List
	c.fillRoundedRect(leftPane, 3, colSurface)
	c.strokeRoundedRect(leftPane, 3, colBorder)
	texts = append(texts, textOp{
		text:    fmt.Sprintf("FRIENDS ROSTER (%d)", len(st.Friends)),
		rect:    image.Rect(leftPane.Min.X+18, leftPane.Min.Y+14, leftPane.Max.X-18, leftPane.Min.Y+36),
		sizePx:  13,
		bold:    true,
		display: true,
		col:     colIvory,
		align:   alignLeft,
	})
	c.fillRect(image.Rect(leftPane.Min.X+18, leftPane.Min.Y+42, leftPane.Max.X-18, leftPane.Min.Y+43), colBorder)

	fy := leftPane.Min.Y + 52
	for _, inc := range st.Incoming {
		if fy+44 > leftPane.Max.Y-12 {
			break
		}
		rowR := image.Rect(leftPane.Min.X+16, fy, leftPane.Max.X-16, fy+40)
		c.fillRoundedRect(rowR, 2, colElevated)
		c.fillRect(image.Rect(rowR.Min.X, rowR.Min.Y, rowR.Min.X+2, rowR.Max.Y), colBrass)
		texts = append(texts, textOp{
			text:     inc.Username + " · Request",
			rect:     image.Rect(rowR.Min.X+12, rowR.Min.Y+4, rowR.Max.X-154, rowR.Max.Y-4),
			sizePx:   13,
			bold:     true,
			col:      colIvory,
			align:    alignLeft,
			ellipsis: true,
		})
		accID := "accept_req:" + inc.Username
		decID := "decline_req:" + inc.Username
		accR := image.Rect(rowR.Max.X-146, rowR.Min.Y+6, rowR.Max.X-78, rowR.Max.Y-6)
		decR := image.Rect(rowR.Max.X-72, rowR.Min.Y+6, rowR.Max.X-8, rowR.Max.Y-6)
		hits = append(hits, hitItem{id: accID, rect: accR, cursor: true}, hitItem{id: decID, rect: decR, cursor: true})
		c.fillRoundedRect(accR, 2, colEmerald)
		c.fillRoundedRect(decR, 2, colSurface)
		c.strokeRoundedRect(decR, 2, colBorder)
		texts = append(texts,
			textOp{text: "ACCEPT", rect: accR, sizePx: 11, bold: true, display: true, col: colRail, align: alignCenter},
			textOp{text: "DECLINE", rect: decR, sizePx: 11, bold: true, display: true, col: colStone, align: alignCenter},
		)
		fy += 48
	}

	if len(st.Friends) == 0 && len(st.Incoming) == 0 {
		texts = append(texts, textOp{
			text:      "No friends yet. Search registered players on the right to send a request.",
			rect:      image.Rect(leftPane.Min.X+18, fy+8, leftPane.Max.X-18, fy+58),
			sizePx:    13,
			multiline: true,
			col:       colMuted,
			align:     alignLeft,
		})
	}
	for _, fr := range st.Friends {
		if fy+42 > leftPane.Max.Y-12 {
			break
		}
		rowR := image.Rect(leftPane.Min.X+16, fy, leftPane.Max.X-16, fy+38)
		c.fillRoundedRect(rowR, 2, colHeaderBar)
		dotC := colStone
		seenTxt := fr.LastSeenText
		if seenTxt == "" {
			seenTxt = "Offline"
		}
		if fr.Online {
			dotC = colEmerald
			seenTxt = "Online"
		}
		c.fillCircle(rowR.Min.X+14, rowR.Min.Y+19, 4, dotC)
		texts = append(texts,
			textOp{text: fr.Username, rect: image.Rect(rowR.Min.X+26, rowR.Min.Y+4, rowR.Max.X-120, rowR.Max.Y-4), sizePx: 13, bold: true, col: colIvory, align: alignLeft, ellipsis: true},
			textOp{text: seenTxt, rect: image.Rect(rowR.Max.X-116, rowR.Min.Y+4, rowR.Max.X-12, rowR.Max.Y-4), sizePx: 12, col: dotC, align: alignRight},
		)
		fy += 44
	}

	// Right Pane: Player Database Search
	c.fillRoundedRect(rightPane, 3, colSurface)
	c.strokeRoundedRect(rightPane, 3, colBorder)
	texts = append(texts, textOp{
		text:    "PLAYER DATABASE SEARCH",
		rect:    image.Rect(rightPane.Min.X+18, rightPane.Min.Y+14, rightPane.Max.X-18, rightPane.Min.Y+36),
		sizePx:  13,
		bold:    true,
		display: true,
		col:     colIvory,
		align:   alignLeft,
	})
	c.fillRect(image.Rect(rightPane.Min.X+18, rightPane.Min.Y+42, rightPane.Max.X-18, rightPane.Min.Y+43), colBorder)

	sBox := image.Rect(rightPane.Min.X+18, rightPane.Min.Y+54, rightPane.Max.X-114, rightPane.Min.Y+92)
	sBtn := image.Rect(rightPane.Max.X-106, rightPane.Min.Y+54, rightPane.Max.X-18, rightPane.Min.Y+92)
	hits = append(hits,
		hitItem{id: "friend_search", rect: sBox, cursor: true},
		hitItem{id: "do_search", rect: sBtn, cursor: true},
	)
	sBorder := colBorder
	if st.FocusField == "friend_search" {
		sBorder = colCrimson
	}
	c.fillRoundedRect(sBox, 3, colHeaderBar)
	c.strokeRoundedRect(sBox, 3, sBorder)
	sBg := colCrimson
	if st.HoverID == "do_search" {
		sBg = colCrimsonHi
	}
	c.fillRoundedRect(sBtn, 3, sBg)

	sDisp := st.InputSearch
	sCol := colIvory
	if sDisp == "" && st.FocusField != "friend_search" {
		sDisp = "Search exact or partial username..."
		sCol = colMuted
	} else if st.FocusField == "friend_search" && st.CaretVisible {
		sDisp += "|"
	}
	texts = append(texts,
		textOp{text: sDisp, rect: image.Rect(sBox.Min.X+10, sBox.Min.Y+2, sBox.Max.X-10, sBox.Max.Y-2), sizePx: 13, col: sCol, align: alignLeft, ellipsis: true},
		textOp{text: "SEARCH", rect: sBtn, sizePx: 12, bold: true, display: true, col: colWhite, align: alignCenter},
	)

	sy := rightPane.Min.Y + 106
	msgReserve := 0
	if st.AuthMessage != "" {
		msgReserve = 34
	}
	for _, u := range st.SearchResults {
		if sy+42 > rightPane.Max.Y-12-msgReserve {
			break
		}
		rowR := image.Rect(rightPane.Min.X+18, sy, rightPane.Max.X-18, sy+38)
		c.fillRoundedRect(rowR, 2, colHeaderBar)
		texts = append(texts, textOp{
			text:     u.Username,
			rect:     image.Rect(rowR.Min.X+12, rowR.Min.Y+4, rowR.Max.X-128, rowR.Max.Y-4),
			sizePx:   13,
			bold:     true,
			col:      colIvory,
			align:    alignLeft,
			ellipsis: true,
		})
		switch u.Relation {
		case "friend":
			texts = append(texts, textOp{text: "FRIENDS", rect: image.Rect(rowR.Max.X-110, rowR.Min.Y+4, rowR.Max.X-12, rowR.Max.Y-4), sizePx: 11, bold: true, display: true, col: colEmerald, align: alignRight})
		case "outgoing":
			texts = append(texts, textOp{text: "SENT", rect: image.Rect(rowR.Max.X-110, rowR.Min.Y+4, rowR.Max.X-12, rowR.Max.Y-4), sizePx: 11, bold: true, display: true, col: colStone, align: alignRight})
		case "incoming":
			accID := "accept_req:" + u.Username
			accR := image.Rect(rowR.Max.X-84, rowR.Min.Y+6, rowR.Max.X-8, rowR.Max.Y-6)
			hits = append(hits, hitItem{id: accID, rect: accR, cursor: true})
			c.fillRoundedRect(accR, 2, colEmerald)
			texts = append(texts, textOp{text: "ACCEPT", rect: accR, sizePx: 11, bold: true, display: true, col: colRail, align: alignCenter})
		default:
			addID := "add_friend:" + u.Username
			addR := image.Rect(rowR.Max.X-106, rowR.Min.Y+6, rowR.Max.X-8, rowR.Max.Y-6)
			hits = append(hits, hitItem{id: addID, rect: addR, cursor: true})
			aBg := colElevated
			if st.HoverID == addID {
				aBg = colHoverSurf
			}
			c.fillRoundedRect(addR, 2, aBg)
			c.strokeRoundedRect(addR, 2, colBorderHi)
			texts = append(texts, textOp{text: "+ ADD FRIEND", rect: addR, sizePx: 11, bold: true, display: true, col: colIvory, align: alignCenter})
		}
		sy += 44
	}

	if st.AuthMessage != "" {
		msgCol := colEmerald
		if st.AuthIsError {
			msgCol = colCrimsonHi
		}
		texts = append(texts, textOp{
			text:     st.AuthMessage,
			rect:     image.Rect(rightPane.Min.X+18, rightPane.Max.Y-36, rightPane.Max.X-18, rightPane.Max.Y-10),
			sizePx:   12,
			col:      msgCol,
			align:    alignLeft,
			ellipsis: true,
		})
	}

	return hits, texts
}

func renderTabSettings(c *canvasBuf, st hubRenderState, hits []hitItem, texts []textOp) ([]hitItem, []textOp) {
	leftX := railWidth + 32
	texts = append(texts,
		textOp{
			text:    "SETTINGS",
			rect:    image.Rect(leftX, 16, leftX+420, 48),
			sizePx:  24,
			bold:    true,
			display: true,
			col:     colIvory,
			align:   alignLeft,
		},
		textOp{
			text:   "Installation directory, release updates, account, and server status",
			rect:   image.Rect(leftX, 46, leftX+560, 68),
			sizePx: 13,
			col:    colStone,
			align:  alignLeft,
		},
	)

	verStr := st.LocalVersion
	if verStr == "" {
		if st.HasExe {
			verStr = "Installed"
		} else {
			verStr = "Not Installed"
		}
	}
	latestStr := st.LatestTag
	if latestStr == "" {
		latestStr = "Offline"
	}
	pingVal := "Manila, PH · Offline"
	if st.PingMs > 0 {
		pingVal = fmt.Sprintf("Manila, PH · Online (%d ms)", st.PingMs)
	}
	acctVal := "Guest (Sign in to sync profile & friends)"
	if st.Profile.IsAccount && st.Profile.Username != "" {
		acctVal = "@" + st.Profile.Username + " · Signed In"
	}

	rows := []struct {
		title  string
		sub    string
		btnID  string
		btnTxt string
	}{
		{"GAME INSTALLATION", st.GameDir, "open_folder", "OPEN FOLDER"},
		{"CLIENT VERSION", fmt.Sprintf("Installed: %s · Latest release: %s", verStr, latestStr), "check", "CHECK UPDATES"},
		{"SERVER REGION", pingVal, "", ""},
		{"ACCOUNT", acctVal, "open_account", "MANAGE ACCOUNT"},
		{"DIRECT LAUNCH", "Start installed game client without checking remote updates", "offline", "LAUNCH GAME"},
	}

	y := 96
	for _, sc := range rows {
		cr := image.Rect(leftX, y, hubWidth-32, y+88)
		c.fillRoundedRect(cr, 3, colSurface)
		c.strokeRoundedRect(cr, 3, colBorder)
		c.fillRect(image.Rect(cr.Min.X, cr.Min.Y+16, cr.Min.X+3, cr.Max.Y-16), colBorderHi)
		texts = append(texts,
			textOp{
				text:    sc.title,
				rect:    image.Rect(cr.Min.X+20, cr.Min.Y+16, cr.Max.X-200, cr.Min.Y+38),
				sizePx:  13,
				bold:    true,
				display: true,
				col:     colIvory,
				align:   alignLeft,
			},
			textOp{
				text:     sc.sub,
				rect:     image.Rect(cr.Min.X+20, cr.Min.Y+44, cr.Max.X-200, cr.Min.Y+68),
				sizePx:   13,
				col:      colStone,
				align:    alignLeft,
				ellipsis: true,
			},
		)
		if sc.btnID != "" {
			br := image.Rect(cr.Max.X-166, cr.Min.Y+24, cr.Max.X-20, cr.Min.Y+64)
			disabled := sc.btnID == "offline" && !st.HasExe
			if !disabled {
				hits = append(hits, hitItem{id: sc.btnID, rect: br, cursor: true})
			}
			bBg := colElevated
			if disabled {
				bBg = colHeaderBar
			} else if st.HoverID == sc.btnID {
				bBg = colHoverSurf
			}
			c.fillRoundedRect(br, 3, bBg)
			c.strokeRoundedRect(br, 3, colBorder)
			tCol := colIvory
			if disabled {
				tCol = colMuted
			}
			texts = append(texts, textOp{
				text:    sc.btnTxt,
				rect:    br,
				sizePx:  12,
				bold:    true,
				display: true,
				col:     tCol,
				align:   alignCenter,
			})
		}
		y += 102
	}
	return hits, texts
}

// Software 2D pixel buffer helpers (direct BGRA/NRGBA rendering with zero heap churn).
type canvasBuf struct {
	pix    []byte
	w, h   int
	stride int
	bgra   bool
}

func (c *canvasBuf) blendPx(x, y int, col color.NRGBA) {
	if x < 0 || x >= c.w || y < 0 || y >= c.h || col.A == 0 {
		return
	}
	off := y*c.stride + x*4
	if off+3 >= len(c.pix) {
		return
	}
	a := uint32(col.A)
	var rIdx, bIdx int
	if c.bgra {
		bIdx, rIdx = 0, 2
	} else {
		rIdx, bIdx = 0, 2
	}
	if a == 255 {
		c.pix[off+rIdx] = col.R
		c.pix[off+1] = col.G
		c.pix[off+bIdx] = col.B
		c.pix[off+3] = 255
		return
	}
	inv := 255 - a
	c.pix[off+rIdx] = uint8((uint32(col.R)*a + uint32(c.pix[off+rIdx])*inv) / 255)
	c.pix[off+1] = uint8((uint32(col.G)*a + uint32(c.pix[off+1])*inv) / 255)
	c.pix[off+bIdx] = uint8((uint32(col.B)*a + uint32(c.pix[off+bIdx])*inv) / 255)
	c.pix[off+3] = 255
}

func (c *canvasBuf) fillRect(r image.Rectangle, col color.NRGBA) {
	r = r.Intersect(image.Rect(0, 0, c.w, c.h))
	if r.Empty() {
		return
	}
	for y := r.Min.Y; y < r.Max.Y; y++ {
		for x := r.Min.X; x < r.Max.X; x++ {
			c.blendPx(x, y, col)
		}
	}
}

func (c *canvasBuf) strokeRect(r image.Rectangle, col color.NRGBA) {
	c.fillRect(image.Rect(r.Min.X, r.Min.Y, r.Max.X, r.Min.Y+1), col)
	c.fillRect(image.Rect(r.Min.X, r.Max.Y-1, r.Max.X, r.Max.Y), col)
	c.fillRect(image.Rect(r.Min.X, r.Min.Y, r.Min.X+1, r.Max.Y), col)
	c.fillRect(image.Rect(r.Max.X-1, r.Min.Y, r.Max.X, r.Max.Y), col)
}

func roundedRectAlpha(dx, dy, rad float64) uint8 {
	if dx <= 0 && dy <= 0 {
		return 255
	}
	if dx < 0 {
		dx = 0
	}
	if dy < 0 {
		dy = 0
	}
	dist := math.Hypot(dx, dy)
	diff := rad - dist
	if diff >= 0.7 {
		return 255
	}
	if diff <= -0.7 {
		return 0
	}
	return uint8(((diff + 0.7) / 1.4) * 255.0)
}

func (c *canvasBuf) fillRoundedRect(r image.Rectangle, rad int, col color.NRGBA) {
	r = r.Intersect(image.Rect(0, 0, c.w, c.h))
	if r.Empty() {
		return
	}
	fr := float64(rad)
	cx0 := float64(r.Min.X) + fr
	cy0 := float64(r.Min.Y) + fr
	cx1 := float64(r.Max.X-1) - fr
	cy1 := float64(r.Max.Y-1) - fr
	for y := r.Min.Y; y < r.Max.Y; y++ {
		dy := 0.0
		if float64(y) < cy0 {
			dy = cy0 - float64(y)
		} else if float64(y) > cy1 {
			dy = float64(y) - cy1
		}
		for x := r.Min.X; x < r.Max.X; x++ {
			dx := 0.0
			if float64(x) < cx0 {
				dx = cx0 - float64(x)
			} else if float64(x) > cx1 {
				dx = float64(x) - cx1
			}
			aa := roundedRectAlpha(dx, dy, fr)
			if aa == 0 {
				continue
			}
			pc := col
			pc.A = uint8((uint32(col.A) * uint32(aa)) / 255)
			c.blendPx(x, y, pc)
		}
	}
}

func (c *canvasBuf) strokeRoundedRect(r image.Rectangle, rad int, col color.NRGBA) {
	if rad <= 2 {
		c.strokeRect(r, col)
		return
	}
	fr := float64(rad)
	cx0 := float64(r.Min.X) + fr
	cy0 := float64(r.Min.Y) + fr
	cx1 := float64(r.Max.X-1) - fr
	cy1 := float64(r.Max.Y-1) - fr
	for y := r.Min.Y; y < r.Max.Y; y++ {
		dy := 0.0
		if float64(y) < cy0 {
			dy = cy0 - float64(y)
		} else if float64(y) > cy1 {
			dy = float64(y) - cy1
		}
		for x := r.Min.X; x < r.Max.X; x++ {
			dx := 0.0
			if float64(x) < cx0 {
				dx = cx0 - float64(x)
			} else if float64(x) > cx1 {
				dx = float64(x) - cx1
			}
			if dx <= 0 && dy <= 0 {
				continue
			}
			dist := math.Hypot(dx, dy)
			ring := 1.0 - math.Abs(dist-(fr-0.5))
			if ring <= 0 {
				continue
			}
			if ring > 1 {
				ring = 1
			}
			pc := col
			pc.A = uint8(float64(col.A) * ring)
			c.blendPx(x, y, pc)
		}
	}
}

func (c *canvasBuf) fillCircle(cx, cy, r int, col color.NRGBA) {
	fr := float64(r)
	for y := cy - r - 1; y <= cy+r+1; y++ {
		for x := cx - r - 1; x <= cx+r+1; x++ {
			d := math.Hypot(float64(x-cx), float64(y-cy))
			cov := fr - d + 0.5
			if cov <= 0 {
				continue
			}
			if cov > 1 {
				cov = 1
			}
			pc := col
			pc.A = uint8(float64(col.A) * cov)
			c.blendPx(x, y, pc)
		}
	}
}

func (c *canvasBuf) drawThickLine(x0, y0, x1, y1 int, halfW float64, col color.NRGBA) {
	minX, maxX := x0, x1
	if x1 < x0 {
		minX, maxX = x1, x0
	}
	minY, maxY := y0, y1
	if y1 < y0 {
		minY, maxY = y1, y0
	}
	pad := int(math.Ceil(halfW)) + 1
	vx, vy := float64(x1-x0), float64(y1-y0)
	vLen2 := vx*vx + vy*vy
	for y := minY - pad; y <= maxY+pad; y++ {
		for x := minX - pad; x <= maxX+pad; x++ {
			t := 0.0
			if vLen2 > 0 {
				t = ((float64(x-x0))*vx + (float64(y-y0))*vy) / vLen2
				if t < 0 {
					t = 0
				} else if t > 1 {
					t = 1
				}
			}
			px := float64(x0) + t*vx
			py := float64(y0) + t*vy
			d := math.Hypot(float64(x)-px, float64(y)-py)
			cov := (halfW - d) + 0.5
			if cov <= 0 {
				continue
			}
			if cov > 1 {
				cov = 1
			}
			pc := col
			pc.A = uint8(float64(col.A) * cov)
			c.blendPx(x, y, pc)
		}
	}
}

func (c *canvasBuf) blitImage(src image.Image, dstRect image.Rectangle) {
	c.blitImageRect(src, dstRect, src.Bounds())
}

func (c *canvasBuf) blitImageRect(src image.Image, dstRect, srcRect image.Rectangle) {
	sb := srcRect.Intersect(src.Bounds())
	dw := dstRect.Dx()
	dh := dstRect.Dy()
	if dw <= 0 || dh <= 0 || sb.Dx() <= 0 || sb.Dy() <= 0 {
		return
	}
	for y := 0; y < dh; y++ {
		sy := sb.Min.Y + (y*sb.Dy())/dh
		for x := 0; x < dw; x++ {
			sx := sb.Min.X + (x*sb.Dx())/dw
			sc := color.NRGBAModel.Convert(src.At(sx, sy)).(color.NRGBA)
			c.blendPx(dstRect.Min.X+x, dstRect.Min.Y+y, sc)
		}
	}
}

func (c *canvasBuf) blitScaledAlpha(src image.Image, dstRect image.Rectangle) {
	c.blitImage(src, dstRect)
}

func (c *canvasBuf) blitRoundedSquare(src image.Image, dstRect image.Rectangle, rad int) {
	sb := src.Bounds()
	dw := dstRect.Dx()
	dh := dstRect.Dy()
	if dw <= 0 || dh <= 0 {
		return
	}
	fr := float64(rad)
	cx0 := float64(dstRect.Min.X) + fr
	cy0 := float64(dstRect.Min.Y) + fr
	cx1 := float64(dstRect.Max.X-1) - fr
	cy1 := float64(dstRect.Max.Y-1) - fr
	for y := dstRect.Min.Y; y < dstRect.Max.Y; y++ {
		dy := 0.0
		if float64(y) < cy0 {
			dy = cy0 - float64(y)
		} else if float64(y) > cy1 {
			dy = float64(y) - cy1
		}
		sy := sb.Min.Y + ((y-dstRect.Min.Y)*sb.Dy())/dh
		for x := dstRect.Min.X; x < dstRect.Max.X; x++ {
			dx := 0.0
			if float64(x) < cx0 {
				dx = cx0 - float64(x)
			} else if float64(x) > cx1 {
				dx = float64(x) - cx1
			}
			aa := roundedRectAlpha(dx, dy, fr)
			if aa == 0 {
				continue
			}
			sx := sb.Min.X + ((x-dstRect.Min.X)*sb.Dx())/dw
			sc := color.NRGBAModel.Convert(src.At(sx, sy)).(color.NRGBA)
			sc.A = uint8((uint32(sc.A) * uint32(aa)) / 255)
			c.blendPx(x, y, sc)
		}
	}
}

func (c *canvasBuf) drawIconGlobeTarget(cx, cy int, col color.NRGBA) {
	c.strokeRoundedRect(image.Rect(cx-8, cy-8, cx+8, cy+8), 8, col)
	c.fillRect(image.Rect(cx-10, cy, cx-5, cy+1), col)
	c.fillRect(image.Rect(cx+6, cy, cx+11, cy+1), col)
	c.fillRect(image.Rect(cx, cy-10, cx+1, cy-5), col)
	c.fillRect(image.Rect(cx, cy+6, cx+1, cy+11), col)
	c.fillCircle(cx, cy, 2, col)
}

func (c *canvasBuf) drawIconNotes(cx, cy int, col color.NRGBA) {
	c.strokeRect(image.Rect(cx-7, cy-8, cx+8, cy+9), col)
	c.fillRect(image.Rect(cx-4, cy-4, cx+5, cy-2), col)
	c.fillRect(image.Rect(cx-4, cy, cx+5, cy+2), col)
	c.fillRect(image.Rect(cx-4, cy+4, cx+2, cy+6), col)
}

func (c *canvasBuf) drawIconAccount(cx, cy int, col color.NRGBA) {
	c.fillCircle(cx, cy-4, 3, col)
	c.fillRoundedRect(image.Rect(cx-7, cy+2, cx+8, cy+9), 3, col)
}

func (c *canvasBuf) drawIconGear(cx, cy int, col color.NRGBA) {
	c.strokeRoundedRect(image.Rect(cx-5, cy-5, cx+6, cy+6), 5, col)
	c.fillRect(image.Rect(cx-1, cy-9, cx+2, cy-5), col)
	c.fillRect(image.Rect(cx-1, cy+6, cx+2, cy+10), col)
	c.fillRect(image.Rect(cx-9, cy-1, cx-5, cy+2), col)
	c.fillRect(image.Rect(cx+6, cy-1, cx+10, cy+2), col)
	c.fillCircle(cx, cy, 2, col)
}

func (c *canvasBuf) drawIconClose(cx, cy int, col color.NRGBA) {
	c.drawThickLine(cx-5, cy-5, cx+5, cy+5, 0.85, col)
	c.drawThickLine(cx-5, cy+5, cx+5, cy-5, 0.85, col)
}

func (c *canvasBuf) drawPlayTriangle(cx, cy int, col color.NRGBA) {
	for dy := -7; dy <= 7; dy++ {
		w := 11 - (int(math.Abs(float64(dy)))*11)/7
		c.fillRect(image.Rect(cx-4, cy+dy, cx-4+w, cy+dy+1), col)
	}
}
