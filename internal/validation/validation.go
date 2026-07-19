// Package validation provides input validation for account labels,
// host aliases, and GitHub personal access tokens.
package validation

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	labelPattern = regexp.MustCompile(`^[a-zA-Z0-9._ -]{1,64}$`)
	hostPattern  = regexp.MustCompile(`^[a-zA-Z0-9._-]{1,128}$`)
)

// ValidateLabel ensures the account name is 1-64 characters and contains only
// letters, numbers, periods, hyphens, underscores, or spaces.
func ValidateLabel(label string) error {
	if !labelPattern.MatchString(label) {
		return fmt.Errorf("account name must be 1-64 chars and only include letters, numbers, '.', '-', '_', and spaces")
	}
	return nil
}

// ValidateHostAlias ensures the host alias is 1-128 characters, contains only
// letters, numbers, periods, hyphens, or underscores, and is not "github.com".
func ValidateHostAlias(alias string) error {
	if !hostPattern.MatchString(alias) {
		return fmt.Errorf("host alias must be 1-128 chars and only include letters, numbers, '.', '-', '_' ")
	}
	if strings.EqualFold(alias, "github.com") {
		return fmt.Errorf("host alias must not be github.com")
	}
	return nil
}

// RequireToken ensures the token string is not empty.
func RequireToken(token string) error {
	if strings.TrimSpace(token) == "" {
		return fmt.Errorf("GitHub token is required")
	}
	return nil
}
