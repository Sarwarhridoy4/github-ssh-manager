package main

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	labelPattern = regexp.MustCompile(`^[a-zA-Z0-9._-]{1,64}$`)
	hostPattern  = regexp.MustCompile(`^[a-zA-Z0-9._-]{1,128}$`)
)

func validateLabel(label string) error {
	if !labelPattern.MatchString(label) {
		return fmt.Errorf("label must be 1-64 chars and only include letters, numbers, '.', '-', '_' ")
	}
	return nil
}

func validateHostAlias(alias string) error {
	if !hostPattern.MatchString(alias) {
		return fmt.Errorf("host alias must be 1-128 chars and only include letters, numbers, '.', '-', '_' ")
	}
	if strings.EqualFold(alias, "github.com") {
		return fmt.Errorf("host alias must not be github.com")
	}
	return nil
}

func requireToken(token string) error {
	if strings.TrimSpace(token) == "" {
		return fmt.Errorf("GitHub token is required")
	}
	return nil
}
