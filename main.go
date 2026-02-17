package main

import (
	"fmt"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/dialog"
)

func main() {
	a := app.New()
	w := a.NewWindow("GitHub SSH Manager")
	w.Resize(fyne.NewSize(980, 760))

	sshDir, err := getSSHDirectory()
	if err != nil {
		dialog.ShowError(err, w)
		w.ShowAndRun()
		return
	}
	if err := ensureSSHDirectory(sshDir); err != nil {
		dialog.ShowError(fmt.Errorf("failed to prepare SSH directory: %w", err), w)
		w.ShowAndRun()
		return
	}

	buildUI(a, w, sshDir)
	w.ShowAndRun()
}
