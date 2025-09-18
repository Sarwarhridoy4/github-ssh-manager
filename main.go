package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

func main() {
	a := app.New()
	w := a.NewWindow("GitHub SSH Manager")
	w.Resize(fyne.NewSize(700, 550))

	sshDir := filepath.Join(os.Getenv("HOME"), ".ssh")
	os.MkdirAll(sshDir, 0700)
	configFile := filepath.Join(sshDir, "config")

	// Input entries
	labelEntry := widget.NewEntry()
	labelEntry.SetPlaceHolder("Account label (e.g. personal, work)")

	tokenEntry := widget.NewPasswordEntry()
	tokenEntry.SetPlaceHolder("GitHub PAT (admin:public_key, repo)")

	// Help button
	helpBtn := widget.NewButtonWithIcon("Help / Instructions", theme.HelpIcon(), func() {
		instructions := `GitHub SSH Manager Instructions:

1. Generate a Personal Access Token (PAT):
   - Open https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Enable:
       ✅ admin:public_key
       ✅ repo

2. Generate SSH Key:
   - Enter a label (e.g. personal, work)
   - Click "Generate Key"

3. Show Public Key:
   - Click "Show Public Key" and copy if needed

4. Upload Key:
   - Click "Upload Key" to GitHub using the PAT

5. Test SSH Connection:
   - Click "Test SSH" to verify connection

6. View SSH Config:
   - Click "View SSH Config" to see host blocks and copy if needed`
		dialog.ShowInformation("Instructions", instructions, w)
	})

	// Generate SSH Key
	genBtn := widget.NewButtonWithIcon("Generate Key", theme.DocumentCreateIcon(), func() {
		label := labelEntry.Text
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		keyPath := filepath.Join(sshDir, "id_ed25519_"+label)
		if _, err := os.Stat(keyPath); err == nil {
			dialog.ShowInformation("Info", "key already exists: "+keyPath, w)
			return
		}

		// Generate the SSH key
		if err := exec.Command("ssh-keygen", "-t", "ed25519", "-C", label+"@github", "-f", keyPath, "-N", "").Run(); err != nil {
			dialog.ShowError(fmt.Errorf("keygen failed: %v", err), w)
			return
		}

		// Add GitHub to known_hosts
		knownHostsPath := filepath.Join(sshDir, "known_hosts")
		cmd := exec.Command("ssh-keyscan", "github.com")
		out, err := cmd.Output()
		if err == nil {
			f, _ := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			defer f.Close()
			f.Write(out)
		}

		// Update SSH config
		hostAlias := "github-" + label
		appendConfig(configFile, hostAlias, "github.com", keyPath)
		dialog.ShowInformation("Success", "SSH key generated, config updated, and github.com added to known_hosts:\n"+keyPath, w)
	})

	// Show Public Key
	showPubBtn := widget.NewButtonWithIcon("Show Public Key", theme.ContentCopyIcon(), func() {
		label := labelEntry.Text
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		pubKeyPath := filepath.Join(sshDir, "id_ed25519_"+label+".pub")
		pub, err := ioutil.ReadFile(pubKeyPath)
		if err != nil {
			dialog.ShowError(fmt.Errorf("cannot read public key: %v", err), w)
			return
		}

		pubEntry := widget.NewMultiLineEntry()
		pubEntry.SetText(string(pub))
		pubEntry.SetMinRowsVisible(6)

		copyBtn := widget.NewButtonWithIcon("Copy to Clipboard", theme.ContentCopyIcon(), func() {
			w.Clipboard().SetContent(string(pub))
			dialog.ShowInformation("Copied", "Public key copied to clipboard", w)
		})

		dialog.ShowCustom("Public Key - "+label, "Close", container.NewVBox(pubEntry, copyBtn), w)
	})

	// Upload Key via PAT
	uploadBtn := widget.NewButtonWithIcon("Upload Key", theme.UploadIcon(), func() {
		label := labelEntry.Text
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		token := tokenEntry.Text
		if token == "" {
			dialog.ShowError(fmt.Errorf("please paste your GitHub PAT first"), w)
			return
		}

		pubKeyPath := filepath.Join(sshDir, "id_ed25519_"+label+".pub")
		pub, err := ioutil.ReadFile(pubKeyPath)
		if err != nil {
			dialog.ShowError(fmt.Errorf("no public key found at %s (generate first)", pubKeyPath), w)
			return
		}

		apiURL := "https://api.github.com/user/keys"
		jsonData := fmt.Sprintf(`{"title":"%s-%s","key":"%s"}`, label, "fyne-app", strings.TrimSpace(string(pub)))
		cmd := exec.Command("curl", "-s", "-H", "Authorization: token "+token,
			"-H", "Accept: application/vnd.github+json", apiURL, "-d", jsonData)

		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			dialog.ShowError(fmt.Errorf("upload failed: %v", err), w)
			return
		}

		dialog.ShowInformation("Response", out.String(), w)
	})

	// Test SSH Connection
	testBtn := widget.NewButtonWithIcon("Test SSH", theme.ConfirmIcon(), func() {
		label := labelEntry.Text
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		hostAlias := "github-" + label
		cmd := exec.Command("ssh", "-T", "git@"+hostAlias)
		var out, stderr bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			dialog.ShowError(fmt.Errorf("ssh test failed: %s", stderr.String()), w)
			return
		}
		dialog.ShowInformation("SSH Test", out.String(), w)
	})

	// View SSH Config (polished modal)
	viewConfigBtn := widget.NewButtonWithIcon("View SSH Config", theme.DocumentIcon(), func() {
		cfg, err := ioutil.ReadFile(configFile)
		if err != nil {
			dialog.ShowError(fmt.Errorf("cannot read ssh config: %v", err), w)
			return
		}

		cfgEntry := widget.NewMultiLineEntry()
		cfgEntry.SetText(string(cfg))
		cfgEntry.SetMinRowsVisible(15)
		cfgEntry.Wrapping = fyne.TextWrapWord
		cfgEntry.Disable() // read-only

		copyBtn := widget.NewButtonWithIcon("Copy Config", theme.ContentCopyIcon(), func() {
			w.Clipboard().SetContent(string(cfg))
			dialog.ShowInformation("Copied", "SSH config copied to clipboard", w)
		})

		modalContent := container.NewVBox(
			widget.NewLabelWithStyle("~/.ssh/config", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			container.NewPadded(cfgEntry),
			copyBtn,
		)

		dialog.ShowCustom("SSH Config Viewer", "Close",
			container.NewBorder(nil, nil, nil, nil, container.NewPadded(modalContent)), w)
	})

	// Layout (simple vertical scrollable)
	form := container.NewVBox(
		labelEntry,
		tokenEntry,
		genBtn,
		showPubBtn,
		uploadBtn,
		testBtn,
		viewConfigBtn,
		helpBtn,
	)

	scroll := container.NewVScroll(form)
	scroll.SetMinSize(fyne.NewSize(650, 500))
	w.SetContent(scroll)
	w.SetIcon(theme.ComputerIcon())
	w.ShowAndRun()
}

// appendConfig ensures ~/.ssh/config contains a Host block for this key
func appendConfig(configFile, hostAlias, hostName, keyPath string) {
	content, _ := ioutil.ReadFile(configFile)
	if strings.Contains(string(content), "Host "+hostAlias) {
		return // already exists
	}
	entry := fmt.Sprintf("\nHost %s\n  HostName %s\n  IdentityFile %s\n  AddKeysToAgent yes\n  IdentitiesOnly yes\n",
		hostAlias, hostName, keyPath)
	f, _ := os.OpenFile(configFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	defer f.Close()
	f.WriteString(entry)
}
