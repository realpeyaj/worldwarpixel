//go:build windows

package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"image"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	dwmapi   = syscall.NewLazyDLL("dwmapi.dll")
	comdlg32 = syscall.NewLazyDLL("comdlg32.dll")

	procCreateMutexW        = kernel32.NewProc("CreateMutexW")
	procCloseHandle         = kernel32.NewProc("CloseHandle")
	procGetModuleHandleW    = kernel32.NewProc("GetModuleHandleW")
	procGetCurrentThreadId  = kernel32.NewProc("GetCurrentThreadId")
	procGlobalLock          = kernel32.NewProc("GlobalLock")
	procGlobalUnlock        = kernel32.NewProc("GlobalUnlock")

	procGetStockObject    = gdi32.NewProc("GetStockObject")
	procCreateCompatibleDC = gdi32.NewProc("CreateCompatibleDC")
	procDeleteDC          = gdi32.NewProc("DeleteDC")
	procCreateDIBSection  = gdi32.NewProc("CreateDIBSection")
	procSelectObject      = gdi32.NewProc("SelectObject")
	procDeleteObject      = gdi32.NewProc("DeleteObject")
	procBitBlt            = gdi32.NewProc("BitBlt")
	procCreateFontW       = gdi32.NewProc("CreateFontW")
	procSetBkMode         = gdi32.NewProc("SetBkMode")
	procSetTextColor      = gdi32.NewProc("SetTextColor")
	procSaveDC            = gdi32.NewProc("SaveDC")
	procRestoreDC         = gdi32.NewProc("RestoreDC")
	procIntersectClipRect = gdi32.NewProc("IntersectClipRect")

	procMessageBoxW             = user32.NewProc("MessageBoxW")
	procRegisterClassExW        = user32.NewProc("RegisterClassExW")
	procCreateWindowExW         = user32.NewProc("CreateWindowExW")
	procDestroyWindow           = user32.NewProc("DestroyWindow")
	procDefWindowProcW          = user32.NewProc("DefWindowProcW")
	procGetMessageW             = user32.NewProc("GetMessageW")
	procTranslateMessage        = user32.NewProc("TranslateMessage")
	procDispatchMessageW        = user32.NewProc("DispatchMessageW")
	procPostMessageW            = user32.NewProc("PostMessageW")
	procPostQuitMessage         = user32.NewProc("PostQuitMessage")
	procLoadIconW               = user32.NewProc("LoadIconW")
	procLoadCursorW             = user32.NewProc("LoadCursorW")
	procSetCursor               = user32.NewProc("SetCursor")
	procGetSystemMetrics        = user32.NewProc("GetSystemMetrics")
	procSetWindowTextW          = user32.NewProc("SetWindowTextW")
	procSendMessageW            = user32.NewProc("SendMessageW")
	procGetClientRect           = user32.NewProc("GetClientRect")
	procBeginPaint              = user32.NewProc("BeginPaint")
	procEndPaint                = user32.NewProc("EndPaint")
	procInvalidateRect          = user32.NewProc("InvalidateRect")
	procDrawTextW               = user32.NewProc("DrawTextW")
	procShowWindow              = user32.NewProc("ShowWindow")
	procScreenToClient          = user32.NewProc("ScreenToClient")
	procTrackMouseEvent         = user32.NewProc("TrackMouseEvent")
	procSetCapture              = user32.NewProc("SetCapture")
	procReleaseCapture          = user32.NewProc("ReleaseCapture")
	procSetTimer                = user32.NewProc("SetTimer")
	procKillTimer               = user32.NewProc("KillTimer")
	procGetKeyState             = user32.NewProc("GetKeyState")
	procOpenClipboard           = user32.NewProc("OpenClipboard")
	procGetClipboardData        = user32.NewProc("GetClipboardData")
	procCloseClipboard          = user32.NewProc("CloseClipboard")
	procAllowSetForegroundWin   = user32.NewProc("AllowSetForegroundWindow")
	procEnumWindows             = user32.NewProc("EnumWindows")
	procGetWindowThreadProcId   = user32.NewProc("GetWindowThreadProcessId")
	procIsWindowVisible         = user32.NewProc("IsWindowVisible")
	procIsIconic                = user32.NewProc("IsIconic")
	procSetForegroundWindow     = user32.NewProc("SetForegroundWindow")
	procBringWindowToTop        = user32.NewProc("BringWindowToTop")
	procGetForegroundWindow     = user32.NewProc("GetForegroundWindow")
	procAttachThreadInput       = user32.NewProc("AttachThreadInput")

	procDwmSetWindowAttribute        = dwmapi.NewProc("DwmSetWindowAttribute")
	procDwmExtendFrameIntoClientArea = dwmapi.NewProc("DwmExtendFrameIntoClientArea")
	procGetOpenFileNameW             = comdlg32.NewProc("GetOpenFileNameW")
)

const (
	errorAlreadyExists = 183

	mbOK        = 0x00000000
	mbIconError = 0x00000010

	wsChild       = 0x40000000
	wsVisible     = 0x10000000
	wsPopup       = 0x80000000
	wsOverlapped  = 0x00000000
	wsCaption     = 0x00C00000
	wsMinimizeBox = 0x00020000

	ssLeft     = 0x00000000
	ssNoPrefix = 0x00000080

	wmDestroy     = 0x0002
	wmPaint       = 0x000F
	wmClose       = 0x0010
	wmEraseBkgnd  = 0x0014
	wmSetFont     = 0x0030
	wmNCHitTest   = 0x0084
	wmKeyDown     = 0x0100
	wmChar        = 0x0102
	wmTimer       = 0x0113
	wmMouseMove   = 0x0200
	wmLButtonDown = 0x0201
	wmLButtonUp   = 0x0202
	wmMouseWheel  = 0x020A
	wmMouseLeave  = 0x02A3
	wmAppStatus   = 0x8001
	wmAppClose    = 0x8002
	wmHubState    = 0x8003

	htClient  = 1
	htCaption = 2

	idcArrow       = 32512
	idcHand        = 32649
	colorBtnFace   = 15
	defaultGUIFont = 17
	smCXScreen     = 0
	smCYScreen     = 1
	swShow         = 5
	swMinimize     = 6
	swRestore      = 9
	srcCopy        = 0x00CC0020
	transparentBk  = 1
	tmeLeave       = 0x00000002

	vkControl     = 0x11
	vkEscape      = 0x1B
	cfUnicodeText = 13

	dtTop         = 0x00000000
	dtLeft        = 0x00000000
	dtCenter      = 0x00000001
	dtRight       = 0x00000002
	dtVCenter     = 0x00000004
	dtWordBreak   = 0x00000010
	dtSingleLine  = 0x00000020
	dtNoPrefix    = 0x00000800
	dtEndEllipsis = 0x00008000

	dwmwaDarkMode   = 20
	dwmwaCornerPref = 33
	dwmwcpRound     = 2

	caretTimerID = 101

	ofnPathMustExist = 0x00000800
	ofnFileMustExist = 0x00001000
	ofnNoChangeDir   = 0x00000008
	ofnExplorer      = 0x00080000
)

type wndClassExW struct {
	cbSize        uint32
	style         uint32
	lpfnWndProc   uintptr
	cbClsExtra    int32
	cbWndExtra    int32
	hInstance     uintptr
	hIcon         uintptr
	hCursor       uintptr
	hbrBackground uintptr
	lpszMenuName  *uint16
	lpszClassName *uint16
	hIconSm       uintptr
}

type rect struct {
	left   int32
	top    int32
	right  int32
	bottom int32
}

type point struct {
	x int32
	y int32
}

type winMsg struct {
	hwnd    uintptr
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	pt      point
}

type paintStruct struct {
	hdc         uintptr
	fErase      int32
	rcPaint     rect
	fRestore    int32
	fIncUpdate  int32
	rgbReserved [32]byte
}

type bitmapInfoHeader struct {
	biSize          uint32
	biWidth         int32
	biHeight        int32
	biPlanes        uint16
	biBitCount      uint16
	biCompression   uint32
	biSizeImage     uint32
	biXPelsPerMeter int32
	biYPelsPerMeter int32
	biClrUsed       uint32
	biClrImportant  uint32
}

type bitmapInfo struct {
	bmiHeader bitmapInfoHeader
	bmiColors [1]uint32
}

type trackMouseEventStruct struct {
	cbSize      uint32
	dwFlags     uint32
	hwndTrack   uintptr
	dwHoverTime uint32
}

type dwmMargins struct {
	left, right, top, bottom int32
}

type openFileNameW struct {
	lStructSize       uint32
	hwndOwner         uintptr
	hInstance         uintptr
	lpstrFilter       *uint16
	lpstrCustomFilter *uint16
	nMaxCustFilter    uint32
	nFilterIndex      uint32
	lpstrFile         *uint16
	nMaxFile          uint32
	lpstrFileTitle    *uint16
	nMaxFileTitle     uint32
	lpstrInitialDir   *uint16
	lpstrTitle        *uint16
	flags             uint32
	nFileOffset       uint16
	nFileExtension    uint16
	lpstrDefExt       *uint16
	lCustData         uintptr
	lpfnHook          uintptr
	lpTemplateName    *uint16
	pvReserved        uintptr
	dwReserved        uint32
	flagsEx           uint32
}

var (
	progressWindows sync.Map
	wndProcCallback = syscall.NewCallback(progressWndProc)
	hubWindows      sync.Map
	hubProcCb       = syscall.NewCallback(hubWndProc)

	enumTargetMu    sync.Mutex
	enumTargetPID   uint32
	enumFoundHwnd   uintptr
	enumWindowsCb   = syscall.NewCallback(enumWindowsProc)
)

func enumWindowsProc(hwnd uintptr, _ uintptr) uintptr {
	vis, _, _ := procIsWindowVisible.Call(hwnd)
	if vis == 0 {
		return 1
	}
	var pid uint32
	procGetWindowThreadProcId.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid == enumTargetPID && enumTargetPID != 0 {
		enumFoundHwnd = hwnd
		return 0
	}
	return 1
}

// acquireSingleInstance creates a per-session named mutex to prevent concurrent updates.
func acquireSingleInstance() (func(), bool) {
	namePtr, err := syscall.UTF16PtrFromString(`Local\WorldWarPixelLauncher`)
	if err != nil {
		return func() {}, true
	}
	handle, _, callErr := procCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(namePtr)))
	if handle == 0 {
		return func() {}, true
	}
	if errno, ok := callErr.(syscall.Errno); ok && errno == errorAlreadyExists {
		procCloseHandle.Call(handle)
		return nil, false
	}
	var once sync.Once
	return func() {
		once.Do(func() {
			procCloseHandle.Call(handle)
		})
	}, true
}

// showErrorBox displays a native Windows modal error dialog.
func showErrorBox(title, message string) {
	titlePtr, _ := syscall.UTF16PtrFromString(title)
	msgPtr, _ := syscall.UTF16PtrFromString(message)
	procMessageBoxW.Call(
		0,
		uintptr(unsafe.Pointer(msgPtr)),
		uintptr(unsafe.Pointer(titlePtr)),
		mbOK|mbIconError,
	)
}

// ---------- Direct-mode minimal progress popup (--wait / CLI) ----------

type winProgressWindow struct {
	mu      sync.Mutex
	status  string
	shown   bool
	closed  bool
	hwnd    uintptr
	hStatic uintptr
	doneCh  chan struct{}
}

func newProgressUI() progressUI {
	return &winProgressWindow{}
}

func (w *winProgressWindow) Show(status string) {
	w.mu.Lock()
	if w.shown || w.closed {
		w.status = status
		hwnd := w.hwnd
		w.mu.Unlock()
		if hwnd != 0 {
			procPostMessageW.Call(hwnd, wmAppStatus, 0, 0)
		}
		return
	}
	w.shown = true
	w.status = status
	w.doneCh = make(chan struct{})
	readyCh := make(chan uintptr, 1)
	w.mu.Unlock()

	go w.runLoop(readyCh)
	<-readyCh
}

func (w *winProgressWindow) SetStatus(status string) {
	w.mu.Lock()
	w.status = status
	hwnd := w.hwnd
	closed := w.closed
	w.mu.Unlock()
	if hwnd != 0 && !closed {
		procPostMessageW.Call(hwnd, wmAppStatus, 0, 0)
	}
}

func (w *winProgressWindow) Close() {
	w.mu.Lock()
	if w.closed || !w.shown {
		w.closed = true
		w.mu.Unlock()
		return
	}
	w.closed = true
	hwnd := w.hwnd
	doneCh := w.doneCh
	w.mu.Unlock()

	if hwnd != 0 {
		procPostMessageW.Call(hwnd, wmAppClose, 0, 0)
	}
	if doneCh != nil {
		<-doneCh
	}
}

func (w *winProgressWindow) currentStatus() string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.status
}

func (w *winProgressWindow) runLoop(readyCh chan<- uintptr) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	defer close(w.doneCh)

	hInstance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("WorldWarPixelProgressClass")
	titlePtr, _ := syscall.UTF16PtrFromString("World War Pixel")
	staticClass, _ := syscall.UTF16PtrFromString("STATIC")
	initialPtr, _ := syscall.UTF16PtrFromString(w.currentStatus())
	hIcon, _, _ := procLoadIconW.Call(hInstance, 1)
	cursor, _, _ := procLoadCursorW.Call(0, idcArrow)

	wc := wndClassExW{
		cbSize:        uint32(unsafe.Sizeof(wndClassExW{})),
		lpfnWndProc:   wndProcCallback,
		hInstance:     hInstance,
		hIcon:         hIcon,
		hCursor:       cursor,
		hbrBackground: colorBtnFace + 1,
		lpszClassName: className,
		hIconSm:       hIcon,
	}
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))

	const winW, winH = 440, 110
	screenW, _, _ := procGetSystemMetrics.Call(smCXScreen)
	screenH, _, _ := procGetSystemMetrics.Call(smCYScreen)
	posX := (int(screenW) - winW) / 2
	posY := (int(screenH) - winH) / 2
	if posX < 0 {
		posX = 100
	}
	if posY < 0 {
		posY = 100
	}

	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(titlePtr)),
		wsOverlapped|wsCaption|wsVisible,
		uintptr(posX),
		uintptr(posY),
		winW,
		winH,
		0,
		0,
		hInstance,
		0,
	)
	if hwnd == 0 {
		readyCh <- 0
		return
	}

	var cr rect
	procGetClientRect.Call(hwnd, uintptr(unsafe.Pointer(&cr)))
	clientW := int(cr.right - cr.left)
	clientH := int(cr.bottom - cr.top)
	if clientW < 100 {
		clientW = 420
	}
	if clientH < 40 {
		clientH = 70
	}

	hStatic, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(staticClass)),
		uintptr(unsafe.Pointer(initialPtr)),
		wsChild|wsVisible|ssLeft|ssNoPrefix,
		18,
		18,
		uintptr(clientW-36),
		uintptr(clientH-30),
		hwnd,
		0,
		hInstance,
		0,
	)
	if hStatic != 0 {
		hFont, _, _ := procGetStockObject.Call(defaultGUIFont)
		if hFont != 0 {
			procSendMessageW.Call(hStatic, wmSetFont, hFont, 1)
		}
	}

	w.mu.Lock()
	w.hwnd = hwnd
	w.hStatic = hStatic
	alreadyClosed := w.closed
	w.mu.Unlock()

	progressWindows.Store(hwnd, w)
	readyCh <- hwnd

	if alreadyClosed {
		procPostMessageW.Call(hwnd, wmAppClose, 0, 0)
	}

	var m winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
	progressWindows.Delete(hwnd)
}

func progressWndProc(hwnd uintptr, uMsg uint32, wParam, lParam uintptr) uintptr {
	switch uMsg {
	case wmAppStatus:
		if v, ok := progressWindows.Load(hwnd); ok {
			w := v.(*winProgressWindow)
			if w.hStatic != 0 {
				ptr, err := syscall.UTF16PtrFromString(w.currentStatus())
				if err == nil {
					procSetWindowTextW.Call(w.hStatic, uintptr(unsafe.Pointer(ptr)))
				}
			}
		}
		return 0
	case wmAppClose:
		procDestroyWindow.Call(hwnd)
		return 0
	case wmClose:
		return 0
	case wmDestroy:
		procPostQuitMessage.Call(0)
		return 0
	default:
		ret, _, _ := procDefWindowProcW.Call(hwnd, uintptr(uMsg), wParam, lParam)
		return ret
	}
}

// ---------- Riot Tactical Editorial Frameless Double-Buffered Hub ----------

type hubWindow struct {
	cfg      launcherConfig
	userDir  string
	acctAPI  *accountAPIClient
	mu       sync.Mutex
	tab      hubTab
	phase    hubPhase
	plan     updatePlan
	status   string
	notes    string
	progTxt  string
	progPct  int
	scroll   int
	maxScrl  int
	selRel   int
	pingMs   int
	prof     localProfile
	hasExe   bool
	busy     bool
	launching bool

	authRegister bool
	focusField   string
	caretVisible bool
	inputUser        string
	inputPass        string
	inputPassConfirm string
	showPassword     bool
	inputSearch      string
	authBusy     bool
	authMessage  string
	authIsError  bool
	friends      []apiUserProfile
	incoming     []apiUserProfile
	searchRes    []apiUserProfile

	hoverID  string
	pressID  string
	tracking bool
	hits     []hitItem

	hwnd    uintptr
	memDC   uintptr
	dibBmp  uintptr
	dibBits []byte
	fonts   map[uint32]uintptr
	arrowC  uintptr
	handC   uintptr
}

func runLauncherHub(cfg launcherConfig) int {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	hInstance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("WorldWarPixelRiotHubClass")
	titlePtr, _ := syscall.UTF16PtrFromString("World War Pixel")
	hIcon, _, _ := procLoadIconW.Call(hInstance, 1)
	arrowC, _, _ := procLoadCursorW.Call(0, idcArrow)
	handC, _, _ := procLoadCursorW.Call(0, idcHand)

	wc := wndClassExW{
		cbSize:        uint32(unsafe.Sizeof(wndClassExW{})),
		lpfnWndProc:   hubProcCb,
		hInstance:     hInstance,
		hIcon:         hIcon,
		hCursor:       arrowC,
		lpszClassName: className,
		hIconSm:       hIcon,
	}
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc)))

	screenW, _, _ := procGetSystemMetrics.Call(smCXScreen)
	screenH, _, _ := procGetSystemMetrics.Call(smCYScreen)
	posX := (int(screenW) - hubWidth) / 2
	posY := (int(screenH) - hubHeight) / 2
	if posX < 24 {
		posX = 24
	}
	if posY < 24 {
		posY = 24
	}

	userDir := resolveGodotUserDir()
	hasExe := fileExists(filepath.Join(cfg.GameDir, clientExeName))
	localVer := readLocalVersion(filepath.Join(cfg.GameDir, versionFileName))
	if localVer == "" && hasExe {
		localVer = "installed"
	}

	h := &hubWindow{
		cfg:          cfg,
		userDir:      userDir,
		acctAPI:      newAccountAPIClient("", nil),
		tab:          tabGame,
		phase:        hubChecking,
		status:       "Checking releases...",
		notes:        formatPatchNotes(nil, cfg.GameDir, cfg.ExeDir),
		progTxt:      "Checking updates...",
		pingMs:       -1,
		prof:         loadLocalGodotProfile(userDir),
		hasExe:       hasExe,
		caretVisible: true,
		fonts:        make(map[uint32]uintptr),
		arrowC:       arrowC,
		handC:        handC,
	}
	if localVer != "" {
		h.status = fmt.Sprintf("Installed %s · Checking updates...", localVer)
	}

	memDC, _, _ := procCreateCompatibleDC.Call(0)
	bmi := bitmapInfo{
		bmiHeader: bitmapInfoHeader{
			biSize:        uint32(unsafe.Sizeof(bitmapInfoHeader{})),
			biWidth:       hubWidth,
			biHeight:      -hubHeight, // top-down BGRA
			biPlanes:      1,
			biBitCount:    32,
			biCompression: 0,
		},
	}
	var bitsPtr unsafe.Pointer
	dibBmp, _, _ := procCreateDIBSection.Call(memDC, uintptr(unsafe.Pointer(&bmi)), 0, uintptr(unsafe.Pointer(&bitsPtr)), 0, 0)
	if dibBmp == 0 || bitsPtr == nil {
		if memDC != 0 {
			procDeleteDC.Call(memDC)
		}
		return launchGameClient(cfg)
	}
	oldBmp, _, _ := procSelectObject.Call(memDC, dibBmp)
	h.memDC = memDC
	h.dibBmp = dibBmp
	h.dibBits = unsafe.Slice((*byte)(bitsPtr), hubWidth*hubHeight*4)
	defer func() {
		for _, f := range h.fonts {
			if f != 0 {
				procDeleteObject.Call(f)
			}
		}
		if oldBmp != 0 {
			procSelectObject.Call(memDC, oldBmp)
		}
		procDeleteObject.Call(dibBmp)
		procDeleteDC.Call(memDC)
	}()

	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(titlePtr)),
		wsPopup|wsMinimizeBox|wsVisible,
		uintptr(posX),
		uintptr(posY),
		hubWidth,
		hubHeight,
		0,
		0,
		hInstance,
		0,
	)
	if hwnd == 0 {
		return launchGameClient(cfg)
	}

	darkVal := int32(1)
	cornerVal := int32(dwmwcpRound)
	procDwmSetWindowAttribute.Call(hwnd, dwmwaDarkMode, uintptr(unsafe.Pointer(&darkVal)), 4)
	procDwmSetWindowAttribute.Call(hwnd, dwmwaCornerPref, uintptr(unsafe.Pointer(&cornerVal)), 4)
	margins := dwmMargins{1, 1, 1, 1}
	procDwmExtendFrameIntoClientArea.Call(hwnd, uintptr(unsafe.Pointer(&margins)))

	h.hwnd = hwnd
	hubWindows.Store(hwnd, h)
	defer hubWindows.Delete(hwnd)

	procSetTimer.Call(hwnd, caretTimerID, 530, 0)
	defer procKillTimer.Call(hwnd, caretTimerID)

	procInvalidateRect.Call(hwnd, 0, 0)
	go h.runCheckAsync()
	go h.runPingAsync()
	go h.runVerifySessionAsync()

	var m winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
	return 0
}

func (h *hubWindow) getFont(sizePx int, bold bool, display bool) uintptr {
	weight := 400
	if bold {
		weight = 700
	}
	dispBit := uint32(0)
	faceName := "Segoe UI"
	if display {
		dispBit = 1
		faceName = "Bahnschrift"
		if !bold {
			weight = 600
		}
	}
	key := (uint32(sizePx) << 17) | (uint32(weight) << 1) | dispBit
	if f, ok := h.fonts[key]; ok {
		return f
	}
	face, _ := syscall.UTF16PtrFromString(faceName)
	hVal := int32(-sizePx)
	f, _, _ := procCreateFontW.Call(
		uintptr(hVal), 0, 0, 0, uintptr(weight),
		0, 0, 0, 1, 0, 0, 5, 0, uintptr(unsafe.Pointer(face)),
	)
	h.fonts[key] = f
	return f
}

func (h *hubWindow) paintToDIB() {
	h.mu.Lock()
	st := hubRenderState{
		Tab:              h.tab,
		Phase:            h.phase,
		LocalVersion:     readLocalVersion(filepath.Join(h.cfg.GameDir, versionFileName)),
		LatestTag:        h.plan.TagName,
		HasExe:           h.hasExe,
		Busy:             h.busy,
		Launching:        h.launching,
		StatusText:       h.status,
		ProgText:         h.progTxt,
		ProgPct:          h.progPct,
		NotesRaw:         h.notes,
		NotesScroll:      h.scroll,
		SelectedRelease:  h.selRel,
		PingMs:           h.pingMs,
		Profile:          h.prof,
		GameDir:          h.cfg.GameDir,
		Repo:             h.cfg.Repo,
		HoverID:          h.hoverID,
		PressID:          h.pressID,
		AuthModeRegister: h.authRegister,
		FocusField:       h.focusField,
		CaretVisible:     h.caretVisible,
		InputUser:        h.inputUser,
		InputPass:        h.inputPass,
		InputPassConfirm: h.inputPassConfirm,
		ShowPassword:     h.showPassword,
		InputSearch:      h.inputSearch,
		AuthBusy:         h.authBusy,
		AuthMessage:      h.authMessage,
		AuthIsError:      h.authIsError,
		Friends:          h.friends,
		Incoming:         h.incoming,
		SearchResults:    h.searchRes,
	}
	h.mu.Unlock()

	hits, texts, maxScrl := renderHubFrame(h.dibBits, hubWidth*4, true, st)

	procSetBkMode.Call(h.memDC, transparentBk)
	for _, t := range texts {
		if t.text == "" {
			continue
		}
		f := h.getFont(t.sizePx, t.bold, t.display)
		if f != 0 {
			procSelectObject.Call(h.memDC, f)
		}
		colorRef := uint32(t.col.R) | (uint32(t.col.G) << 8) | (uint32(t.col.B) << 16)
		procSetTextColor.Call(h.memDC, uintptr(colorRef))
		r := rect{
			left:   int32(t.rect.Min.X),
			top:    int32(t.rect.Min.Y),
			right:  int32(t.rect.Max.X),
			bottom: int32(t.rect.Max.Y),
		}
		flags := uint32(dtNoPrefix)
		if t.multiline {
			flags |= dtWordBreak | dtTop
		} else {
			flags |= dtVCenter | dtSingleLine
		}
		switch t.align {
		case alignCenter:
			flags |= dtCenter
		case alignRight:
			flags |= dtRight
		default:
			flags |= dtLeft
		}
		if t.ellipsis && !t.multiline {
			flags |= dtEndEllipsis
		}
		ptr, err := syscall.UTF16PtrFromString(t.text)
		if err == nil {
			saved := uintptr(0)
			if !t.clip.Empty() {
				saved, _, _ = procSaveDC.Call(h.memDC)
				procIntersectClipRect.Call(h.memDC, uintptr(t.clip.Min.X), uintptr(t.clip.Min.Y), uintptr(t.clip.Max.X), uintptr(t.clip.Max.Y))
			}
			procDrawTextW.Call(h.memDC, uintptr(unsafe.Pointer(ptr)), ^uintptr(0), uintptr(unsafe.Pointer(&r)), uintptr(flags))
			if saved != 0 {
				procRestoreDC.Call(h.memDC, saved)
			}
		}
	}

	h.mu.Lock()
	h.hits = hits
	h.maxScrl = maxScrl
	if h.scroll > maxScrl {
		h.scroll = maxScrl
	}
	h.mu.Unlock()
}

func (h *hubWindow) hitTest(x, y int) string {
	h.mu.Lock()
	defer h.mu.Unlock()
	pt := image.Pt(x, y)
	for _, it := range h.hits {
		if pt.In(it.rect) {
			return it.id
		}
	}
	return ""
}

func (h *hubWindow) postRefresh() {
	h.mu.Lock()
	hwnd := h.hwnd
	h.mu.Unlock()
	if hwnd != 0 {
		procPostMessageW.Call(hwnd, wmHubState, 0, 0)
	}
}

func (h *hubWindow) runPingAsync() {
	ms := probeServerPing(defaultManilaHostPort, 2500*time.Millisecond)
	h.mu.Lock()
	h.pingMs = ms
	h.mu.Unlock()
	h.postRefresh()
}

func (h *hubWindow) applyAPIUserLocked(tok string, user apiUserProfile) {
	if tok != "" {
		h.prof.Token = tok
	}
	if user.Username != "" {
		h.prof.Username = user.Username
		h.prof.IsAccount = h.prof.Token != ""
	}
	if user.AvatarHash != "" {
		h.prof.AvatarHash = user.AvatarHash
	}
	if user.AvatarFrames > 0 {
		h.prof.AvatarFrames = user.AvatarFrames
	}
	if user.AvatarDelayMs >= 40 {
		h.prof.AvatarDelayMs = user.AvatarDelayMs
	}
	h.prof.GamesPlayed = user.GamesPlayed
	h.prof.Wins = user.Wins
	if user.Elo > 0 {
		h.prof.Elo = user.Elo
	}
	if user.RankTitle != "" {
		h.prof.RankTitle = user.RankTitle
	}
	var avPNG []byte
	if user.AvatarB64 != "" {
		if raw, err := base64.StdEncoding.DecodeString(user.AvatarB64); err == nil {
			avPNG = raw
		}
	}
	_ = saveLocalGodotProfile(h.userDir, &h.prof, avPNG)
}

func (h *hubWindow) runVerifySessionAsync() {
	h.mu.Lock()
	tok := h.prof.Token
	h.mu.Unlock()
	if tok == "" {
		return
	}
	user, err := h.acctAPI.Me(context.Background(), tok)
	if err != nil {
		msg := sanitizeUserError(err)
		if strings.Contains(strings.ToLower(msg), "expired") || strings.Contains(strings.ToLower(msg), "sign in") {
			h.mu.Lock()
			h.prof.Token = ""
			h.prof.IsAccount = false
			_ = saveLocalGodotProfile(h.userDir, &h.prof, nil)
			h.mu.Unlock()
			h.postRefresh()
		}
		return
	}
	h.mu.Lock()
	h.applyAPIUserLocked(tok, user)
	h.mu.Unlock()
	h.postRefresh()
	h.runRefreshFriendsAsync()
}

func (h *hubWindow) runRefreshFriendsAsync() {
	h.mu.Lock()
	tok := h.prof.Token
	h.mu.Unlock()
	if tok == "" {
		return
	}
	ov, err := h.acctAPI.FriendsOverview(context.Background(), tok)
	if err != nil {
		return
	}
	h.mu.Lock()
	h.friends = ov.Friends
	h.incoming = ov.IncomingRequests
	h.mu.Unlock()
	h.postRefresh()
}

func (h *hubWindow) runAuthSubmitAsync() {
	h.mu.Lock()
	if h.authBusy {
		h.mu.Unlock()
		return
	}
	isReg := h.authRegister
	u := strings.TrimSpace(h.inputUser)
	p := h.inputPass
	pConfirm := h.inputPassConfirm
	if u == "" || p == "" {
		h.authMessage = "Enter both username and password."
		h.authIsError = true
		h.mu.Unlock()
		h.postRefresh()
		return
	}
	if isReg {
		if len([]rune(p)) < 4 {
			h.authMessage = "Password must be at least 4 characters."
			h.authIsError = true
			h.mu.Unlock()
			h.postRefresh()
			return
		}
		if p != pConfirm {
			h.authMessage = "Passwords do not match."
			h.authIsError = true
			h.mu.Unlock()
			h.postRefresh()
			return
		}
	}
	h.authBusy = true
	h.authMessage = ""
	h.authIsError = false
	h.mu.Unlock()
	h.postRefresh()

	var tok string
	var user apiUserProfile
	var err error
	if isReg {
		tok, user, err = h.acctAPI.Register(context.Background(), u, p)
	} else {
		tok, user, err = h.acctAPI.Login(context.Background(), u, p)
	}

	h.mu.Lock()
	h.authBusy = false
	if err != nil {
		h.authMessage = sanitizeUserError(err)
		h.authIsError = true
		h.mu.Unlock()
		h.postRefresh()
		return
	}
	h.applyAPIUserLocked(tok, user)
	h.inputPass = ""
	h.inputPassConfirm = ""
	h.showPassword = false
	h.focusField = ""
	h.authMessage = "Signed in as @" + h.prof.Username
	h.authIsError = false
	h.mu.Unlock()
	h.postRefresh()
	h.runRefreshFriendsAsync()
}

func (h *hubWindow) runLogoutAsync() {
	h.mu.Lock()
	tok := h.prof.Token
	h.prof.Token = ""
	h.prof.IsAccount = false
	h.prof.Username = "Commander"
	h.friends = nil
	h.incoming = nil
	h.searchRes = nil
	h.focusField = "auth_user"
	h.authMessage = "Signed out."
	h.authIsError = false
	_ = saveLocalGodotProfile(h.userDir, &h.prof, nil)
	h.mu.Unlock()
	h.postRefresh()
	if tok != "" {
		_ = h.acctAPI.Logout(context.Background(), tok)
	}
}

func (h *hubWindow) runSearchAsync() {
	h.mu.Lock()
	tok := h.prof.Token
	q := strings.TrimSpace(h.inputSearch)
	if tok == "" {
		h.mu.Unlock()
		return
	}
	if q == "" {
		h.searchRes = nil
		h.authMessage = "Enter a username to search."
		h.authIsError = true
		h.mu.Unlock()
		h.postRefresh()
		return
	}
	h.authMessage = ""
	h.mu.Unlock()

	users, err := h.acctAPI.SearchUsers(context.Background(), tok, q)
	h.mu.Lock()
	if err != nil {
		h.authMessage = sanitizeUserError(err)
		h.authIsError = true
	} else {
		h.searchRes = users
		if len(users) == 0 {
			h.authMessage = fmt.Sprintf("No players matched %q.", q)
			h.authIsError = false
		}
	}
	h.mu.Unlock()
	h.postRefresh()
}

func (h *hubWindow) runFriendActionAsync(action, target string) {
	h.mu.Lock()
	tok := h.prof.Token
	h.mu.Unlock()
	if tok == "" {
		return
	}
	var msg string
	var err error
	switch action {
	case "add":
		msg, err = h.acctAPI.SendFriendRequest(context.Background(), tok, target)
	case "accept":
		msg, err = h.acctAPI.RespondFriendRequest(context.Background(), tok, target, true)
	case "decline":
		msg, err = h.acctAPI.RespondFriendRequest(context.Background(), tok, target, false)
	}
	h.mu.Lock()
	if err != nil {
		h.authMessage = sanitizeUserError(err)
		h.authIsError = true
	} else {
		h.authMessage = msg
		h.authIsError = false
	}
	h.mu.Unlock()
	h.postRefresh()
	h.runRefreshFriendsAsync()
	if strings.TrimSpace(h.inputSearch) != "" {
		h.runSearchAsync()
	}
}

func (h *hubWindow) pickAndUploadAvatar() {
	path := openAvatarFileDialog(h.hwnd)
	if path == "" {
		return
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		h.mu.Lock()
		h.authMessage = "Failed to read selected image."
		h.authIsError = true
		h.mu.Unlock()
		h.postRefresh()
		return
	}
	go func() {
		h.mu.Lock()
		tok := h.prof.Token
		h.authMessage = "Uploading avatar..."
		h.authIsError = false
		h.mu.Unlock()
		h.postRefresh()

		user, upErr := h.acctAPI.UploadAvatar(context.Background(), tok, raw)
		h.mu.Lock()
		if upErr != nil {
			h.authMessage = sanitizeUserError(upErr)
			h.authIsError = true
		} else {
			h.applyAPIUserLocked(tok, user)
			h.authMessage = "Avatar updated & synced."
			h.authIsError = false
		}
		h.mu.Unlock()
		h.postRefresh()
	}()
}

func openAvatarFileDialog(owner uintptr) string {
	buf := make([]uint16, 1024)
	filter := "Images & GIFs (*.png;*.jpg;*.jpeg;*.gif)\x00*.png;*.jpg;*.jpeg;*.gif\x00All Files (*.*)\x00*.*\x00\x00"
	filterPtr := syscall.StringToUTF16(filter)
	titlePtr, _ := syscall.UTF16PtrFromString("Select Profile Avatar (PNG, JPG, or GIF)")
	ofn := openFileNameW{
		lStructSize: uint32(unsafe.Sizeof(openFileNameW{})),
		hwndOwner:   owner,
		lpstrFilter: &filterPtr[0],
		lpstrFile:   &buf[0],
		nMaxFile:    uint32(len(buf)),
		lpstrTitle:  titlePtr,
		flags:       ofnExplorer | ofnFileMustExist | ofnPathMustExist | ofnNoChangeDir,
	}
	ok, _, _ := procGetOpenFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ok == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf)
}

func (h *hubWindow) runCheckAsync() {
	h.mu.Lock()
	if h.busy {
		h.mu.Unlock()
		return
	}
	h.busy = true
	h.phase = hubChecking
	h.progTxt = "Checking releases..."
	h.progPct = 0
	hasExe := fileExists(filepath.Join(h.cfg.GameDir, clientExeName))
	localVer := readLocalVersion(filepath.Join(h.cfg.GameDir, versionFileName))
	h.hasExe = hasExe
	h.mu.Unlock()
	h.postRefresh()

	plan, err := buildUpdatePlan(context.Background(), h.cfg)

	h.mu.Lock()
	h.busy = false
	h.plan = plan
	h.hasExe = fileExists(filepath.Join(h.cfg.GameDir, clientExeName))
	if plan.ReleaseNotes != "" {
		h.notes = plan.ReleaseNotes
	}
	verDisplay := localVer
	if verDisplay == "" {
		if h.hasExe {
			verDisplay = "installed"
		} else {
			verDisplay = "not installed"
		}
	}
	if err != nil {
		if h.hasExe {
			h.phase = hubReadyToPlay
			h.status = fmt.Sprintf("Installed %s · Offline mode", verDisplay)
			h.progTxt = ""
			h.progPct = 100
		} else {
			h.phase = hubNeedsInstall
			h.status = "Not installed · Connect online to download game client."
			h.progTxt = "Click INSTALL to download World War Pixel."
			h.progPct = 0
		}
	} else {
		switch plan.Kind {
		case updateNone:
			h.phase = hubReadyToPlay
			h.status = fmt.Sprintf("Up to date · Installed %s", verDisplay)
			h.progTxt = ""
			h.progPct = 100
		case updateDeltaPatch, updatePackReplace:
			h.phase = hubNeedsPatch
			h.status = fmt.Sprintf("Installed %s · Patch %s available", verDisplay, plan.TagName)
			h.progTxt = fmt.Sprintf("Patch %s available", plan.TagName)
			h.progPct = 0
		case updateFullClient:
			if !h.hasExe {
				h.phase = hubNeedsInstall
				h.status = fmt.Sprintf("Latest release: %s", plan.TagName)
				h.progTxt = "Click INSTALL to download World War Pixel."
			} else {
				h.phase = hubNeedsFullUpdate
				h.status = fmt.Sprintf("Installed %s · Update %s available", verDisplay, plan.TagName)
				h.progTxt = fmt.Sprintf("Update %s available", plan.TagName)
			}
			h.progPct = 0
		}
	}
	h.mu.Unlock()
	h.postRefresh()
}

func (h *hubWindow) runInstallOrUpdateAsync() {
	h.mu.Lock()
	if h.busy || h.plan.Payload == nil {
		h.mu.Unlock()
		return
	}
	h.busy = true
	h.phase = hubWorking
	plan := h.plan
	h.progTxt = fmt.Sprintf("Preparing %s...", plan.TagName)
	h.progPct = 2
	h.mu.Unlock()
	h.postRefresh()

	err := executeUpdatePlan(context.Background(), h.cfg, plan, func(status string, pct int) {
		h.mu.Lock()
		h.progTxt = status
		h.progPct = pct
		h.mu.Unlock()
		h.postRefresh()
	})

	h.mu.Lock()
	h.busy = false
	h.hasExe = fileExists(filepath.Join(h.cfg.GameDir, clientExeName))
	if err != nil {
		h.status = sanitizeUserError(err)
		h.progTxt = "Update interrupted."
		h.progPct = 0
		if h.hasExe {
			h.phase = hubReadyToPlay
		} else {
			h.phase = hubNeedsInstall
		}
	} else {
		h.phase = hubReadyToPlay
		h.plan.Kind = updateNone
		h.status = fmt.Sprintf("Up to date · Installed %s", plan.TagName)
		h.progTxt = ""
		h.progPct = 100
	}
	h.mu.Unlock()
	h.postRefresh()
}

// runRepairAsync clears stale patches and re-downloads the latest full client archive.
func (h *hubWindow) runRepairAsync() {
	h.mu.Lock()
	if h.busy || h.launching {
		h.mu.Unlock()
		return
	}
	h.busy = true
	h.tab = tabGame
	h.phase = hubWorking
	h.progTxt = "Verifying installation..."
	h.progPct = 2
	cfg := h.cfg
	h.mu.Unlock()
	h.postRefresh()

	tag, err := repairGameFiles(context.Background(), cfg, func(status string, pct int) {
		h.mu.Lock()
		h.progTxt = status
		h.progPct = pct
		h.mu.Unlock()
		h.postRefresh()
	})

	h.mu.Lock()
	h.busy = false
	h.hasExe = fileExists(filepath.Join(cfg.GameDir, clientExeName))
	if err != nil {
		h.status = sanitizeUserError(err)
		h.progTxt = "Repair interrupted."
		h.progPct = 0
		if h.hasExe {
			h.phase = hubReadyToPlay
		} else {
			h.phase = hubNeedsInstall
		}
	} else {
		h.phase = hubReadyToPlay
		h.plan.Kind = updateNone
		h.status = fmt.Sprintf("Verified & repaired · Installed %s", tag)
		h.progTxt = ""
		h.progPct = 100
	}
	h.mu.Unlock()
	h.postRefresh()
}

// startPlayAndForeground launches WorldWarPixel-Client.exe, brings its visible window to foreground, then closes the launcher.
func (h *hubWindow) startPlayAndForeground(extraArgs ...string) {
	h.mu.Lock()
	if h.launching || h.busy || !h.hasExe {
		h.mu.Unlock()
		return
	}
	h.launching = true
	h.status = "Starting World War Pixel..."
	launcherHwnd := h.hwnd
	cfg := h.cfg
	h.mu.Unlock()
	h.postRefresh()

	go func() {
		err := launchGameAndFocus(cfg, launcherHwnd, extraArgs...)
		if err != nil {
			h.mu.Lock()
			h.launching = false
			h.status = "Failed to launch game client."
			h.mu.Unlock()
			h.postRefresh()
			return
		}
		if launcherHwnd != 0 {
			procPostMessageW.Call(launcherHwnd, wmAppClose, 0, 0)
		}
	}()
}

func launchGameAndFocus(cfg launcherConfig, launcherHwnd uintptr, extraArgs ...string) error {
	clientExePath := filepath.Join(cfg.GameDir, clientExeName)
	if !fileExists(clientExePath) {
		return fmt.Errorf("missing client binary")
	}

	args := make([]string, 0, len(cfg.ForwardArgs)+len(extraArgs))
	args = append(args, cfg.ForwardArgs...)
	args = append(args, extraArgs...)
	cmd := exec.Command(clientExePath, args...)
	cmd.Dir = cfg.GameDir
	if err := cmd.Start(); err != nil {
		return err
	}
	pid := uint32(cmd.Process.Pid)
	procAllowSetForegroundWin.Call(uintptr(pid))
	procAllowSetForegroundWin.Call(^uintptr(0))

	// Poll up to 8s for Godot's top-level window so the game always opens in front instead of behind desktop windows.
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		enumTargetMu.Lock()
		enumTargetPID = pid
		enumFoundHwnd = 0
		procEnumWindows.Call(enumWindowsCb, 0)
		childHwnd := enumFoundHwnd
		enumTargetMu.Unlock()

		if childHwnd != 0 {
			iconic, _, _ := procIsIconic.Call(childHwnd)
			if iconic != 0 {
				procShowWindow.Call(childHwnd, swRestore)
			} else {
				procShowWindow.Call(childHwnd, swShow)
			}
			fgHwnd, _, _ := procGetForegroundWindow.Call()
			var fgTID uint32
			if fgHwnd != 0 {
				t, _, _ := procGetWindowThreadProcId.Call(fgHwnd, 0)
				fgTID = uint32(t)
			}
			curTID, _, _ := procGetCurrentThreadId.Call()
			attached := false
			if fgTID != 0 && fgTID != uint32(curTID) {
				res, _, _ := procAttachThreadInput.Call(curTID, uintptr(fgTID), 1)
				attached = res != 0
			}
			procBringWindowToTop.Call(childHwnd)
			procSetForegroundWindow.Call(childHwnd)
			if attached {
				procAttachThreadInput.Call(curTID, uintptr(fgTID), 0)
			}
			_ = launcherHwnd
			time.Sleep(120 * time.Millisecond)
			return nil
		}
		time.Sleep(50 * time.Millisecond)
	}
	return nil
}

func (h *hubWindow) handleClick(id string) {
	if strings.HasPrefix(id, "rel_") {
		var idx int
		if _, err := fmt.Sscanf(id, "rel_%d", &idx); err == nil {
			h.mu.Lock()
			h.selRel = idx
			h.scroll = 0
			h.mu.Unlock()
			procInvalidateRect.Call(h.hwnd, 0, 0)
		}
		return
	}
	if strings.HasPrefix(id, "add_friend:") {
		go h.runFriendActionAsync("add", strings.TrimPrefix(id, "add_friend:"))
		return
	}
	if strings.HasPrefix(id, "accept_req:") {
		go h.runFriendActionAsync("accept", strings.TrimPrefix(id, "accept_req:"))
		return
	}
	if strings.HasPrefix(id, "decline_req:") {
		go h.runFriendActionAsync("decline", strings.TrimPrefix(id, "decline_req:"))
		return
	}
	if strings.HasPrefix(id, "join_friend:") {
		code := strings.TrimSpace(strings.TrimPrefix(id, "join_friend:"))
		if code != "" {
			h.mu.Lock()
			hasExe := h.hasExe
			busy := h.busy
			launching := h.launching
			h.mu.Unlock()
			if hasExe && !busy && !launching {
				h.startPlayAndForeground("--join-room=" + code)
			}
		}
		return
	}

	switch id {
	case "tab_game":
		h.mu.Lock()
		h.tab = tabGame
		h.focusField = ""
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "tab_notes", "open_notes":
		h.mu.Lock()
		h.tab = tabNotes
		h.focusField = ""
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "tab_account", "open_account":
		h.mu.Lock()
		h.tab = tabAccount
		if !h.prof.IsAccount && h.focusField == "" {
			h.focusField = "auth_user"
		}
		isAcct := h.prof.IsAccount
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
		if isAcct {
			go h.runRefreshFriendsAsync()
		}
	case "tab_settings":
		h.mu.Lock()
		h.tab = tabSettings
		h.focusField = ""
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "auth_mode_login":
		h.mu.Lock()
		h.authRegister = false
		h.inputPassConfirm = ""
		h.authMessage = ""
		h.focusField = "auth_user"
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "auth_mode_register":
		h.mu.Lock()
		h.authRegister = true
		h.inputPassConfirm = ""
		h.authMessage = ""
		h.focusField = "auth_user"
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "auth_user", "auth_pass", "auth_pass_confirm", "friend_search":
		h.mu.Lock()
		h.focusField = id
		h.caretVisible = true
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "toggle_pass_eye":
		h.mu.Lock()
		h.showPassword = !h.showPassword
		h.caretVisible = true
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case "auth_submit":
		go h.runAuthSubmitAsync()
	case "auth_logout":
		go h.runLogoutAsync()
	case "upload_avatar":
		h.pickAndUploadAvatar()
	case "do_search":
		go h.runSearchAsync()
	case "refresh_friends":
		go h.runRefreshFriendsAsync()
	case "minimize":
		procShowWindow.Call(h.hwnd, swMinimize)
	case "close":
		procDestroyWindow.Call(h.hwnd)
	case "open_folder":
		_ = exec.Command("explorer.exe", h.cfg.GameDir).Start()
	case "check":
		go h.runCheckAsync()
		go h.runPingAsync()
	case "repair":
		go h.runRepairAsync()
	case "offline":
		h.startPlayAndForeground()
	case "primary":
		h.mu.Lock()
		ph := h.phase
		hasExe := h.hasExe
		busy := h.busy
		launching := h.launching
		h.mu.Unlock()
		if busy || launching {
			return
		}
		if ph == hubReadyToPlay && hasExe {
			h.startPlayAndForeground()
		} else if ph == hubNeedsInstall || ph == hubNeedsPatch || ph == hubNeedsFullUpdate {
			go h.runInstallOrUpdateAsync()
		}
	}
}

func readClipboardText(hwnd uintptr) string {
	ok, _, _ := procOpenClipboard.Call(hwnd)
	if ok == 0 {
		return ""
	}
	defer procCloseClipboard.Call()
	hMem, _, _ := procGetClipboardData.Call(cfUnicodeText)
	if hMem == 0 {
		return ""
	}
	ptr, _, _ := procGlobalLock.Call(hMem)
	if ptr == 0 {
		return ""
	}
	defer procGlobalUnlock.Call(hMem)
	u16 := unsafe.Slice((*uint16)(unsafe.Pointer(ptr)), 256)
	return syscall.UTF16ToString(u16)
}

func (h *hubWindow) appendRunesFocused(s string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.focusField == "" {
		return
	}
	clean := make([]rune, 0, len(s))
	for _, r := range s {
		if r >= 0x20 && r != 0x7F {
			clean = append(clean, r)
		}
	}
	if len(clean) == 0 {
		return
	}
	switch h.focusField {
	case "auth_user":
		cur := []rune(h.inputUser)
		for _, r := range clean {
			if len(cur) < 20 {
				cur = append(cur, r)
			}
		}
		h.inputUser = string(cur)
	case "auth_pass":
		cur := []rune(h.inputPass)
		for _, r := range clean {
			if len(cur) < 128 {
				cur = append(cur, r)
			}
		}
		h.inputPass = string(cur)
	case "auth_pass_confirm":
		cur := []rune(h.inputPassConfirm)
		for _, r := range clean {
			if len(cur) < 128 {
				cur = append(cur, r)
			}
		}
		h.inputPassConfirm = string(cur)
	case "friend_search":
		cur := []rune(h.inputSearch)
		for _, r := range clean {
			if len(cur) < 20 {
				cur = append(cur, r)
			}
		}
		h.inputSearch = string(cur)
	}
	h.caretVisible = true
}

func (h *hubWindow) handleChar(ch rune) {
	switch ch {
	case '\b':
		h.mu.Lock()
		switch h.focusField {
		case "auth_user":
			r := []rune(h.inputUser)
			if len(r) > 0 {
				h.inputUser = string(r[:len(r)-1])
			}
		case "auth_pass":
			r := []rune(h.inputPass)
			if len(r) > 0 {
				h.inputPass = string(r[:len(r)-1])
			}
		case "auth_pass_confirm":
			r := []rune(h.inputPassConfirm)
			if len(r) > 0 {
				h.inputPassConfirm = string(r[:len(r)-1])
			}
		case "friend_search":
			r := []rune(h.inputSearch)
			if len(r) > 0 {
				h.inputSearch = string(r[:len(r)-1])
			}
		}
		h.caretVisible = true
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case '\t':
		h.mu.Lock()
		if h.tab == tabAccount && !h.prof.IsAccount {
			if h.focusField == "auth_user" {
				h.focusField = "auth_pass"
			} else if h.focusField == "auth_pass" && h.authRegister {
				h.focusField = "auth_pass_confirm"
			} else {
				h.focusField = "auth_user"
			}
			h.caretVisible = true
		}
		h.mu.Unlock()
		procInvalidateRect.Call(h.hwnd, 0, 0)
	case '\r':
		h.mu.Lock()
		tab := h.tab
		ff := h.focusField
		isAcct := h.prof.IsAccount
		h.mu.Unlock()
		if tab == tabAccount && !isAcct {
			go h.runAuthSubmitAsync()
		} else if tab == tabAccount && isAcct && ff == "friend_search" {
			go h.runSearchAsync()
		}
	default:
		if ch >= 0x20 && ch != 0x7F {
			h.appendRunesFocused(string(ch))
			procInvalidateRect.Call(h.hwnd, 0, 0)
		}
	}
}

func signedLoHi(lp uintptr) (int, int) {
	x := int(int16(lp & 0xFFFF))
	y := int(int16((lp >> 16) & 0xFFFF))
	return x, y
}

func hubWndProc(hwnd uintptr, uMsg uint32, wParam, lParam uintptr) uintptr {
	v, ok := hubWindows.Load(hwnd)
	if !ok {
		ret, _, _ := procDefWindowProcW.Call(hwnd, uintptr(uMsg), wParam, lParam)
		return ret
	}
	h := v.(*hubWindow)

	switch uMsg {
	case wmEraseBkgnd:
		return 1
	case wmHubState:
		procInvalidateRect.Call(hwnd, 0, 0)
		return 0
	case wmAppClose:
		procDestroyWindow.Call(hwnd)
		return 0
	case wmTimer:
		if wParam == caretTimerID {
			h.mu.Lock()
			hasFocus := h.focusField != "" && h.tab == tabAccount
			if hasFocus {
				h.caretVisible = !h.caretVisible
			}
			h.mu.Unlock()
			if hasFocus {
				procInvalidateRect.Call(hwnd, 0, 0)
			}
		}
		return 0
	case wmKeyDown:
		if wParam == vkEscape {
			h.mu.Lock()
			h.focusField = ""
			h.mu.Unlock()
			procInvalidateRect.Call(hwnd, 0, 0)
			return 0
		}
		if wParam == 'V' {
			ctrlState, _, _ := procGetKeyState.Call(vkControl)
			if (ctrlState & 0x8000) != 0 {
				if clip := readClipboardText(hwnd); clip != "" {
					h.appendRunesFocused(clip)
					procInvalidateRect.Call(hwnd, 0, 0)
				}
				return 0
			}
		}
		return 0
	case wmChar:
		h.handleChar(rune(wParam))
		return 0
	case wmPaint:
		var ps paintStruct
		hdc, _, _ := procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		if hdc != 0 {
			h.paintToDIB()
			procBitBlt.Call(hdc, 0, 0, hubWidth, hubHeight, h.memDC, 0, 0, srcCopy)
			procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
		}
		return 0
	case wmNCHitTest:
		sx, sy := signedLoHi(lParam)
		pt := point{int32(sx), int32(sy)}
		procScreenToClient.Call(hwnd, uintptr(unsafe.Pointer(&pt)))
		if pt.y >= 0 && pt.y < 60 && pt.x >= railWidth {
			if h.hitTest(int(pt.x), int(pt.y)) == "" {
				return htCaption
			}
		}
		return htClient
	case wmMouseMove:
		x, y := signedLoHi(lParam)
		id := h.hitTest(x, y)
		h.mu.Lock()
		changed := h.hoverID != id
		h.hoverID = id
		if !h.tracking {
			h.tracking = true
			tme := trackMouseEventStruct{
				cbSize:    uint32(unsafe.Sizeof(trackMouseEventStruct{})),
				dwFlags:   tmeLeave,
				hwndTrack: hwnd,
			}
			procTrackMouseEvent.Call(uintptr(unsafe.Pointer(&tme)))
		}
		h.mu.Unlock()
		if id != "" {
			procSetCursor.Call(h.handC)
		} else {
			procSetCursor.Call(h.arrowC)
		}
		if changed {
			procInvalidateRect.Call(hwnd, 0, 0)
		}
		return 0
	case wmMouseLeave:
		h.mu.Lock()
		h.tracking = false
		changed := h.hoverID != ""
		h.hoverID = ""
		h.pressID = ""
		h.mu.Unlock()
		if changed {
			procInvalidateRect.Call(hwnd, 0, 0)
		}
		return 0
	case wmLButtonDown:
		x, y := signedLoHi(lParam)
		id := h.hitTest(x, y)
		h.mu.Lock()
		h.pressID = id
		h.mu.Unlock()
		procSetCapture.Call(hwnd)
		procInvalidateRect.Call(hwnd, 0, 0)
		return 0
	case wmLButtonUp:
		procReleaseCapture.Call()
		x, y := signedLoHi(lParam)
		relID := h.hitTest(x, y)
		h.mu.Lock()
		pressed := h.pressID
		h.pressID = ""
		h.mu.Unlock()
		procInvalidateRect.Call(hwnd, 0, 0)
		if pressed != "" && pressed == relID {
			h.handleClick(relID)
		}
		return 0
	case wmMouseWheel:
		delta := int16((wParam >> 16) & 0xFFFF)
		h.mu.Lock()
		if h.tab == tabNotes {
			h.scroll -= int(delta) / 3
			if h.scroll < 0 {
				h.scroll = 0
			}
			if h.scroll > h.maxScrl {
				h.scroll = h.maxScrl
			}
		}
		h.mu.Unlock()
		procInvalidateRect.Call(hwnd, 0, 0)
		return 0
	case wmClose:
		procDestroyWindow.Call(hwnd)
		return 0
	case wmDestroy:
		procPostQuitMessage.Call(0)
		return 0
	default:
		ret, _, _ := procDefWindowProcW.Call(hwnd, uintptr(uMsg), wParam, lParam)
		return ret
	}
}
