package main

import (
	"fmt"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/dialog"

	"github.com/Sarwarhridoy4/github-ssh-manager/internal/ssh"
	"github.com/Sarwarhridoy4/github-ssh-manager/internal/ui"
)

func main() {
	a := app.New()
	w := a.NewWindow("GitHub SSH Manager")
	w.Resize(fyne.NewSize(980, 760))

	sshDir, err := ssh.GetSSHDirectory()
	if err != nil {
		w.ShowAndRun()
		fyne.Do(func() {
			dialog.ShowError(err, w)
		})
		return
	}
	if err := ssh.EnsureSSHDirectory(sshDir); err != nil {
		w.ShowAndRun()
		fyne.Do(func() {
			dialog.ShowError(fmt.Errorf("failed to prepare SSH directory: %w", err), w)
		})
		return
	}

	ui.BuildUI(a, w, sshDir)
	w.ShowAndRun()
}
