// Package theme provides utilities for switching between system, light, and dark themes
// in Fyne applications.
package theme

import (
	"image/color"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/theme"
)

type forcedVariantTheme struct {
	fyne.Theme
	variant fyne.ThemeVariant
}

func (f *forcedVariantTheme) Color(name fyne.ThemeColorName, _ fyne.ThemeVariant) color.Color {
	return f.Theme.Color(name, f.variant)
}

// ApplyThemeChoice sets the application theme to System, Light, or Dark.
func ApplyThemeChoice(a fyne.App, choice string) {
	normalized := strings.ToLower(strings.TrimSpace(choice))
	switch normalized {
	case "light":
		a.Settings().SetTheme(&forcedVariantTheme{Theme: theme.DefaultTheme(), variant: theme.VariantLight})
	case "dark":
		a.Settings().SetTheme(&forcedVariantTheme{Theme: theme.DefaultTheme(), variant: theme.VariantDark})
	default:
		a.Settings().SetTheme(theme.DefaultTheme())
	}
}
