package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

func main() {
	a := app.New()
	w := a.NewWindow("GitHub SSH Manager")
	w.Resize(fyne.NewSize(700, 550))

	// Determine SSH directory cross-platform
	var sshDir string
	switch runtime.GOOS {
	case "windows":
		if userProfile := os.Getenv("USERPROFILE"); userProfile != "" {
			sshDir = filepath.Join(userProfile, ".ssh")
		} else {
			dialog.ShowError(fmt.Errorf("cannot determine USERPROFILE on Windows"), w)
			return
		}
	case "linux", "darwin":
		if home := os.Getenv("HOME"); home != "" {
			sshDir = filepath.Join(home, ".ssh")
		} else {
			dialog.ShowError(fmt.Errorf("cannot determine HOME on Linux/macOS"), w)
			return
		}
	default:
		dialog.ShowError(fmt.Errorf("unsupported OS: %s", runtime.GOOS), w)
		return
	}
	os.MkdirAll(sshDir, 0700)
	configFile := filepath.Join(sshDir, "config")

	// Input entries
	labelEntry := widget.NewEntry()
	labelEntry.SetPlaceHolder("Account label (e.g. personal, work)")

	hostEntry := widget.NewEntry()
	hostEntry.SetPlaceHolder("Host alias (e.g. github-linux)")
	hostEntry.SetText("github-linux") // default

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
   - Enter a host alias (e.g. github-linux)
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
		hostAlias := hostEntry.Text
		if hostAlias == "" {
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		keyPath := filepath.Join(sshDir, "id_ed25519_"+label)
		if _, err := os.Stat(keyPath); err == nil {
			dialog.ShowInformation("Info", "Key already exists: "+keyPath, w)
			return
		}

		// Generate the SSH key
		cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-C", label+"@github", "-f", keyPath, "-N", "")
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			dialog.ShowError(fmt.Errorf("keygen failed: %v\n%s", err, stderr.String()), w)
			return
		}

		// Add GitHub to known_hosts
		knownHostsPath := filepath.Join(sshDir, "known_hosts")
		scanCmd := exec.Command("ssh-keyscan", "github.com")
		out, err := scanCmd.Output()
		if err == nil {
			f, _ := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			defer f.Close()
			f.Write(out)
		}

		// Update SSH config with user-defined host alias
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

	// Upload Key via PAT with user-friendly messages
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
		jsonData := fmt.Sprintf(`{"title":"%s-%s","key":"%s"}`, label, hostEntry.Text, strings.TrimSpace(string(pub)))
		cmd := exec.Command("curl", "-s", "-H", "Authorization: token "+token,
			"-H", "Accept: application/vnd.github+json", apiURL, "-d", jsonData)

		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			dialog.ShowError(fmt.Errorf("upload failed: %v", err), w)
			return
		}

		// Parse JSON response
		var resp map[string]interface{}
		if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
			dialog.ShowInformation("Response", string(out.Bytes()), w)
			return
		}

		// Show user-friendly message
		if resp["id"] != nil {
			dialog.ShowInformation("Success", fmt.Sprintf("SSH Key uploaded successfully!\nTitle: %s", resp["title"]), w)
		} else if resp["message"] != nil {
			dialog.ShowError(fmt.Errorf("Error: %s", resp["message"]), w)
		} else {
			dialog.ShowInformation("Response", string(out.Bytes()), w)
		}
	})

	// Test SSH Connection
	testBtn := widget.NewButtonWithIcon("Test SSH", theme.ConfirmIcon(), func() {
		hostAlias := hostEntry.Text
		if hostAlias == "" {
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

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

	// View SSH Config (professional modal)
	viewConfigBtn := widget.NewButtonWithIcon("View SSH Config", theme.DocumentIcon(), func() {
		cfg, err := ioutil.ReadFile(configFile)
		if err != nil {
			dialog.ShowError(fmt.Errorf("cannot read ssh config: %v", err), w)
			return
		}

		cfgLabel := widget.NewLabel(string(cfg))
		cfgLabel.Wrapping = fyne.TextWrapWord
		cfgLabel.TextStyle.Monospace = true

		scrollContainer := container.NewVScroll(cfgLabel)
		scrollContainer.SetMinSize(fyne.NewSize(600, 400))

		copyBtn := widget.NewButtonWithIcon("Copy Config", theme.ContentCopyIcon(), func() {
			w.Clipboard().SetContent(string(cfg))
			dialog.ShowInformation("Copied", "SSH config copied to clipboard", w)
		})

		modalContent := container.NewVBox(
			widget.NewLabelWithStyle("~/.ssh/config", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			container.NewPadded(scrollContainer),
			container.NewHBox(layout.NewSpacer(), copyBtn),
		)

		dialog.ShowCustom("SSH Config Viewer", "Close", modalContent, w)
	})

	// Layout
	form := container.NewVBox(
		labelEntry,
		hostEntry,
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
