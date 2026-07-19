# AGENT.md

## Project Overview

Cross-platform GUI desktop application built with **Go** and **Fyne v2.8.0** for managing multiple GitHub SSH keys. Generates ed25519 keys, uploads to GitHub via API, tests SSH connections, and manages `~/.ssh/config`.

- **Module**: `github.com/Sarwarhridoy4/github-ssh-manager`
- **Go version**: 1.25.0
- **License**: MIT
- **Package layout**: Single `package main` at root with six `internal/` sub-packages

## File Organization

| Path | Responsibility |
|------|---------------|
| `main.go` | Entry point; resolves SSH directory, delegates to `internal/ui` |
| `internal/ui/ui.go` | Fyne UI layout, widgets, dialogs, event handlers |
| `internal/ssh/ssh.go` | SSH key generation, config file parsing, known_hosts, connection testing |
| `internal/github/github.go` | GitHub REST API client for SSH key upload |
| `internal/validation/validation.go` | Input validation (label, host alias, token) |
| `internal/logging/logging.go` | In-memory activity logger with color-coded output |
| `internal/theme/theme.go` | System/Light/Dark theme switching via custom theme wrapper |

Assets live under `assets/` (icons) and `screenshots/` (README images).

## Build & Run

```bash
go mod tidy
go run .
```

Build binary:
```bash
go build -o github-ssh-manager
```

Cross-compile:
```bash
GOOS=linux GOARCH=amd64 go build -o github-ssh-manager
```

Packaging uses `fyne.io/tools/cmd/fyne` and `build.sh`. No CI/CD is configured.

### `build.sh`

The build script follows the official Fyne packaging approach and produces three distributable formats in one run:

```bash
./build.sh [--version vX.Y.Z] [--build N]
```

**Auto-installed dependencies**: `go`, `tar`, `dpkg-deb`, `imagemagick`, `fyne` CLI.

**Outputs in `dist/`**:
- `*.tar.gz` — Fyne-standard Linux tarball (extracted from `usr/local/` layout)
- `*.deb` — Debian package with desktop entry, icons, and control metadata
- `*.AppImage` — Universal Linux package (downloads `appimagetool` automatically if missing)
- `SHA256SUMS` / `MD5SUMS` — checksums for verification

The script auto-detects the system package manager (`apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`) and installs missing tools with `sudo`.

## Code Style

- **Standard Go conventions**: exported functions/types only when needed; unexported by default
- **No comments** unless explicitly requested
- **Error wrapping**: use `fmt.Errorf("context: %w", err)`; avoid bare `errors.New` chains when wrapping
- **Internal packages**: all domain logic lives in `internal/` sub-packages; `main.go` only wires dependencies
- **Package boundaries**: each `internal/` package owns one concern (UI, SSH, GitHub, validation, logging, theme)
- **Imports**: standard library first, then third-party, then internal; group with blank lines if needed

## Key Conventions & Patterns

### Fyne UI (`internal/ui`)
- All UI construction happens in `BuildUI(a fyne.App, w fyne.Window, sshDir string)`
- Dialogs use `dialog.NewCustom`, `dialog.ShowError`, `dialog.ShowInformation`
- Buttons use `widget.NewButtonWithIcon` with `theme.*Icon()` icons
- Layout: `container.NewVBox` with `widget.NewCard` for sections; `container.NewVScroll` for scrollable content
- Status updates via a closure `setStatus` that updates a `widget.NewRichTextFromMarkdown`
- Event handlers call into `internal/ssh`, `internal/github`, `internal/validation`, `internal/logging`, and `apptheme` (aliased internal theme)

### SSH Operations (`internal/ssh`)
- `ssh-keygen`, `ssh-keyscan`, and `ssh` are invoked via `exec.Command`
- Key paths: `~/.ssh/id_ed25519_<label>` (private), `.pub` suffix for public
- Config entries are appended; deduplication handled by `hasHostAlias`
- File permissions: `0o700` for `.ssh/`, `0o600` for private keys/config, `0o644` for public keys
- Windows skips chmod operations (`runtime.GOOS != "windows"` guards)

### GitHub API (`internal/github`)
- Single endpoint: `POST https://api.github.com/user/keys`
- Bearer token auth; token cleared from UI after successful upload
- `http.Client` timeout: 20 seconds
- Response decoding into `KeyResponse`; errors surfaced via `Message` field or HTTP status

### Validation (`internal/validation`)
- Regex patterns precompiled as package vars: `labelPattern`, `hostPattern`
- `ValidateLabel`, `ValidateHostAlias`, `RequireToken` return `error`
- Host alias must not equal `github.com` (case-insensitive)

### Logging (`internal/logging`)
- `Logger` struct wraps a `fyne.Container` and `fyne.Window`
- Levels: `Info`, `Success`, `Warn`, `Err`
- Timestamps in `15:04:05` format; monospace `canvas.Text`
- All mutations wrapped in `fyne.Do()` for thread safety under Fyne v2.8+
- Logs are in-memory only; export via "Save Log" button writes to user-selected file

### Theme (`internal/theme`)
- Custom `forcedVariantTheme` embeds `fyne.Theme` and overrides `Color` to force variant
- Choices: System (default, no override), Light, Dark
- Imported as `apptheme` in `internal/ui` to avoid collision with `fyne.io/fyne/v2/theme`

## Security Considerations

- **Token handling**: PAT is used only for a single HTTPS API call, then immediately cleared from the UI field. No token is persisted to disk.
- **SSH keys**: Stored in `~/.ssh/` with restrictive permissions. App does not read private key contents.
- **No secrets in logs**: Only public key titles and operation outcomes are logged.
- **SSH config hardening**: Generated entries include `StrictHostKeyChecking accept-new`, `ServerAliveInterval 20`, and `ServerAliveCountMax 2`.

## Threading Model (Fyne v2.8+)

- All Fyne widget mutations must occur on the main UI thread.
- `main.go` uses `fyne.Do()` for pre-`ShowAndRun` error dialogs.
- `internal/logging` wraps all container updates in `fyne.Do()`.
- Button handlers run on the UI thread by default; additional `fyne.Do()` wrappers are used defensively.

## Testing

- No test files exist in the project currently.
- If adding tests, use standard Go testing (`*_test.go`, `go test ./...`).
- Mock `exec.Command` and HTTP clients for unit tests rather than invoking real `ssh-keygen` or GitHub API.
- GUI logic in `internal/ui` is difficult to unit test; prefer testing domain logic in `internal/ssh`, `internal/github`, and `internal/validation`.

## Dependencies

- **Direct**: `fyne.io/fyne/v2 v2.8.0`
- All other dependencies are indirect and managed via `go.mod`

## What NOT to Do

- Do not reorganize packages or flatten `internal/` back to root without explicit request
- Do not add network calls or external services beyond the existing GitHub API upload
- Do not persist secrets, tokens, or private key contents
- Do not add a database or config file for application state
- Do not introduce a CLI mode or headless operation; this is a GUI-only app
- Do not change the single-entry-point `main.go` structure unless asked
