// Package logging provides an in-memory activity logger with color-coded,
// timestamped output designed for Fyne applications.
package logging

import (
	"fmt"
	"image/color"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/theme"
)

// Logger records operational events with severity levels, timestamps, and color coding.
type Logger struct {
	container *fyne.Container
	window    fyne.Window
}

// NewLogger creates a Logger that appends entries to the given container and refreshes the window.
func NewLogger(c *fyne.Container, w fyne.Window) *Logger {
	return &Logger{container: c, window: w}
}

// Info logs an informational message.
func (l *Logger) Info(msg string) { l.log("INFO", msg, theme.Color(theme.ColorNamePrimary), "i") }

// Success logs a success message.
func (l *Logger) Success(msg string) { l.log("SUCCESS", msg, theme.SuccessColor(), "+") }

// Warn logs a warning message.
func (l *Logger) Warn(msg string) { l.log("WARN", msg, theme.Color(theme.ColorNameWarning), "!") }

// Err logs an error message.
func (l *Logger) Err(msg string) { l.log("ERROR", msg, theme.Color(theme.ColorNameError), "x") }

func (l *Logger) log(level, message string, color color.Color, marker string) {
	timestamp := time.Now().Format("15:04:05")
	text := canvas.NewText(fmt.Sprintf("[%s] %s %s: %s", timestamp, marker, level, message), color)
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	text.TextSize = 11

	fyne.Do(func() {
		l.container.Add(text)
		l.container.Refresh()
		if l.window != nil {
			l.window.Canvas().Refresh(l.container)
		}
	})
}
