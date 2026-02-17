package main

import (
	"fmt"
	"image/color"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/theme"
)

type logger struct {
	container *fyne.Container
	window    fyne.Window
}

func newLogger(c *fyne.Container, w fyne.Window) *logger {
	return &logger{container: c, window: w}
}

func (l *logger) info(msg string)    { l.log("INFO", msg, theme.Color(theme.ColorNamePrimary), "i") }
func (l *logger) success(msg string) { l.log("SUCCESS", msg, theme.SuccessColor(), "+") }
func (l *logger) warn(msg string)    { l.log("WARN", msg, theme.Color(theme.ColorNameWarning), "!") }
func (l *logger) err(msg string)     { l.log("ERROR", msg, theme.Color(theme.ColorNameError), "x") }

func (l *logger) log(level, message string, color color.Color, marker string) {
	timestamp := time.Now().Format("15:04:05")
	text := canvas.NewText(fmt.Sprintf("[%s] %s %s: %s", timestamp, marker, level, message), color)
	text.TextStyle.Monospace = true
	text.Alignment = fyne.TextAlignLeading
	text.TextSize = 11

	l.container.Add(text)
	l.container.Refresh()
	if l.window != nil {
		l.window.Canvas().Refresh(l.container)
	}
}
