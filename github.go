package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type githubKeyRequest struct {
	Title string `json:"title"`
	Key   string `json:"key"`
}

type githubKeyResponse struct {
	ID      int64  `json:"id"`
	Title   string `json:"title"`
	Message string `json:"message"`
}

func uploadKeyToGitHub(token, title, publicKey string) (*githubKeyResponse, error) {
	payload := githubKeyRequest{Title: title, Key: publicKey}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, "https://api.github.com/user/keys", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "github-ssh-manager")
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var decoded githubKeyResponse
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return nil, err
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if decoded.Message == "" {
			decoded.Message = fmt.Sprintf("GitHub API returned status %d", resp.StatusCode)
		}
		return &decoded, fmt.Errorf("%s", decoded.Message)
	}
	return &decoded, nil
}
