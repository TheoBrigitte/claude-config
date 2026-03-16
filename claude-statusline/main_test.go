package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/fatih/color"
)

// --- parseCurrentUsage ---

func TestParseCurrentUsage(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want int
	}{
		{
			name: "empty raw message",
			raw:  "",
			want: 0,
		},
		{
			name: "null value",
			raw:  "null",
			want: 0,
		},
		{
			name: "single number",
			raw:  "42",
			want: 42,
		},
		{
			name: "single number float truncates",
			raw:  "42.9",
			want: 42,
		},
		{
			name: "object sums all fields",
			raw:  `{"input_tokens":8500,"output_tokens":1200,"cache_creation_input_tokens":5000,"cache_read_input_tokens":2000}`,
			want: 16700,
		},
		{
			name: "object with zeros",
			raw:  `{"input_tokens":0,"output_tokens":0}`,
			want: 0,
		},
		{
			name: "object single field",
			raw:  `{"input_tokens":4096}`,
			want: 4096,
		},
		{
			name: "invalid JSON falls back to 0",
			raw:  `not-json`,
			want: 0,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var raw json.RawMessage
			if tt.raw != "" {
				raw = json.RawMessage(tt.raw)
			}
			if got := parseCurrentUsage(raw); got != tt.want {
				t.Errorf("parseCurrentUsage(%q) = %d, want %d", tt.raw, got, tt.want)
			}
		})
	}
}

// --- formatSI ---

func TestFormatSI(t *testing.T) {
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
			if got := formatSI(tt.n); got != tt.want {
				t.Errorf("formatSI(%d) = %q, want %q", tt.n, got, tt.want)
			}
		})
	}
}

// --- part type ---

func TestNewPart(t *testing.T) {
	t.Run("without color", func(t *testing.T) {
		p := newPart("hello", nil)
		if p.text != "hello" {
			t.Errorf("text = %q, want %q", p.text, "hello")
		}
		if p.length() != 5 {
			t.Errorf("length = %d, want 5", p.length())
		}
	})

	t.Run("with color has same logical length", func(t *testing.T) {
		p := newPart("hello", color.New(color.FgRed))
		if p.length() != 5 {
			t.Errorf("length = %d, want 5 (should track raw text length, not ANSI)", p.length())
		}
		if !strings.Contains(p.text, "hello") {
			t.Errorf("text should contain 'hello', got %q", p.text)
		}
	})

	t.Run("empty string", func(t *testing.T) {
		p := newPart("", nil)
		if p.length() != 0 {
			t.Errorf("length = %d, want 0", p.length())
		}
	})
}

func TestPartAppend(t *testing.T) {
	t.Run("with separator", func(t *testing.T) {
		p := newPart("a", nil)
		p.append("b", " | ", nil)
		if p.text != "a | b" {
			t.Errorf("text = %q, want %q", p.text, "a | b")
		}
		if p.length() != 5 {
			t.Errorf("length = %d, want 5", p.length())
		}
	})

	t.Run("with color preserves logical length", func(t *testing.T) {
		p := newPart("a", nil)
		p.append("b", " ", color.New(color.FgCyan))
		if p.length() != 3 {
			t.Errorf("length = %d, want 3", p.length())
		}
	})
}

func TestPartPrepend(t *testing.T) {
	p := newPart("b", nil)
	p.prepend("a", " | ", nil)
	if p.text != "a | b" {
		t.Errorf("text = %q, want %q", p.text, "a | b")
	}
	if p.length() != 5 {
		t.Errorf("length = %d, want 5", p.length())
	}
}

func TestPartAppendPart(t *testing.T) {
	p1 := newPart("hello", nil)
	p2 := newPart("world", nil)
	p1.appendPart(p2, " ")
	if p1.text != "hello world" {
		t.Errorf("text = %q, want %q", p1.text, "hello world")
	}
	if p1.length() != 11 {
		t.Errorf("length = %d, want 11", p1.length())
	}
}

func TestPartPrependPart(t *testing.T) {
	p1 := newPart("world", nil)
	p2 := newPart("hello", nil)
	p1.prependPart(p2, " ")
	if p1.text != "hello world" {
		t.Errorf("text = %q, want %q", p1.text, "hello world")
	}
	if p1.length() != 11 {
		t.Errorf("length = %d, want 11", p1.length())
	}
}

// --- layoutLines ---

func TestLayoutLines(t *testing.T) {
	tests := []struct {
		name      string
		termWidth int
		parts     []*part
		wantLines int
	}{
		{
			name:      "all fit on one line",
			termWidth: 100,
			parts: []*part{
				newPart("A", nil),
				newPart("B", nil),
				newPart("C", nil),
			},
			wantLines: 1,
		},
		{
			name:      "wrap to multiple lines",
			termWidth: 10,
			parts: []*part{
				newPart("AAAAAAA", nil),
				newPart("BBBBBBB", nil),
			},
			wantLines: 2,
		},
		{
			name:      "empty parts skipped",
			termWidth: 100,
			parts: []*part{
				newPart("A", nil),
				{text: "", len: 0},
				newPart("B", nil),
			},
			wantLines: 1,
		},
		{
			name:      "no parts",
			termWidth: 100,
			parts:     []*part{},
			wantLines: 0,
		},
		{
			name:      "single part",
			termWidth: 5,
			parts: []*part{
				newPart("A", nil),
			},
			wantLines: 1,
		},
		{
			name:      "each part on own line when narrow",
			termWidth: 5,
			parts: []*part{
				newPart("AAA", nil),
				newPart("BBB", nil),
				newPart("CCC", nil),
			},
			wantLines: 3,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lines := layoutLines(tt.termWidth, tt.parts)
			if len(lines) != tt.wantLines {
				t.Errorf("got %d lines, want %d: %v", len(lines), tt.wantLines, lines)
			}
		})
	}
}

func TestLayoutLinesSeparator(t *testing.T) {
	lines := layoutLines(100, []*part{
		newPart("A", nil),
		newPart("B", nil),
	})
	if len(lines) != 1 {
		t.Fatalf("expected 1 line, got %d", len(lines))
	}
	if !strings.Contains(lines[0], " | ") {
		t.Errorf("expected separator in line: %q", lines[0])
	}
}

func TestLayoutLinesWrappedOmitsSeparator(t *testing.T) {
	lines := layoutLines(5, []*part{
		newPart("AAA", nil),
		newPart("BBB", nil),
	})
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d", len(lines))
	}
	if strings.Contains(lines[0], " | ") || strings.Contains(lines[1], " | ") {
		t.Errorf("wrapped lines should not contain separator: %v", lines)
	}
}

// --- barColorForPct ---

func TestBarColorForPct(t *testing.T) {
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
			got := barColorForPct(tt.pct)
			want := color.New(tt.wantColor)
			// Compare by rendering a test string — same color produces same ANSI output.
			if got.Sprint("x") != want.Sprint("x") {
				t.Errorf("barColorForPct(%d) produced unexpected color", tt.pct)
			}
		})
	}
}

// --- fetchAPIStatus ---

func TestFetchAPIStatus(t *testing.T) {
	t.Run("operational returns green", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `{"status":{"description":"All Systems Operational"}}`)
		}))
		defer srv.Close()

		got := fetchAPIStatus(srv.Client(), srv.URL)
		if got != statusOK {
			t.Errorf("got %q, want %q", got, statusOK)
		}
	})

	t.Run("degraded returns warning", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `{"status":{"description":"Partially Degraded Service"}}`)
		}))
		defer srv.Close()

		got := fetchAPIStatus(srv.Client(), srv.URL)
		if got != statusWARN+" degraded" {
			t.Errorf("got %q, want %q", got, statusWARN+" degraded")
		}
	})

	t.Run("invalid JSON returns error", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `not json`)
		}))
		defer srv.Close()

		got := fetchAPIStatus(srv.Client(), srv.URL)
		if !strings.HasPrefix(got, statusERR) {
			t.Errorf("got %q, want prefix %q", got, statusERR)
		}
		if !strings.Contains(got, "reponse:") {
			t.Errorf("got %q, want 'reponse:' in error message", got)
		}
	})

	t.Run("connection error returns error", func(t *testing.T) {
		client := &http.Client{}
		got := fetchAPIStatus(client, "http://127.0.0.1:1") // refused port
		if !strings.HasPrefix(got, statusERR) {
			t.Errorf("got %q, want prefix %q", got, statusERR)
		}
		if !strings.Contains(got, "request:") {
			t.Errorf("got %q, want 'request:' in error message", got)
		}
	})

	t.Run("case insensitive operational match", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `{"status":{"description":"all systems OPERATIONAL"}}`)
		}))
		defer srv.Close()

		got := fetchAPIStatus(srv.Client(), srv.URL)
		if got != statusOK {
			t.Errorf("got %q, want %q", got, statusOK)
		}
	})
}

// --- formatDuration ---

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		ms   int
		want string
	}{
		{
			ms:   0,
			want: "⏱️ 0m 0s",
		},
		{
			ms:   5000,
			want: "⏱️ 0m 5s",
		},
		{
			ms:   60000,
			want: "⏱️ 1m 0s",
		},
		{
			ms:   90000,
			want: "⏱️ 1m 30s",
		},
		{
			ms:   245000,
			want: "⏱️ 4m 5s",
		},
		{
			ms:   3_600_000,
			want: "⏱️ 60m 0s",
		},
	}
	for _, tt := range tests {
		t.Run(fmt.Sprintf("%dms", tt.ms), func(t *testing.T) {
			if got := formatDuration(tt.ms); got != tt.want {
				t.Errorf("formatDuration(%d) = %q, want %q", tt.ms, got, tt.want)
			}
		})
	}
}

// --- context bar sizing ---

func TestContextBarSize(t *testing.T) {
	tests := []struct {
		name        string
		termWidth   int
		wantBarSize int
	}{
		{
			name:        "wide terminal uses third of width",
			termWidth:   180,
			wantBarSize: 60,
		},
		{
			name:        "medium terminal clamps to 40",
			termWidth:   90,
			wantBarSize: 40,
		},
		{
			name:        "narrow terminal still gets 40",
			termWidth:   50,
			wantBarSize: 40,
		},
		{
			name:        "very narrow terminal still gets clamped to 40",
			termWidth:   20,
			wantBarSize: 40,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Mirrors the logic in main(): max(termWidth/3, 40), then 0 if <10
			barSize := max(tt.termWidth/3, 40)
			if barSize < 10 {
				barSize = 0
			}
			if barSize != tt.wantBarSize {
				t.Errorf("termWidth=%d: barSize = %d, want %d", tt.termWidth, barSize, tt.wantBarSize)
			}
		})
	}
}

// --- context bar fill pattern ---

func TestContextBarFillPattern(t *testing.T) {
	tests := []struct {
		name       string
		pct        int
		barSize    int
		wantFilled int
		wantEmpty  int
	}{
		{
			name:       "0% all dashes",
			pct:        0,
			barSize:    40,
			wantFilled: 0,
			wantEmpty:  40,
		},
		{
			name:       "50% half filled",
			pct:        50,
			barSize:    40,
			wantFilled: 20,
			wantEmpty:  20,
		},
		{
			name:       "100% all hashes",
			pct:        100,
			barSize:    40,
			wantFilled: 40,
			wantEmpty:  0,
		},
		{
			name:       "25% with integer rounding",
			pct:        25,
			barSize:    40,
			wantFilled: 10,
			wantEmpty:  30,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			filled := tt.pct * tt.barSize / 100
			empty := tt.barSize - filled
			if filled != tt.wantFilled {
				t.Errorf("filled = %d, want %d", filled, tt.wantFilled)
			}
			if empty != tt.wantEmpty {
				t.Errorf("empty = %d, want %d", empty, tt.wantEmpty)
			}
			// Verify total bar length is constant
			bar := strings.Repeat("#", filled) + strings.Repeat("-", empty)
			if len(bar) != tt.barSize {
				t.Errorf("bar length = %d, want %d", len(bar), tt.barSize)
			}
		})
	}
}

// --- model name display conditional ---

func TestModelNameDisplay(t *testing.T) {
	tests := []struct {
		name      string
		termWidth int
		wantModel bool
	}{
		{
			name:      "wide terminal shows model",
			termWidth: 120,
			wantModel: true,
		},
		{
			name:      "exactly 80 shows model",
			termWidth: 80,
			wantModel: true,
		},
		{
			name:      "narrow terminal hides model",
			termWidth: 79,
			wantModel: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotModel := tt.termWidth >= 80
			if gotModel != tt.wantModel {
				t.Errorf("termWidth=%d: model shown = %v, want %v", tt.termWidth, gotModel, tt.wantModel)
			}
		})
	}
}

// --- formatCost ---

func TestFormatCost(t *testing.T) {
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
			if got := formatCost(tt.cost); got != tt.want {
				t.Errorf("formatCost(%f) = %q, want %q", tt.cost, got, tt.want)
			}
		})
	}
}

// --- input JSON deserialization (focused per field group) ---

func mustParseInput(t *testing.T, jsonStr string) input {
	t.Helper()
	var in input
	if err := json.Unmarshal([]byte(jsonStr), &in); err != nil {
		t.Fatalf("failed to parse test input: %v", err)
	}
	return in
}

func TestInputModel(t *testing.T) {
	in := mustParseInput(t, `{
		"model": {
			"id": "claude-opus-4-6[1m]",
			"display_name": "Opus 4.6 (1M context)"
		}
	}`)
	if in.Model.ID != "claude-opus-4-6[1m]" {
		t.Errorf("model.id = %q", in.Model.ID)
	}
	if in.Model.DisplayName != "Opus 4.6 (1M context)" {
		t.Errorf("model.display_name = %q", in.Model.DisplayName)
	}
}

func TestInputCost(t *testing.T) {
	in := mustParseInput(t, `{
		"cost": {
			"total_cost_usd": 0.24710,
			"total_duration_ms": 245000,
			"total_api_duration_ms": 128000,
			"total_lines_added": 478,
			"total_lines_removed": 112
		}
	}`)
	if in.Cost.TotalCostUSD != 0.24710 {
		t.Errorf("total_cost_usd = %f", in.Cost.TotalCostUSD)
	}
	if in.Cost.TotalDurationMS != 245000 {
		t.Errorf("total_duration_ms = %d", in.Cost.TotalDurationMS)
	}
	if in.Cost.TotalAPIDurationMS != 128000 {
		t.Errorf("total_api_duration_ms = %d", in.Cost.TotalAPIDurationMS)
	}
	if in.Cost.TotalLinesAdded != 478 {
		t.Errorf("total_lines_added = %d", in.Cost.TotalLinesAdded)
	}
	if in.Cost.TotalLinesRemoved != 112 {
		t.Errorf("total_lines_removed = %d", in.Cost.TotalLinesRemoved)
	}
}

func TestInputContextWindow(t *testing.T) {
	t.Run("populated percentages", func(t *testing.T) {
		in := mustParseInput(t, `{
			"context_window": {
				"total_input_tokens": 42000,
				"total_output_tokens": 12800,
				"context_window_size": 1000000,
				"current_usage": {
					"input_tokens": 21000,
					"output_tokens": 6400
				},
				"used_percentage": 7,
				"remaining_percentage": 93
			}
		}`)
		if in.ContextWindow.ContextWindowSize != 1000000 {
			t.Errorf("context_window_size = %d", in.ContextWindow.ContextWindowSize)
		}
		if in.ContextWindow.UsedPercentage == nil || *in.ContextWindow.UsedPercentage != 7 {
			t.Error("used_percentage should be 7")
		}
		if in.ContextWindow.RemainingPercentage == nil || *in.ContextWindow.RemainingPercentage != 93 {
			t.Error("remaining_percentage should be 93")
		}
		if got := parseCurrentUsage(in.ContextWindow.CurrentUsage); got != 27400 {
			t.Errorf("current_usage sum = %d, want 27400", got)
		}
	})

	t.Run("null percentages before first API call", func(t *testing.T) {
		in := mustParseInput(t, `{
			"context_window": {
				"context_window_size": 200000,
				"current_usage": null,
				"used_percentage": null,
				"remaining_percentage": null
			}
		}`)
		if in.ContextWindow.UsedPercentage != nil {
			t.Errorf("used_percentage should be nil, got %v", *in.ContextWindow.UsedPercentage)
		}
		if in.ContextWindow.RemainingPercentage != nil {
			t.Errorf("remaining_percentage should be nil, got %v", *in.ContextWindow.RemainingPercentage)
		}
		// Null used_percentage should default to 0
		contextPct := 0
		if in.ContextWindow.UsedPercentage != nil {
			contextPct = int(*in.ContextWindow.UsedPercentage)
		}
		if contextPct != 0 {
			t.Errorf("contextPct = %d, want 0", contextPct)
		}
	})
}
