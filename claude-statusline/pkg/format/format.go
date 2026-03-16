// Package format provides formatting functions for cost, duration, and SI units.
package format

import (
	"fmt"

	"github.com/dustin/go-humanize"
	"github.com/fatih/color"
)

// Cost formats a USD amount as "$X.XX".
func Cost(usd float64) string {
	return fmt.Sprintf("$%.2f", usd)
}

// Duration formats milliseconds as "⏱️ Xm Ys".
func Duration(ms int) string {
	mins := ms / 60000
	secs := (ms % 60000) / 1000
	return fmt.Sprintf("⏱️ %dm %ds", mins, secs)
}

// SI formats a number with SI suffixes (e.g. 1500 -> "1.5K", 1000000 -> "1M").
func SI(n int) string {
	val, prefix := humanize.ComputeSI(float64(n))
	return humanize.FtoaWithDigits(val, 0) + prefix
}

// BarColor returns the bar color based on context usage percentage.
// > 90% = red, to notify about hitting limits soon.
// > 40% = yellow, to indicate that context has reached a significant portion,
// reminding about the "dumb zone" (see https://www.youtube.com/watch?v=rmvDxxNubIg).
func BarColor(pct int) *color.Color {
	if pct >= 90 {
		return color.New(color.FgRed)
	}
	if pct >= 40 {
		return color.New(color.FgYellow)
	}
	return color.New(color.FgGreen)
}
