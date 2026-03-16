// Format and display a status line for the latest Claude API call,
// showing model, context usage, cost, duration, and API status.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"claude-statusline/pkg/format"
	"claude-statusline/pkg/layout"
	"claude-statusline/pkg/model"
	"claude-statusline/pkg/status"
	"claude-statusline/pkg/terminal"

	"github.com/fatih/color"
)

const padding = 5

func init() {
	color.NoColor = false
}

// main reads a Claude Code status JSON payload from stdin and renders
// a terminal status line with model name, context usage bar, cost,
// session duration, and API health. Parts are laid out to fit the
// current terminal width, wrapping to multiple lines when needed.
func main() {
	var in model.Input
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil {
		fmt.Fprintf(os.Stderr, "error parsing JSON: %v\n", err)
		os.Exit(1)
	}

	currentUsage := model.ParseCurrentUsage(in.ContextWindow.CurrentUsage)
	contextPct := 0
	if in.ContextWindow.UsedPercentage != nil {
		contextPct = int(*in.ContextWindow.UsedPercentage)
	}

	// Reserve padding and compute how wide the context bar can be.
	// Clamp to at least 40 chars, or disable it entirely if too narrow.
	termWidth := terminal.Width() - padding
	contextBarSize := max(termWidth/3, 40)
	if contextBarSize < 10 {
		contextBarSize = 0
	}

	barColor := format.BarColor(contextPct)

	parts := []*layout.Part{}

	// Only show model name on wide enough terminals
	if termWidth >= 80 {
		parts = append(parts, layout.NewPart(fmt.Sprintf("[%s]", in.Model.DisplayName), color.New(color.FgCyan)))
	}

	// Build the context usage part: progressively add the token count
	// and visual bar only if they fit within the available width.
	filled := contextPct * contextBarSize / 100
	empty := contextBarSize - filled
	contextBar := layout.NewPart(strings.Repeat("#", filled)+strings.Repeat("-", empty), barColor)
	contextTokens := layout.NewPart(fmt.Sprintf("(%s/%s tokens)", format.SI(currentUsage), format.SI(in.ContextWindow.ContextWindowSize)), nil)
	contextText := layout.NewPart(fmt.Sprintf("%d%%", contextPct), nil)
	if contextText.Length()+1+contextTokens.Length() < termWidth {
		contextText.AppendPart(contextTokens, " ")
	}
	if contextBarSize > 0 && contextText.Length()+1+contextBar.Length() < termWidth {
		contextText.PrependPart(contextBar, " ")
	}
	parts = append(parts, contextText)

	parts = append(parts, layout.NewPart(format.Cost(in.Cost.TotalCostUSD), color.New(color.FgYellow)))
	parts = append(parts, layout.NewPart(format.Duration(in.Cost.TotalDurationMS), nil))
	parts = append(parts, layout.NewPart(status.Get(), nil))

	for _, line := range layout.Lines(termWidth, parts) {
		fmt.Println(line)
	}
}
