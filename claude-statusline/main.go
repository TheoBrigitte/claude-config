// Format and display a status line for the latest Claude API call,
// showing model, context usage, cost, duration, and API status.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"claude-statusline/pkg/config"
	"claude-statusline/pkg/format"
	"claude-statusline/pkg/layout"
	"claude-statusline/pkg/model"
	"claude-statusline/pkg/status"
	"claude-statusline/pkg/style"
	"claude-statusline/pkg/terminal"
)

func main() {
	var configPath string
	args := os.Args[1:]
	for i, a := range args {
		if a == "--config" && i+1 < len(args) {
			configPath = args[i+1]
		}
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error loading config: %v\n", err)
		os.Exit(1)
	}

	var in model.Input
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil {
		fmt.Fprintf(os.Stderr, "error parsing JSON: %v\n", err)
		os.Exit(1)
	}

	termWidth := terminal.Width() - cfg.Padding
	modules := renderModules(cfg, in, termWidth)

	for _, lineTemplate := range cfg.Lines {
		segments := strings.Split(lineTemplate, cfg.Separator)
		var parts []*layout.Part
		for _, seg := range segments {
			rendered := renderSegment(strings.TrimSpace(seg), modules)
			if rendered == "" {
				continue
			}
			parts = append(parts, &layout.Part{
				Text: rendered,
				Len:  displayLen(rendered, modules, strings.TrimSpace(seg)),
			})
		}
		for _, line := range layout.Lines(termWidth, parts) {
			fmt.Println(line)
		}
	}
}

// moduleResult holds both the rendered (styled) and raw (unstyled) text for a module.
type moduleResult struct {
	rendered string
	rawLen   int
}

// renderModules renders every module into a map keyed by $token name.
func renderModules(cfg config.Config, in model.Input, termWidth int) map[string]moduleResult {
	currentUsage := model.ParseCurrentUsage(in.ContextWindow.CurrentUsage)
	contextPct := 0
	if in.ContextWindow.UsedPercentage != nil {
		contextPct = int(*in.ContextWindow.UsedPercentage)
	}

	m := make(map[string]moduleResult)

	// Model
	if !cfg.Model.Disabled && (cfg.Model.MinWidth == 0 || termWidth >= cfg.Model.MinWidth) {
		if in.Model.DisplayName != "" {
			raw := applyFormat(cfg.Model.Format, in.Model.DisplayName, cfg.Model.Symbol)
			s := style.Parse(cfg.Model.Style)
			m["$model"] = moduleResult{s.Sprint(raw), len(raw)}
		}
	}

	// Context bar
	if !cfg.ContextBar.Disabled {
		barWidth := cfg.ContextBar.Width
		if barWidth == 0 {
			barWidth = max(termWidth/3, 40)
			if barWidth < 10 {
				barWidth = 0
			}
		}
		if barWidth > 0 {
			filled := contextPct * barWidth / 100
			empty := barWidth - filled
			fc, ec := cfg.ContextBar.FillChar, cfg.ContextBar.EmptyChar
			if fc == "" {
				fc = "#"
			}
			if ec == "" {
				ec = "-"
			}
			raw := cfg.ContextBar.Symbol + strings.Repeat(fc, filled) + strings.Repeat(ec, empty)
			s := resolveThresholdStyle(cfg.ContextBar.ThresholdConfig, float64(contextPct))
			m["$context_bar"] = moduleResult{s.Sprint(raw), len(raw)}
		}
	}

	// Context tokens
	if !cfg.ContextTokens.Disabled {
		value := fmt.Sprintf("%s/%s tokens", format.SI(currentUsage), format.SI(in.ContextWindow.ContextWindowSize))
		raw := applyFormat(cfg.ContextTokens.Format, value, cfg.ContextTokens.Symbol)
		s := style.Parse(cfg.ContextTokens.Style)
		m["$context_tokens"] = moduleResult{s.Sprint(raw), len(raw)}
	}

	// Context percentage
	if !cfg.ContextPct.Disabled {
		value := fmt.Sprintf("%d", contextPct)
		raw := applyFormat(cfg.ContextPct.Format, value, cfg.ContextPct.Symbol)
		s := style.Parse(cfg.ContextPct.Style)
		m["$context_pct"] = moduleResult{s.Sprint(raw), len(raw)}
	}

	// Cost
	if !cfg.Cost.Disabled {
		value := format.Cost(in.Cost.TotalCostUSD)
		raw := applyFormat(cfg.Cost.Format, value, cfg.Cost.Symbol)
		s := resolveThresholdStyle(cfg.Cost, in.Cost.TotalCostUSD)
		m["$cost"] = moduleResult{s.Sprint(raw), len(raw)}
	}

	// Duration
	if !cfg.Duration.Disabled {
		value := format.Duration(in.Cost.TotalDurationMS)
		raw := applyFormat(cfg.Duration.Format, value, cfg.Duration.Symbol)
		s := style.Parse(cfg.Duration.Style)
		m["$duration"] = moduleResult{s.Sprint(raw), len(raw)}
	}

	// Status
	if !cfg.Status.Disabled {
		value := status.Get()
		raw := applyFormat(cfg.Status.Format, value, cfg.Status.Symbol)
		s := style.Parse(cfg.Status.Style)
		m["$status"] = moduleResult{s.Sprint(raw), len(raw)}
	}

	return m
}

// applyFormat applies a format string. Supports {value} and {symbol} placeholders.
// If format is empty, returns symbol + value.
func applyFormat(format, value, symbol string) string {
	if format == "" {
		return symbol + value
	}
	r := strings.NewReplacer("{value}", value, "{symbol}", symbol)
	return r.Replace(format)
}

// resolveThresholdStyle picks the appropriate style based on threshold config.
func resolveThresholdStyle(cfg config.ThresholdConfig, value float64) *style.Style {
	if cfg.CriticalThreshold > 0 && value >= cfg.CriticalThreshold {
		if s := style.Parse(cfg.CriticalStyle); s != nil {
			return s
		}
	}
	if cfg.WarnThreshold > 0 && value >= cfg.WarnThreshold {
		if s := style.Parse(cfg.WarnStyle); s != nil {
			return s
		}
	}
	return style.Parse(cfg.Style)
}

// renderSegment replaces all $module tokens in a segment template with their
// rendered values. Returns empty string if all tokens resolved to empty.
func renderSegment(seg string, modules map[string]moduleResult) string {
	result := seg
	hasContent := false
	for token, mod := range modules {
		if strings.Contains(result, token) {
			if mod.rendered != "" {
				hasContent = true
			}
			result = strings.ReplaceAll(result, token, mod.rendered)
		}
	}
	if !hasContent {
		return ""
	}
	return strings.TrimSpace(result)
}

// displayLen calculates the logical display width of a rendered segment
// by summing the raw lengths of the modules it contains plus literal text.
func displayLen(_ string, modules map[string]moduleResult, seg string) int {
	total := 0
	remaining := seg
	for remaining != "" {
		earliest := -1
		var earliestToken string
		for token := range modules {
			if idx := strings.Index(remaining, token); idx >= 0 && (earliest < 0 || idx < earliest) {
				earliest = idx
				earliestToken = token
			}
		}
		if earliest < 0 {
			total += len(remaining)
			break
		}
		total += earliest // literal text before token
		total += modules[earliestToken].rawLen
		remaining = remaining[earliest+len(earliestToken):]
	}
	return total
}
