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
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

var logContainer *fyne.Container
var mainWindow fyne.Window

func main() {
	// Check for admin privileges on Windows
	if runtime.GOOS == "windows" {
		if !isAdmin() {
			// Relaunch with admin privileges
			err := runAsAdmin()
			if err != nil {
				// Show error dialog before exiting
				a := app.New()
				w := a.NewWindow("Admin Required")
				dialog.ShowError(fmt.Errorf(" Failed to elevate privileges: %v\n\nPlease run as administrator", err), w)
				w.ShowAndRun()
			}
			return
		}
	}

	a := app.New()
	w := a.NewWindow("GitHub SSH Manager")
	w.Resize(fyne.NewSize(900, 700))
	mainWindow = w

	// Initialize logger container
	logContainer = container.NewVBox()

	logInfo("Application started")
	logInfo(fmt.Sprintf("Operating System: %s", runtime.GOOS))
	if runtime.GOOS == "windows" && isAdmin() {
		logSuccess("Running with administrator privileges")
	}

	// Determine SSH directory cross-platform
	sshDir, err := getSSHDirectory()
	if err != nil {
		logError(fmt.Sprintf("Failed to determine SSH directory: %v", err))
		dialog.ShowError(err, w)
		return
	}
	logInfo(fmt.Sprintf("SSH Directory: %s", sshDir))

	// Ensure .ssh directory exists with proper permissions
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		logError(fmt.Sprintf("Failed to create .ssh directory: %v", err))
		dialog.ShowError(fmt.Errorf("failed to create .ssh directory: %v", err), w)
		return
	}
	logSuccess("SSH directory verified/created")

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
			logError("Generate Key: Label is empty")
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		hostAlias := strings.TrimSpace(hostEntry.Text)
		if hostAlias == "" {
			logError("Generate Key: Host alias is empty")
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		logInfo(fmt.Sprintf("Generating SSH key for label: %s, host: %s", label, hostAlias))

		keyPath := filepath.Join(sshDir, "id_ed25519_"+label)
		if _, err := os.Stat(keyPath); err == nil {
			logWarning(fmt.Sprintf("Key already exists: %s", keyPath))
			dialog.ShowInformation("Info", "Key already exists: "+keyPath, w)
			return
		}

		// Generate the SSH key
		logInfo("Executing ssh-keygen command...")
		cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-C", label+"@github", "-f", keyPath, "-N", "")
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			logError(fmt.Sprintf("ssh-keygen failed: %v - %s", err, stderr.String()))
			dialog.ShowError(fmt.Errorf("keygen failed: %v\n%s", err, stderr.String()), w)
			return
		}
		logSuccess(fmt.Sprintf("SSH key pair generated: %s", keyPath))

		// Add GitHub to known_hosts
		logInfo("Adding github.com to known_hosts...")
		knownHostsPath := filepath.Join(sshDir, "known_hosts")
		scanCmd := exec.Command("ssh-keyscan", "github.com")
		out, err := scanCmd.Output()
		if err == nil {
			f, _ := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if f != nil {
				defer f.Close()
				f.Write(out)
				logSuccess("GitHub added to known_hosts")
			}
		} else {
			logWarning(fmt.Sprintf("Failed to add GitHub to known_hosts: %v", err))
		}

		// Update SSH config with user-defined host alias
		logInfo(fmt.Sprintf("Updating SSH config with host alias: %s", hostAlias))
		appendConfig(configFile, hostAlias, "github.com", keyPath)
		logSuccess("SSH config updated successfully")
		
		dialog.ShowInformation("Success", fmt.Sprintf("✓ SSH key generated\n✓ Config updated\n✓ GitHub added to known_hosts\n\nKey: %s", keyPath), w)
	})
	genBtn.Importance = widget.HighImportance

	showPubBtn := widget.NewButtonWithIcon("Show Public Key", theme.VisibilityIcon(), func() {
		label := strings.TrimSpace(labelEntry.Text)
		if label == "" {
			logError("Show Public Key: Label is empty")
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		
		logInfo(fmt.Sprintf("Reading public key for label: %s", label))
		pubKeyPath := filepath.Join(sshDir, "id_ed25519_"+label+".pub")
		pub, err := ioutil.ReadFile(pubKeyPath)
		if err != nil {
			logError(fmt.Sprintf("Cannot read public key: %v", err))
			dialog.ShowError(fmt.Errorf("cannot read public key: %v", err), w)
			return
		}
		logSuccess(fmt.Sprintf("Public key loaded: %s", pubKeyPath))

		pubEntry := widget.NewMultiLineEntry()
		pubEntry.SetText(string(pub))
		pubEntry.SetMinRowsVisible(6)
		pubEntry.Wrapping = fyne.TextWrapBreak

		copyBtn := widget.NewButtonWithIcon("Copy to Clipboard", theme.ContentCopyIcon(), func() {
			a.Clipboard().SetContent(string(pub))
			logInfo("Public key copied to clipboard")
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
			logError("Upload Key: Label is empty")
			dialog.ShowError(fmt.Errorf("please enter a label"), w)
			return
		}
		token := strings.TrimSpace(tokenEntry.Text)
		if token == "" {
			logError("Upload Key: GitHub PAT is empty")
			dialog.ShowError(fmt.Errorf("please enter your GitHub Personal Access Token"), w)
			return
		}
		hostAlias := strings.TrimSpace(hostEntry.Text)
		if hostAlias == "" {
			logError("Upload Key: Host alias is empty")
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		logInfo(fmt.Sprintf("Uploading SSH key to GitHub for label: %s", label))

		pubKeyPath := filepath.Join(sshDir, "id_ed25519_"+label+".pub")
		pub, err := ioutil.ReadFile(pubKeyPath)
		if err != nil {
			logError(fmt.Sprintf("No public key found: %v", err))
			dialog.ShowError(fmt.Errorf("no public key found (generate key first): %v", err), w)
			return
		}

		apiURL := "https://api.github.com/user/keys"
		keyTitle := label + "-" + hostAlias
		jsonData := fmt.Sprintf(`{"title":"%s","key":"%s"}`, keyTitle, strings.TrimSpace(string(pub)))
		
		logInfo(fmt.Sprintf("Making API request to GitHub (key title: %s)...", keyTitle))
		cmd := exec.Command("curl", "-s", "-H", "Authorization: token "+token,
			"-H", "Accept: application/vnd.github+json", apiURL, "-d", jsonData)

		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			logError(fmt.Sprintf("Upload failed: %v", err))
			dialog.ShowError(fmt.Errorf("upload failed: %v", err), w)
			return
		}

		// Parse JSON response
		var resp map[string]interface{}
		if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
			logWarning(fmt.Sprintf("Could not parse GitHub API response: %v", err))
			dialog.ShowInformation("Response", out.String(), w)
			return
		}

		// Show user-friendly message
		if resp["id"] != nil {
			logSuccess(fmt.Sprintf("SSH key uploaded successfully (ID: %.0f)", resp["id"]))
			dialog.ShowInformation("Success", fmt.Sprintf("✓ SSH Key uploaded successfully!\n\nTitle: %s\nID: %.0f", resp["title"], resp["id"]), w)
		} else if resp["message"] != nil {
			logError(fmt.Sprintf("GitHub API Error: %s", resp["message"]))
			dialog.ShowError(fmt.Errorf("GitHub API Error: %s", resp["message"]), w)
		} else {
			logWarning("Unexpected API response received")
			dialog.ShowInformation("Response", out.String(), w)
		}
	})
	uploadBtn.Importance = widget.HighImportance

	testBtn := widget.NewButtonWithIcon("Test SSH Connection", theme.ConfirmIcon(), func() {
		hostAlias := strings.TrimSpace(hostEntry.Text)
		if hostAlias == "" {
			logError("Test SSH: Host alias is empty")
			dialog.ShowError(fmt.Errorf("please enter a host alias"), w)
			return
		}

		logInfo(fmt.Sprintf("Testing SSH connection to git@%s...", hostAlias))
		cmd := exec.Command("ssh", "-T", "git@"+hostAlias)
		var out, stderr bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &stderr
		
		// SSH to GitHub always returns exit code 1 with success message in stderr
		cmd.Run()
		
		combinedOutput := stderr.String() + out.String()
		if strings.Contains(combinedOutput, "successfully authenticated") {
			logSuccess(fmt.Sprintf("SSH connection successful to %s", hostAlias))
			dialog.ShowInformation("Success", "✓ SSH connection successful!\n\n"+combinedOutput, w)
		} else {
			logError(fmt.Sprintf("SSH test failed: %s", combinedOutput))
			dialog.ShowError(fmt.Errorf("SSH test failed:\n%s", combinedOutput), w)
		}
	})

		viewConfigBtn := widget.NewButtonWithIcon("View SSH Config", theme.DocumentIcon(), func() {
		logInfo("Opening SSH config viewer...")

		// Ensure config file exists (create empty if not)
		if _, err := os.Stat(configFile); os.IsNotExist(err) {
			if f, createErr := os.Create(configFile); createErr == nil {
				f.Close()
				os.Chmod(configFile, 0600)
				logInfo("Created empty SSH config file")
			}
		}

		cfg, err := os.ReadFile(configFile)
		if err != nil {
			logError(fmt.Sprintf("Cannot read SSH config: %v", err))
			dialog.ShowError(fmt.Errorf("cannot read SSH config: %v", err), w)
			return
		}

		content := string(cfg)
		if content == "" {
			content = "# SSH config file is empty\n# Generate a key to add entries\n"
		}

		logSuccess(fmt.Sprintf("SSH config loaded (%d bytes)", len(cfg)))

		cfgLabel := widget.NewLabel(content)
		cfgLabel.Wrapping = fyne.TextWrapWord
		cfgLabel.TextStyle.Monospace = true

		scrollContainer := container.NewVScroll(cfgLabel)
		scrollContainer.SetMinSize(fyne.NewSize(600, 400))

		copyBtn := widget.NewButtonWithIcon("Copy to Clipboard", theme.ContentCopyIcon(), func() {
			a.Clipboard().SetContent(content)
			logInfo("SSH config copied to clipboard")
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
		logInfo("Opening help dialog")
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

	// Logger section
	separator3 := widget.NewSeparator()
	loggerLabel := widget.NewLabelWithStyle("Activity Log", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	
	logScroll := container.NewVScroll(logContainer)
	logScroll.SetMinSize(fyne.NewSize(0, 150))

	// Logger controls
	clearLogBtn := widget.NewButtonWithIcon("Clear Log", theme.DeleteIcon(), func() {
		logContainer.Objects = nil
		logContainer.Refresh()
		logInfo("Log cleared")
	})

	saveLogBtn := widget.NewButtonWithIcon("Save Log", theme.DocumentSaveIcon(), func() {
		logInfo("Opening save dialog...")
		saveDialog := dialog.NewFileSave(func(writer fyne.URIWriteCloser, err error) {
			if err != nil {
				logError(fmt.Sprintf("Save dialog error: %v", err))
				dialog.ShowError(err, w)
				return
			}
			if writer == nil {
				logWarning("Save operation cancelled")
				return
			}
			defer writer.Close()

			timestamp := time.Now().Format("2006-01-02 15:04:05")
			header := fmt.Sprintf("GitHub SSH Manager - Activity Log\nGenerated: %s\n%s\n\n", timestamp, strings.Repeat("=", 60))
			
			// Extract text from log container
			var logText strings.Builder
			for _, obj := range logContainer.Objects {
				if label, ok := obj.(*canvas.Text); ok {
					logText.WriteString(label.Text)
					logText.WriteString("\n")
				}
			}
			
			content := header + logText.String()
			_, err = writer.Write([]byte(content))
			if err != nil {
				logError(fmt.Sprintf("Failed to write log file: %v", err))
				dialog.ShowError(fmt.Errorf("failed to save log: %v", err), w)
				return
			}
			
			logSuccess(fmt.Sprintf("Log saved to: %s", writer.URI().Path()))
			dialog.ShowInformation("Saved", "✓ Log saved successfully!", w)
		}, w)
		
		saveDialog.SetFileName(fmt.Sprintf("ssh-manager-log-%s.txt", time.Now().Format("2006-01-02-150405")))
		saveDialog.Show()
	})
	saveLogBtn.Importance = widget.HighImportance

	logControls := container.NewHBox(
		loggerLabel,
		layout.NewSpacer(),
		clearLogBtn,
		saveLogBtn,
	)

	loggerSection := container.NewBorder(
		logControls,
		nil,
		nil,
		nil,
		logScroll,
	)

	// Footer
	separator4 := widget.NewSeparator()
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
		container.NewPadded(loggerSection),
		separator4,
		container.NewPadded(footerLabel),
	)

	scroll := container.NewVScroll(content)
	w.SetContent(scroll)
	w.SetIcon(theme.ComputerIcon())
	w.ShowAndRun()
}

// Logging functions with theme-aware colors
func logInfo(message string) {
	timestamp := time.Now().Format("15:04:05")
	logMessage := fmt.Sprintf("[%s] ℹ INFO: %s", timestamp, message)
	wrapped := wrapText(logMessage, 110)

	text := canvas.NewText(wrapped, theme.Color(theme.ColorNamePrimary))
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	logContainer.Add(text)
	logContainer.Refresh()

	if mainWindow != nil {
		mainWindow.Canvas().Refresh(logContainer)
	}
}

func logSuccess(message string) {
	timestamp := time.Now().Format("15:04:05")
	logMessage := fmt.Sprintf("[%s] ✓ SUCCESS: %s", timestamp, message)
	wrapped := wrapText(logMessage, 110)

	text := canvas.NewText(wrapped, theme.SuccessColor())
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	logContainer.Add(text)
	logContainer.Refresh()

	if mainWindow != nil {
		mainWindow.Canvas().Refresh(logContainer)
	}
}

func logError(message string) {
	timestamp := time.Now().Format("15:04:05")
	logMessage := fmt.Sprintf("[%s] ✗ ERROR: %s", timestamp, message)
	wrapped := wrapText(logMessage, 110)

	text := canvas.NewText(wrapped, theme.Color(theme.ColorNameError))
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	logContainer.Add(text)
	logContainer.Refresh()

	if mainWindow != nil {
		mainWindow.Canvas().Refresh(logContainer)
	}
}

func logWarning(message string) {
	timestamp := time.Now().Format("15:04:05")
	logMessage := fmt.Sprintf("[%s] ⚠ WARNING: %s", timestamp, message)
	wrapped := wrapText(logMessage, 110)

	text := canvas.NewText(wrapped, theme.Color(theme.ColorNameWarning))
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	logContainer.Add(text)
	logContainer.Refresh()

	if mainWindow != nil {
		mainWindow.Canvas().Refresh(logContainer)
	}
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

// toUnixPath converts Windows paths to Unix-style paths for SSH config
func toUnixPath(path string) string {
	if runtime.GOOS == "windows" {
		// Replace backslashes with forward slashes
		path = strings.ReplaceAll(path, "\\", "/")
		// Handle Windows drive letters (C: -> /c/)
		if len(path) >= 2 && path[1] == ':' {
			path = "/" + strings.ToLower(string(path[0])) + path[2:]
		}
	}
	return path
}

// appendConfig ensures ~/.ssh/config contains a Host block for this key
func appendConfig(configFile, hostAlias, hostName, keyPath string) {
	// Read existing content to check for duplicate Host entry
	var hostExists bool
	var configContent string // will hold file content as string for searching

	if data, err := os.ReadFile(configFile); err == nil {
		configContent = string(data)
		// More robust check for existing Host block
		hostExists = strings.Contains(configContent, "\nHost "+hostAlias+"\n") ||
		             strings.Contains(configContent, "\nHost "+hostAlias+" ") ||
		             strings.HasPrefix(configContent, "Host "+hostAlias)
	} else {
		// File doesn't exist — that's okay, we'll create it
		configContent = ""
		hostExists = false
	}

	if hostExists {
		logWarning(fmt.Sprintf("Host alias '%s' already exists in config", hostAlias))
		return
	}

	// Convert Windows path to Unix-style and quote it safely
	unixKeyPath := toUnixPath(keyPath)
	quotedKeyPath := fmt.Sprintf(`"%s"`, unixKeyPath)

	entry := fmt.Sprintf("\nHost %s\n  HostName %s\n  IdentityFile %s\n  AddKeysToAgent yes\n  IdentitiesOnly yes\n",
		hostAlias, hostName, quotedKeyPath)

	// Append (or create) the config file
	f, err := os.OpenFile(configFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		logError(fmt.Sprintf("Failed to open config file for writing: %v", err))
		return
	}
	defer f.Close()

	if _, err := f.WriteString(entry); err != nil {
		logError(fmt.Sprintf("Failed to write to config file: %v", err))
	} else {
		logSuccess("SSH config updated successfully")
	}
}

// Windows admin privilege functions
func isAdmin() bool {
	if runtime.GOOS != "windows" {
		return true // Not Windows, assume sufficient privileges
	}
	
	// Try to open a privileged path to test admin rights
	_, err := os.Open("\\\\.\\PHYSICALDRIVE0")
	return err == nil
}

func runAsAdmin() error {
	if runtime.GOOS != "windows" {
		return nil
	}
	
	// Get the executable path
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	
	// Use PowerShell to elevate
	verb := "Start-Process"
	args := fmt.Sprintf("-Verb RunAs -FilePath '%s'", exe)
	
	cmd := exec.Command("powershell", "-Command", verb, args)
	err = cmd.Start()
	
	return err
}

// wrapText wraps long log lines for clean display
func wrapText(text string, maxWidth int) string {
	if len(text) <= maxWidth {
		return text
	}

	var builder strings.Builder
	words := strings.Fields(text)
	currentLen := 0

	for _, word := range words {
		wordLen := len(word)
		if currentLen+wordLen+1 > maxWidth && currentLen > 0 {
			builder.WriteString("\n        ") // indent wrapped lines
			currentLen = 8
		} else if currentLen > 0 {
			builder.WriteString(" ")
			currentLen++
		}

		builder.WriteString(word)
		currentLen += wordLen
	}

	return builder.String()
}