// Package format provides formatting functions for cost, duration, and SI units.
package format

import (
	"fmt"

	"github.com/dustin/go-humanize"
)

// Cost formats a USD amount as "$X.XX".
func Cost(usd float64) string {
	return fmt.Sprintf("$%.2f", usd)
}

// Duration formats milliseconds as "Xm Ys".
func Duration(ms int) string {
	mins := ms / 60000
	secs := (ms % 60000) / 1000
	return fmt.Sprintf("%dm %ds", mins, secs)
}

// SI formats a number with SI suffixes (e.g. 1500 -> "1.5K", 1000000 -> "1M").
func SI(n int) string {
	val, prefix := humanize.ComputeSI(float64(n))
	return humanize.FtoaWithDigits(val, 0) + prefix
}
