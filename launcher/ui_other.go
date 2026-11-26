//go:build !windows

package main

import (
	"fmt"
	"os"
)

func acquireSingleInstance() (func(), bool) {
	return func() {}, true
}

func showErrorBox(title, message string) {
	fmt.Fprintf(os.Stderr, "%s: %s\n", title, message)
}

type consoleProgressUI struct{}

func newProgressUI() progressUI {
	return &consoleProgressUI{}
}

func (c *consoleProgressUI) Show(status string) {
	fmt.Println(status)
}

func (c *consoleProgressUI) SetStatus(status string) {
	fmt.Println(status)
}

func (c *consoleProgressUI) Close() {}

func runLauncherHub(cfg launcherConfig) int {
	return checkAndLaunchConsole(cfg)
}

func checkAndLaunchConsole(cfg launcherConfig) int {
	ui := newProgressUI()
	defer ui.Close()
	_ = ui
	return launchGameClient(cfg)
}
