package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/url"
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
	w.Resize(fyne.NewSize(750, 600))

	// Determine SSH directory cross-platform
	sshDir, err := getSSHDirectory()
	if err != nil {
		dialog.ShowError(err, w)
		return
	}

	// Ensure .ssh directory exists with proper permissions
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		dialog.ShowError(fmt.Errorf("failed to create .ssh directory: %v", err), w)
		return
	}

	configFile := filepath.Join(sshDir, "config")

	// Header section
	titleLabel := widget.NewLabelWithStyle("GitHub SSH Key Manager", fyne.TextAlignCenter, fyne.TextStyle{Bold: true})
	subtitleLabel := widget.NewLabel("Manage SSH keys for GitHub accounts")
	subtitleLabel.Alignment = fyne.TextAlignCenter

	separator1 := widget.NewSeparator()

	// Input section
	labelEntry := widget.NewEntry()
	labelEntry.SetPlaceHolder("Account label (e.g., personal, work, company)")

	hostEntry := widget.NewEntry()
	hostEntry.SetPlaceHolder("Host alias (e.g., github-personal, github-work)")

	tokenEntry := widget.NewPasswordEntry()
	tokenEntry.SetPlaceHolder("GitHub Personal Access Token")

	// Form layout with labels
	formGrid := container.New(layout.NewFormLayout(),
		widget.NewLabel("Label:"), labelEntry,
		widget.NewLabel("Host Alias:"), hostEntry,
		widget.NewLabel("GitHub PAT:"), tokenEntry,
	)

	separator2 := widget.NewSeparator()

	// Action buttons in a grid
	genBtn := widget.NewButtonWithIcon("Generate SSH Key", theme.DocumentCreateIcon(), func() {
		label := strings.TrimSpace(labelEntry.Text)
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		hostAlias := strings.TrimSpace(hostEntry.Text)
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
			if f != nil {
				defer f.Close()
				f.Write(out)
			}
		}

		// Update SSH config with user-defined host alias
		appendConfig(configFile, hostAlias, "github.com", keyPath)
		dialog.ShowInformation("Success", fmt.Sprintf("✓ SSH key generated\n✓ Config updated\n✓ GitHub added to known_hosts\n\nKey: %s", keyPath), w)
	})
	genBtn.Importance = widget.HighImportance

	showPubBtn := widget.NewButtonWithIcon("Show Public Key", theme.VisibilityIcon(), func() {
		label := strings.TrimSpace(labelEntry.Text)
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
		pubEntry.Wrapping = fyne.TextWrapBreak

		copyBtn := widget.NewButtonWithIcon("Copy to Clipboard", theme.ContentCopyIcon(), func() {
			w.Clipboard().SetContent(string(pub))
			dialog.ShowInformation("Copied", "✓ Public key copied to clipboard", w)
		})
		copyBtn.Importance = widget.HighImportance

		modalContent := container.NewVBox(
			widget.NewLabelWithStyle("Public Key - "+label, fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			widget.NewSeparator(),
			pubEntry,
			container.NewHBox(layout.NewSpacer(), copyBtn),
		)

		dialog.ShowCustom("Public Key", "Close", modalContent, w)
	})

	uploadBtn := widget.NewButtonWithIcon("Upload to GitHub", theme.UploadIcon(), func() {
		label := strings.TrimSpace(labelEntry.Text)
		if label == "" {
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		token := strings.TrimSpace(tokenEntry.Text)
		if token == "" {
			dialog.ShowError(fmt.Errorf("please enter your GitHub Personal Access Token"), w)
			return
		}
		hostAlias := strings.TrimSpace(hostEntry.Text)
		if hostAlias == "" {
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		pubKeyPath := filepath.Join(sshDir, "id_ed25519_"+label+".pub")
		pub, err := ioutil.ReadFile(pubKeyPath)
		if err != nil {
			dialog.ShowError(fmt.Errorf("no public key found (generate key first): %v", err), w)
			return
		}

		apiURL := "https://api.github.com/user/keys"
		keyTitle := label + "-" + hostAlias
		jsonData := fmt.Sprintf(`{"title":"%s","key":"%s"}`, keyTitle, strings.TrimSpace(string(pub)))
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
			dialog.ShowInformation("Success", fmt.Sprintf("✓ SSH Key uploaded successfully!\n\nTitle: %s\nID: %.0f", resp["title"], resp["id"]), w)
		} else if resp["message"] != nil {
			dialog.ShowError(fmt.Errorf("GitHub API Error: %s", resp["message"]), w)
		} else {
			dialog.ShowInformation("Response", string(out.Bytes()), w)
		}
	})
	uploadBtn.Importance = widget.HighImportance

	testBtn := widget.NewButtonWithIcon("Test SSH Connection", theme.ConfirmIcon(), func() {
		hostAlias := strings.TrimSpace(hostEntry.Text)
		if hostAlias == "" {
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		cmd := exec.Command("ssh", "-T", "git@"+hostAlias)
		var out, stderr bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &stderr
		
		// SSH to GitHub always returns exit code 1 with success message in stderr
		cmd.Run()
		
		combinedOutput := stderr.String() + out.String()
		if strings.Contains(combinedOutput, "successfully authenticated") {
			dialog.ShowInformation("Success", "✓ SSH connection successful!\n\n"+combinedOutput, w)
		} else {
			dialog.ShowError(fmt.Errorf("SSH test failed:\n%s", combinedOutput), w)
		}
	})

	viewConfigBtn := widget.NewButtonWithIcon("View SSH Config", theme.DocumentIcon(), func() {
		cfg, err := ioutil.ReadFile(configFile)
		if err != nil {
			dialog.ShowError(fmt.Errorf("cannot read SSH config: %v", err), w)
			return
		}

		cfgLabel := widget.NewLabel(string(cfg))
		cfgLabel.Wrapping = fyne.TextWrapWord
		cfgLabel.TextStyle.Monospace = true

		scrollContainer := container.NewVScroll(cfgLabel)
		scrollContainer.SetMinSize(fyne.NewSize(600, 400))

		copyBtn := widget.NewButtonWithIcon("Copy to Clipboard", theme.ContentCopyIcon(), func() {
			w.Clipboard().SetContent(string(cfg))
			dialog.ShowInformation("Copied", "✓ SSH config copied to clipboard", w)
		})

		modalContent := container.NewVBox(
			widget.NewLabelWithStyle("SSH Configuration File", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
			widget.NewLabel(configFile),
			widget.NewSeparator(),
			container.NewPadded(scrollContainer),
			container.NewHBox(layout.NewSpacer(), copyBtn),
		)

		dialog.ShowCustom("SSH Config Viewer", "Close", modalContent, w)
	})

	// Button grid layout
	buttonGrid := container.NewGridWithColumns(2,
		genBtn,
		showPubBtn,
		uploadBtn,
		testBtn,
	)

	viewConfigBtn.Importance = widget.LowImportance

	// Help button with hyperlink
	helpBtn := widget.NewButtonWithIcon("Help & Instructions", theme.HelpIcon(), func() {
		instructions := widget.NewRichTextFromMarkdown(`## GitHub SSH Manager Instructions

### 1. Generate a Personal Access Token (PAT)
Visit GitHub Settings and create a token with these permissions:
• **admin:public_key** (read and write)
• **repo** (optional, for private repos)

### 2. Fill in the Form
• **Label**: Descriptive name (e.g., personal, work)
• **Host Alias**: SSH host identifier (e.g., github-personal)
• **GitHub PAT**: Paste your token

### 3. Generate SSH Key
Click "Generate SSH Key" to create a new key pair

### 4. Upload to GitHub
Click "Upload to GitHub" to add the key to your account

### 5. Test Connection
Click "Test SSH Connection" to verify setup

### 6. View Configuration
Click "View SSH Config" to see your SSH config file

---

**Note**: Keep your PAT secure and never share it publicly.`)
		instructions.Wrapping = fyne.TextWrapWord

		scrollInstructions := container.NewVScroll(instructions)
		scrollInstructions.SetMinSize(fyne.NewSize(550, 400))

		// Create hyperlink
		linkURL, _ := url.Parse("https://github.com/settings/tokens")
		link := widget.NewHyperlink("Open GitHub Token Settings", linkURL)

		modalContent := container.NewVBox(
			scrollInstructions,
			widget.NewSeparator(),
			container.NewCenter(link),
		)

		dialog.ShowCustom("Help & Instructions", "Close", modalContent, w)
	})

	// Footer
	separator3 := widget.NewSeparator()
	footerLabel := widget.NewLabel("SSH Directory: " + sshDir)
	footerLabel.TextStyle.Italic = true

	// Main layout
	content := container.NewVBox(
		container.NewPadded(
			container.NewVBox(
				titleLabel,
				subtitleLabel,
			),
		),
		separator1,
		container.NewPadded(formGrid),
		separator2,
		container.NewPadded(buttonGrid),
		container.NewPadded(viewConfigBtn),
		container.NewPadded(helpBtn),
		separator3,
		container.NewPadded(footerLabel),
	)

	scroll := container.NewVScroll(content)
	w.SetContent(scroll)
	w.SetIcon(theme.ComputerIcon())
	w.ShowAndRun()
}

// getSSHDirectory returns the .ssh directory path based on the OS
func getSSHDirectory() (string, error) {
	var homeDir string
	
	switch runtime.GOOS {
	case "windows":
		homeDir = os.Getenv("USERPROFILE")
		if homeDir == "" {
			return "", fmt.Errorf("USERPROFILE environment variable not set")
		}
	case "linux", "darwin":
		homeDir = os.Getenv("HOME")
		if homeDir == "" {
			return "", fmt.Errorf("HOME environment variable not set")
		}
	default:
		return "", fmt.Errorf("unsupported operating system: %s", runtime.GOOS)
	}
	
	return filepath.Join(homeDir, ".ssh"), nil
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
	if f != nil {
		defer f.Close()
		f.WriteString(entry)
	}
}