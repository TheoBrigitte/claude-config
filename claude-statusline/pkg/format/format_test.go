package format

import (
	"fmt"
	"testing"

	"github.com/fatih/color"
)

func TestSI(t *testing.T) {
	tests := []struct {
		n    int
		want string
	}{
		{0, "0"},
		{999, "999"},
		{1000, "1k"},
		{1500, "1k"},
		{20000, "20k"},
		{200000, "200k"},
		{1000000, "1M"},
	}
	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := SI(tt.n); got != tt.want {
				t.Errorf("SI(%d) = %q, want %q", tt.n, got, tt.want)
			}
		})
	}
}

func TestBarColor(t *testing.T) {
	tests := []struct {
		pct       int
		wantColor color.Attribute
	}{
		{0, color.FgGreen},
		{39, color.FgGreen},
		{40, color.FgYellow},
		{89, color.FgYellow},
		{90, color.FgRed},
		{100, color.FgRed},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("pct=%d", tt.pct), func(t *testing.T) {
			got := BarColor(tt.pct)
			want := color.New(tt.wantColor)
			if got.Sprint("x") != want.Sprint("x") {
				t.Errorf("BarColor(%d) produced unexpected color", tt.pct)
			}
		})
	}
}

func TestDuration(t *testing.T) {
	tests := []struct {
		ms   int
		want string
	}{
		{0, "⏱️ 0m 0s"},
		{5000, "⏱️ 0m 5s"},
		{60000, "⏱️ 1m 0s"},
		{90000, "⏱️ 1m 30s"},
		{245000, "⏱️ 4m 5s"},
		{3_600_000, "⏱️ 60m 0s"},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("%dms", tt.ms), func(t *testing.T) {
			if got := Duration(tt.ms); got != tt.want {
				t.Errorf("Duration(%d) = %q, want %q", tt.ms, got, tt.want)
			}
		})
	}
}

func TestCost(t *testing.T) {
	tests := []struct {
		cost float64
		want string
	}{
		{0, "$0.00"},
		{0.001, "$0.00"},
		{0.005, "$0.01"},
		{0.08734, "$0.09"},
		{1.5, "$1.50"},
		{12.345, "$12.35"},
	}
	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			if got := Cost(tt.cost); got != tt.want {
				t.Errorf("Cost(%f) = %q, want %q", tt.cost, got, tt.want)
			}
		})
	}
}
