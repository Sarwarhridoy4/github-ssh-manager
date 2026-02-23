package main

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

func buildUI(a fyne.App, w fyne.Window, sshDir string) {
	configFile := filepath.Join(sshDir, "config")
	logContainer := container.NewVBox()
	log := newLogger(logContainer, w)
	log.info("Application started")
	log.info("Operating system: " + runtime.GOOS)
	log.info("SSH directory: " + sshDir)

	labelEntry := widget.NewEntry()
	labelEntry.SetPlaceHolder("personal, work, company")

	hostEntry := widget.NewEntry()
	hostEntry.SetPlaceHolder("github-personal")

	tokenEntry := widget.NewPasswordEntry()
	tokenEntry.SetPlaceHolder("GitHub token (scope: admin:public_key, repo optional)")

	themeSelect := widget.NewSelect([]string{"System (Default)", "Light", "Dark"}, func(choice string) {
		applyThemeChoice(a, choice)
		log.info("Theme changed to: " + choice)
	})
	themeSelect.SetSelected("System (Default)")

	status := widget.NewRichTextFromMarkdown("`Ready`")

	setStatus := func(message string) {
		status.ParseMarkdown("`" + strings.ReplaceAll(message, "`", "'") + "`")
		status.Refresh()
	}

	validateInputs := func(requirePAT bool) (string, string, string, error) {
		label := strings.TrimSpace(labelEntry.Text)
		alias := strings.TrimSpace(hostEntry.Text)
		token := strings.TrimSpace(tokenEntry.Text)

		if err := validateLabel(label); err != nil {
			return "", "", "", err
		}
		if err := validateHostAlias(alias); err != nil {
			return "", "", "", err
		}
		if requirePAT {
			if err := requireToken(token); err != nil {
				return "", "", "", err
			}
		}
		return label, alias, token, nil
	}

	generateBtn := widget.NewButtonWithIcon("Generate Key", theme.DocumentCreateIcon(), func() {
		label, alias, _, err := validateInputs(false)
		if err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}

		setStatus("Generating key pair")
		keyPath, err := generateKeyPair(sshDir, label)
		if err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			setStatus("Failed")
			return
		}
		log.success("SSH key generated: " + keyPath)

		if err := ensureGitHubKnownHost(sshDir); err != nil {
			log.warn("Could not update known_hosts: " + err.Error())
		} else {
			log.success("github.com present in known_hosts")
		}

		if err := ensureSSHConfigEntry(configFile, alias, keyPath); err != nil {
			dialog.ShowError(err, w)
			log.err("Failed to update SSH config: " + err.Error())
			setStatus("Failed")
			return
		}
		log.success("SSH config updated for host " + alias)
		setStatus("Key generated and config updated")
		dialog.ShowInformation("Success", "SSH key created and SSH config updated.", w)
	})
	generateBtn.Importance = widget.HighImportance

	showPublicBtn := widget.NewButtonWithIcon("Show Public Key", theme.VisibilityIcon(), func() {
		label := strings.TrimSpace(labelEntry.Text)
		if err := validateLabel(label); err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}

		pub, err := readPublicKey(sshDir, label)
		if err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}

		entry := widget.NewMultiLineEntry()
		entry.SetText(pub)
		entry.Wrapping = fyne.TextWrapBreak
		entry.SetMinRowsVisible(5)

		copyBtn := widget.NewButtonWithIcon("Copy", theme.ContentCopyIcon(), func() {
			a.Clipboard().SetContent(pub)
			log.success("Public key copied to clipboard")
		})

		entry.Disable()
		body := container.NewBorder(
			container.NewVBox(
				widget.NewLabelWithStyle("Public key for "+label, fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
				widget.NewLabel("Add this to GitHub -> SSH and GPG keys"),
				widget.NewSeparator(),
			),
			container.NewHBox(layout.NewSpacer(), copyBtn),
			nil,
			nil,
			entry,
		)
		d := dialog.NewCustom("Public Key", "Close", body, w)
		d.Resize(fyne.NewSize(820, 420))
		d.Show()
	})

	uploadBtn := widget.NewButtonWithIcon("Upload to GitHub", theme.UploadIcon(), func() {
		label, alias, token, err := validateInputs(true)
		if err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}

		pub, err := readPublicKey(sshDir, label)
		if err != nil {
			dialog.ShowError(fmt.Errorf("generate key first: %w", err), w)
			log.err("Public key not found for " + label)
			return
		}

		setStatus("Uploading key to GitHub")
		resp, err := uploadKeyToGitHub(token, label+"-"+alias, pub)
		if err != nil {
			msg := err.Error()
			if resp != nil && resp.Message != "" {
				msg = resp.Message
			}
			dialog.ShowError(fmt.Errorf("GitHub upload failed: %s", msg), w)
			log.err("GitHub upload failed: " + msg)
			setStatus("Upload failed")
			return
		}

		log.success(fmt.Sprintf("Key uploaded to GitHub (ID: %d)", resp.ID))
		setStatus("Key uploaded")
		tokenEntry.SetText("")
		dialog.ShowInformation("Uploaded", fmt.Sprintf("Key uploaded successfully.\nTitle: %s\nID: %d", resp.Title, resp.ID), w)
	})
	uploadBtn.Importance = widget.HighImportance

	testBtn := widget.NewButtonWithIcon("Test SSH", theme.ConfirmIcon(), func() {
		alias := strings.TrimSpace(hostEntry.Text)
		if err := validateHostAlias(alias); err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}

		setStatus("Testing SSH connection")
		output, err := testSSHConnection(alias)
		if err != nil {
			log.err(output)
			dialog.ShowError(fmt.Errorf("%s", output), w)
			setStatus("SSH test failed")
			return
		}
		log.success("SSH connection verified for " + alias)
		setStatus("SSH test passed")
		dialog.ShowInformation("Connection OK", output, w)
	})

	viewConfigBtn := widget.NewButtonWithIcon("View SSH Config", theme.DocumentIcon(), func() {
		if err := ensureConfigFile(configFile); err != nil {
			dialog.ShowError(err, w)
			log.err("Could not prepare config file: " + err.Error())
			return
		}
		cfg, err := osRead(configFile)
		if err != nil {
			dialog.ShowError(err, w)
			log.err(err.Error())
			return
		}
		if strings.TrimSpace(cfg) == "" {
			cfg = "# SSH config is empty\n"
		}

		cfgText := widget.NewMultiLineEntry()
		cfgText.SetText(cfg)
		cfgText.Wrapping = fyne.TextWrapOff
		cfgText.Disable()
		cfgText.SetMinRowsVisible(14)

		copyBtn := widget.NewButtonWithIcon("Copy Config", theme.ContentCopyIcon(), func() {
			a.Clipboard().SetContent(cfg)
			log.success("SSH config copied to clipboard")
		})
		body := container.NewBorder(
			container.NewVBox(
				widget.NewLabelWithStyle("SSH Config", fyne.TextAlignLeading, fyne.TextStyle{Bold: true}),
				widget.NewLabel(configFile),
				widget.NewSeparator(),
			),
			container.NewHBox(layout.NewSpacer(), copyBtn),
			nil,
			nil,
			cfgText,
		)
		d := dialog.NewCustom("SSH Config", "Close", body, w)
		d.Resize(fyne.NewSize(900, 520))
		d.Show()
	})

	helpBtn := widget.NewButtonWithIcon("Instructions", theme.HelpIcon(), func() {
		instructions := widget.NewRichTextFromMarkdown(`## Fast Setup

1. Create a GitHub token with scope **admin:public_key** + **repo** (optional).
2. Enter label + host alias and generate key.
3. Upload the key to GitHub.
4. Test SSH connection.

## Field Guide

- **Label**: Friendly name for the key (e.g., "work", "personal"). Used to name the key in GitHub.
- **Host Alias**: The SSH host name you will use in git URLs. This is the most important field.

## Host Alias Details

Use a unique alias per GitHub account, for example:
- ` + "`github-work`" + `, ` + "`github-personal`" + `, ` + "`gh-company`" + `

Your SSH config will look like:

` + "```" + `
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/<label>-<alias>
  AddKeysToAgent yes
  IdentitiesOnly yes
` + "```" + `

Then use it in git remotes like:
- ` + "`git@github-work:org/repo.git`" + `

Notes:
- Alias must be 1-128 characters using letters, numbers, ".", "-", "_".
- Alias must not be ` + "`github.com`" + `.
- If the alias already exists in ` + "`~/.ssh/config`" + `, it will not be duplicated.
- You can view the generated config via **View Config**.

## Token & Security Notes

- Token is used only for a direct HTTPS API call.
- Token is cleared from the field after upload.
- Keys and config stay in your local ` + "`~/.ssh`" + `.`)
		instructions.Wrapping = fyne.TextWrapWord
		linkURL, _ := url.Parse("https://github.com/settings/tokens")
		link := widget.NewHyperlink("Open GitHub Token Settings", linkURL)
		copyScopeBtn := widget.NewButtonWithIcon("Copy Required Scopes", theme.ContentCopyIcon(), func() {
			a.Clipboard().SetContent("admin:public_key, repo")
			log.success("Token scopes copied to clipboard")
		})
		scroll := container.NewVScroll(instructions)
		scroll.SetMinSize(fyne.NewSize(760, 420))
		body := container.NewVBox(
			scroll,
			widget.NewSeparator(),
			container.NewHBox(link, layout.NewSpacer(), copyScopeBtn),
		)
		d := dialog.NewCustom("Instructions", "Close", body, w)
		d.Resize(fyne.NewSize(800, 520))
		d.Show()
	})

	clearLogBtn := widget.NewButtonWithIcon("Clear Log", theme.DeleteIcon(), func() {
		logContainer.Objects = nil
		logContainer.Refresh()
		log.info("Log cleared")
	})

	saveLogBtn := widget.NewButtonWithIcon("Save Log", theme.DocumentSaveIcon(), func() {
		saveDialog := dialog.NewFileSave(func(writer fyne.URIWriteCloser, err error) {
			if err != nil {
				dialog.ShowError(err, w)
				return
			}
			if writer == nil {
				return
			}
			defer writer.Close()

			var b strings.Builder
			b.WriteString("GitHub SSH Manager - Activity Log\n")
			b.WriteString("Generated: " + time.Now().Format("2006-01-02 15:04:05") + "\n\n")
			for _, obj := range logContainer.Objects {
				if t, ok := obj.(*canvas.Text); ok {
					b.WriteString(t.Text + "\n")
				}
			}
			if _, err := writer.Write([]byte(b.String())); err != nil {
				dialog.ShowError(err, w)
				return
			}
			log.success("Log saved: " + writer.URI().Path())
		}, w)
		saveDialog.SetFileName("ssh-manager-log-" + time.Now().Format("2006-01-02-150405") + ".txt")
		saveDialog.Show()
	})

	actions := container.NewGridWithColumns(2, generateBtn, uploadBtn, showPublicBtn, testBtn)

	inputCard := widget.NewCard(
		"Account Setup",
		"Create and bind per-account SSH identities",
		container.New(layout.NewFormLayout(),
			widget.NewLabel("Label"), labelEntry,
			widget.NewLabel("Host Alias"), hostEntry,
			widget.NewLabel("GitHub Token"), tokenEntry,
			widget.NewLabel("Theme"), themeSelect,
		),
	)

	actionsCard := widget.NewCard(
		"Actions",
		"Recommended flow: Generate -> Upload -> Test",
		container.NewVBox(actions, container.NewGridWithColumns(2, viewConfigBtn, helpBtn)),
	)

	logScroll := container.NewVScroll(logContainer)
	logScroll.SetMinSize(fyne.NewSize(0, 180))
	logCard := widget.NewCard("Activity Log", "Operational events and validation messages", logScroll)

	headline := widget.NewRichTextFromMarkdown("# GitHub SSH Manager\nSecure multi-account SSH setup with cross-platform path handling.")
	statusBar := container.NewBorder(nil, nil, widget.NewLabel("Status:"), nil, status)
	footer := container.NewHBox(widget.NewLabel("SSH Directory: "+sshDir), layout.NewSpacer(), clearLogBtn, saveLogBtn)

	content := container.NewVBox(
		headline,
		widget.NewSeparator(),
		inputCard,
		actionsCard,
		statusBar,
		logCard,
		widget.NewSeparator(),
		footer,
	)

	scroll := container.NewVScroll(container.NewPadded(content))
	w.SetContent(scroll)
	w.SetIcon(theme.ComputerIcon())
}

func osRead(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
