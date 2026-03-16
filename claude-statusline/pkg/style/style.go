// Package style parses Starship-compatible style strings into ANSI escape sequences.
//
// Supported syntax:
//
//	"bold"                        – modifier only
//	"red"                         – named foreground color
//	"bold green"                  – modifier + named color
//	"fg:#c792ea"                  – 24-bit hex foreground
//	"bold fg:#ff5370 bg:#1a1a2e"  – modifier + hex fg + hex bg
//	"bright_red"                  – bright/hi-intensity named color
package style

import (
	"fmt"
	"strconv"
	"strings"
)

// Style holds parsed ANSI SGR codes ready to wrap text.
type Style struct {
	codes []string
}

var namedFg = map[string]int{
	"black": 30, "red": 31, "green": 32, "yellow": 33,
	"blue": 34, "purple": 35, "magenta": 35, "cyan": 36, "white": 37,
	"bright_black": 90, "bright_red": 91, "bright_green": 92, "bright_yellow": 93,
	"bright_blue": 94, "bright_purple": 95, "bright_magenta": 95, "bright_cyan": 96, "bright_white": 97,
}

var namedBg = map[string]int{
	"black": 40, "red": 41, "green": 42, "yellow": 43,
	"blue": 44, "purple": 45, "magenta": 45, "cyan": 46, "white": 47,
	"bright_black": 100, "bright_red": 101, "bright_green": 102, "bright_yellow": 103,
	"bright_blue": 104, "bright_purple": 105, "bright_magenta": 105, "bright_cyan": 106, "bright_white": 107,
}

// Parse parses a style string into a Style. Returns nil for empty strings.
func Parse(s string) *Style {
	if s == "" {
		return nil
	}
	st := &Style{}
	for p := range strings.FieldsSeq(s) {
		switch p {
		case "bold":
			st.codes = append(st.codes, "1")
		case "dimmed", "dim":
			st.codes = append(st.codes, "2")
		case "italic":
			st.codes = append(st.codes, "3")
		case "underline":
			st.codes = append(st.codes, "4")
		default:
			if val, ok := strings.CutPrefix(p, "fg:"); ok {
				if r, g, b, ok := parseHex(val); ok {
					st.codes = append(st.codes, fmt.Sprintf("38;2;%d;%d;%d", r, g, b))
				}
			} else if val, ok := strings.CutPrefix(p, "bg:"); ok {
				if r, g, b, ok := parseHex(val); ok {
					st.codes = append(st.codes, fmt.Sprintf("48;2;%d;%d;%d", r, g, b))
				} else if code, ok := namedBg[val]; ok {
					st.codes = append(st.codes, strconv.Itoa(code))
				}
			} else if strings.HasPrefix(p, "#") {
				if r, g, b, ok := parseHex(p); ok {
					st.codes = append(st.codes, fmt.Sprintf("38;2;%d;%d;%d", r, g, b))
				}
			} else if code, ok := namedFg[p]; ok {
				st.codes = append(st.codes, strconv.Itoa(code))
			}
		}
	}
	if len(st.codes) == 0 {
		return nil
	}
	return st
}

// Sprint wraps text in ANSI escape codes. Nil-safe: returns text unchanged.
func (s *Style) Sprint(text string) string {
	if s == nil || len(s.codes) == 0 {
		return text
	}
	return fmt.Sprintf("\033[%sm%s\033[0m", strings.Join(s.codes, ";"), text)
}

// parseHex parses #RGB or #RRGGBB hex color strings.
func parseHex(s string) (r, g, b byte, ok bool) {
	s = strings.TrimPrefix(s, "#")
	if len(s) == 3 {
		s = string([]byte{s[0], s[0], s[1], s[1], s[2], s[2]})
	}
	if len(s) != 6 {
		return 0, 0, 0, false
	}
	n, err := strconv.ParseUint(s, 16, 24)
	if err != nil {
		return 0, 0, 0, false
	}
	return byte(n >> 16), byte(n >> 8), byte(n), true
}
