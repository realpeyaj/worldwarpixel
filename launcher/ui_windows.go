//go:build windows

package main

import (
	"runtime"
	"sync"
	"syscall"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	procCreateMutexW     = kernel32.NewProc("CreateMutexW")
	procCloseHandle      = kernel32.NewProc("CloseHandle")
	procGetModuleHandleW = kernel32.NewProc("GetModuleHandleW")

	procGetStockObject = gdi32.NewProc("GetStockObject")

	procMessageBoxW      = user32.NewProc("MessageBoxW")
	procRegisterClassExW = user32.NewProc("RegisterClassExW")
	procCreateWindowExW  = user32.NewProc("CreateWindowExW")
	procDestroyWindow    = user32.NewProc("DestroyWindow")
	procDefWindowProcW   = user32.NewProc("DefWindowProcW")
	procGetMessageW      = user32.NewProc("GetMessageW")
	procTranslateMessage = user32.NewProc("TranslateMessage")
	procDispatchMessageW = user32.NewProc("DispatchMessageW")
	procPostMessageW     = user32.NewProc("PostMessageW")
	procPostQuitMessage  = user32.NewProc("PostQuitMessage")
	procLoadIconW        = user32.NewProc("LoadIconW")
	procLoadCursorW      = user32.NewProc("LoadCursorW")
	procGetSystemMetrics = user32.NewProc("GetSystemMetrics")
	procSetWindowTextW   = user32.NewProc("SetWindowTextW")
	procSendMessageW     = user32.NewProc("SendMessageW")
	procGetClientRect    = user32.NewProc("GetClientRect")
)

const (
	errorAlreadyExists = 183

	mbOK        = 0x00000000
	mbIconError = 0x00000010

	wsChild      = 0x40000000
	wsVisible    = 0x10000000
	wsOverlapped = 0x00000000
	wsCaption    = 0x00C00000

	ssLeft     = 0x00000000
	ssNoPrefix = 0x00000080

	wmDestroy  = 0x0002
	wmClose    = 0x0010
	wmSetFont  = 0x0030
	wmAppStatus = 0x8001
	wmAppClose  = 0x8002

	idcArrow       = 32512
	colorBtnFace   = 15
	defaultGUIFont = 17
	smCXScreen     = 0
	smCYScreen     = 1
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

var (
	progressWindows sync.Map
	wndProcCallback = syscall.NewCallback(progressWndProc)
)

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
		// Ignore user close while file swap may be active; Close() tears down via wmAppClose.
		return 0
	case wmDestroy:
		procPostQuitMessage.Call(0)
		return 0
	default:
		ret, _, _ := procDefWindowProcW.Call(hwnd, uintptr(uMsg), wParam, lParam)
		return ret
	}
}
