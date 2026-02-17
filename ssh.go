package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func getSSHDirectory() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil || homeDir == "" {
		return "", fmt.Errorf("failed to resolve user home directory: %w", err)
	}
	return filepath.Join(homeDir, ".ssh"), nil
}

func ensureSSHDirectory(sshDir string) error {
	if err := os.MkdirAll(sshDir, 0o700); err != nil {
		return err
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(sshDir, 0o700)
	}
	return nil
}

func keyBasePath(sshDir, label string) string {
	return filepath.Join(sshDir, "id_ed25519_"+label)
}

func generateKeyPair(sshDir, label string) (string, error) {
	keyPath := keyBasePath(sshDir, label)
	if _, err := os.Stat(keyPath); err == nil {
		return "", fmt.Errorf("key already exists: %s", keyPath)
	}

	cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-C", label+"@github", "-f", keyPath, "-N", "")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("ssh-keygen failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}

	if runtime.GOOS != "windows" {
		_ = os.Chmod(keyPath, 0o600)
		_ = os.Chmod(keyPath+".pub", 0o644)
	}

	return keyPath, nil
}

func ensureGitHubKnownHost(sshDir string) error {
	knownHostsPath := filepath.Join(sshDir, "known_hosts")
	if contains, err := fileContainsHost(knownHostsPath, "github.com"); err == nil && contains {
		return nil
	}

	cmd := exec.Command("ssh-keyscan", "github.com")
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("ssh-keyscan failed: %w", err)
	}

	f, err := os.OpenFile(knownHostsPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.Write(out); err != nil {
		return err
	}
	return nil
}

func fileContainsHost(path, host string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if strings.HasPrefix(line, host+" ") || strings.HasPrefix(line, host+",") {
			return true, nil
		}
	}
	return false, s.Err()
}

func ensureSSHConfigEntry(configFile, hostAlias, keyPath string) error {
	if err := ensureConfigFile(configFile); err != nil {
		return err
	}

	data, err := os.ReadFile(configFile)
	if err != nil {
		return err
	}
	if hasHostAlias(data, hostAlias) {
		return nil
	}

	identityPath := filepath.ToSlash(keyPath)
	entry := fmt.Sprintf("\nHost %s\n  HostName github.com\n  User git\n  IdentityFile %q\n  AddKeysToAgent yes\n  IdentitiesOnly yes\n", hostAlias, identityPath)

	f, err := os.OpenFile(configFile, os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(entry)
	return err
}

func ensureConfigFile(configFile string) error {
	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		f, createErr := os.OpenFile(configFile, os.O_CREATE|os.O_WRONLY, 0o600)
		if createErr != nil {
			return createErr
		}
		f.Close()
	}
	if runtime.GOOS != "windows" {
		_ = os.Chmod(configFile, 0o600)
	}
	return nil
}

func hasHostAlias(config []byte, hostAlias string) bool {
	s := bufio.NewScanner(bytes.NewReader(config))
	needle := strings.ToLower(hostAlias)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) >= 2 && strings.EqualFold(parts[0], "host") {
			for _, alias := range parts[1:] {
				if strings.ToLower(alias) == needle {
					return true
				}
			}
		}
	}
	return false
}

func readPublicKey(sshDir, label string) (string, error) {
	path := keyBasePath(sshDir, label) + ".pub"
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("cannot read public key: %w", err)
	}
	return strings.TrimSpace(string(data)), nil
}

func testSSHConnection(hostAlias string) (string, error) {
	cmd := exec.Command("ssh", "-T", "git@"+hostAlias)
	var out, stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	_ = cmd.Run()
	combined := strings.TrimSpace(stderr.String() + "\n" + out.String())
	if strings.Contains(strings.ToLower(combined), "successfully authenticated") {
		return combined, nil
	}
	if combined == "" {
		combined = "SSH returned no output"
	}
	return combined, fmt.Errorf("SSH test failed")
}
