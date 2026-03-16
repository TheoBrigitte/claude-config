// Format and display a status line for the latest Claude API call,
// showing model, context usage, cost, duration, and API status.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dustin/go-humanize"
	"github.com/fatih/color"
	"golang.org/x/term"
)

const (
	padding   = 5
	separator = " | "

	statusOK   = "🟢"
	statusWARN = "🟡"
	statusERR  = "🔴"

	statusAPIURL        = "https://status.claude.com/api/v2/status.json"
	statusCacheDuration = 10 * time.Minute
)

var statusFilePath = filepath.Join(".local", "state", "claude-status", "api_status.txt")

func init() {
	color.NoColor = false
}

// Types

type input struct {
	SessionID      string `json:"session_id"`
	TranscriptPath string `json:"transcript_path"`
	CWD            string `json:"cwd"`
	Model          struct {
		ID          string `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"model"`
	Workspace struct {
		CurrentDir string   `json:"current_dir"`
		ProjectDir string   `json:"project_dir"`
		AddedDirs  []string `json:"added_dirs"`
	} `json:"workspace"`
	Version     string `json:"version"`
	OutputStyle struct {
		Name string `json:"name"`
	} `json:"output_style"`
	Cost struct {
		TotalCostUSD       float64 `json:"total_cost_usd"`
		TotalDurationMS    int     `json:"total_duration_ms"`
		TotalAPIDurationMS int     `json:"total_api_duration_ms"`
		TotalLinesAdded    int     `json:"total_lines_added"`
		TotalLinesRemoved  int     `json:"total_lines_removed"`
	} `json:"cost"`
	ContextWindow struct {
		TotalInputTokens    int             `json:"total_input_tokens"`
		TotalOutputTokens   int             `json:"total_output_tokens"`
		ContextWindowSize   int             `json:"context_window_size"`
		CurrentUsage        json.RawMessage `json:"current_usage"`
		UsedPercentage      *float64        `json:"used_percentage"`
		RemainingPercentage *float64        `json:"remaining_percentage"`
	} `json:"context_window"`
	Exceeds200kTokens bool `json:"exceeds_200k_tokens"`
}

type apiStatusResponse struct {
	Status struct {
		Description string `json:"description"`
	} `json:"status"`
}

type part struct {
	text string
	len  int
}

func newPart(text string, c *color.Color) *part {
	p := &part{}
	p.append(text, "", c)
	return p
}

func (p *part) append(text, separator string, c *color.Color) {
	if c == nil {
		p.text += separator + text
	} else {
		p.text += separator + c.Sprint(text)
	}
	p.len += len(text + separator)
}

func (p *part) prepend(text, separator string, c *color.Color) {
	if c == nil {
		p.text = text + separator + p.text
	} else {
		p.text = c.Sprint(text) + separator + p.text
	}
	p.len += len(text + separator)
}

func (p *part) appendPart(other *part, separator string) {
	p.text += separator + other.text
	p.len += other.len + len(separator)
}

func (p *part) prependPart(other *part, separator string) {
	p.text = other.text + separator + p.text
	p.len += other.len + len(separator)
}

func (p part) length() int {
	return p.len
}

func main() {
	var in input
	if err := json.NewDecoder(os.Stdin).Decode(&in); err != nil {
		fmt.Fprintf(os.Stderr, "error parsing JSON: %v\n", err)
		os.Exit(1)
	}

	currentUsage := parseCurrentUsage(in.ContextWindow.CurrentUsage)
	contextPct := 0
	if in.ContextWindow.UsedPercentage != nil {
		contextPct = int(*in.ContextWindow.UsedPercentage)
	}

	termWidth := getTerminalWidth() - padding
	contextBarSize := max(termWidth/3, 40)
	if contextBarSize < 10 {
		contextBarSize = 0
	}

	barColor := barColorForPct(contextPct)

	parts := []*part{}

	// Model name part
	if termWidth >= 80 {
		parts = append(parts, newPart(fmt.Sprintf("[%s]", in.Model.DisplayName), color.New(color.FgCyan)))
	}

	filled := contextPct * contextBarSize / 100
	empty := contextBarSize - filled
	contextBar := newPart(strings.Repeat("#", filled)+strings.Repeat("-", empty), barColor)
	contextTokens := newPart(fmt.Sprintf("(%s/%s tokens)", formatSI(currentUsage), formatSI(in.ContextWindow.ContextWindowSize)), nil)
	contextText := newPart(fmt.Sprintf("%d%%", contextPct), nil)
	if contextText.length()+1+contextTokens.length() < termWidth {
		contextText.appendPart(contextTokens, " ")
	}
	if contextBarSize > 0 && contextText.length()+1+contextBar.length() < termWidth {
		contextText.prependPart(contextBar, " ")
	}
	parts = append(parts, contextText)

	partCost := newPart(formatCost(in.Cost.TotalCostUSD), color.New(color.FgYellow))
	parts = append(parts, partCost)

	partDuration := newPart(formatDuration(in.Cost.TotalDurationMS), nil)
	parts = append(parts, partDuration)

	parts = append(parts, newPart(getAPIStatus(), nil))

	for _, line := range layoutLines(termWidth, parts) {
		fmt.Println(line)
	}
}

// formatCost formats a USD amount as "$X.XX".
func formatCost(usd float64) string {
	return fmt.Sprintf("$%.2f", usd)
}

// formatDuration formats milliseconds as "⏱️ Xm Ys".
func formatDuration(ms int) string {
	mins := ms / 60000
	secs := (ms % 60000) / 1000
	return fmt.Sprintf("⏱️ %dm %ds", mins, secs)
}

// barColorForPct returns the bar color based on context usage percentage.
// > 90% = red, to notify about hitting limits soon.
// > 40% = yellow, to indicate that context has reached a significant portion,
// reminding about the "dumb zone" (see https://www.youtube.com/watch?v=rmvDxxNubIg).
func barColorForPct(pct int) *color.Color {
	if pct >= 90 {
		return color.New(color.FgRed)
	}
	if pct >= 40 {
		return color.New(color.FgYellow)
	}
	return color.New(color.FgGreen)
}

// parseCurrentUsage sums the values in current_usage, which can be either
// a single number or an object with numeric values (e.g. {"input": 100, "output": 50}).
func parseCurrentUsage(raw json.RawMessage) int {
	if len(raw) == 0 {
		return 0
	}
	// Try as a single number first
	var n float64
	if json.Unmarshal(raw, &n) == nil {
		return int(n)
	}
	// Try as an object with numeric values (matches jq's add?)
	var obj map[string]float64
	if json.Unmarshal(raw, &obj) == nil {
		total := 0.0
		for _, v := range obj {
			total += v
		}
		return int(total)
	}
	return 0
}

// formatSI formats a number with SI suffixes (e.g. 1500 -> "1.5K", 1000000 -> "1M").
func formatSI(n int) string {
	val, prefix := humanize.ComputeSI(float64(n))
	return humanize.FtoaWithDigits(val, 0) + prefix
}

func getTerminalWidth() int {
	f, err := os.Open("/dev/tty")
	if err != nil {
		return 80
	}
	defer f.Close()
	w, _, err := term.GetSize(int(f.Fd()))
	if err != nil {
		return 80
	}
	return w
}

// layoutLines groups parts into lines joined by " | ", wrapping when a line would exceed termWidth.
// Layout uses len(part.text) for width; colors are applied via part.render() in the output.
func layoutLines(termWidth int, parts []*part) []string {
	var lines []string
	var lineWidth int
	for _, p := range parts {
		if p.text == "" {
			continue
		}
		candidateWidth := lineWidth + len(separator) + p.length()
		if len(lines) == 0 || candidateWidth >= termWidth {
			lines = append(lines, p.text)
			lineWidth = p.length()
		} else {
			lines[len(lines)-1] += separator + p.text
			lineWidth = candidateWidth
		}
	}
	return lines
}

// getAPIStatus returns a cached API status indicator, refreshing from the API if the cache is older than 10 minutes.
func getAPIStatus() string {
	var status string

	if home, err := os.UserHomeDir(); err == nil {
		statusFileFullPath := filepath.Join(home, statusFilePath)
		os.MkdirAll(filepath.Dir(statusFileFullPath), 0o755)
		statusFile, err := os.OpenFile(statusFileFullPath, os.O_RDWR|os.O_CREATE, 0o644)
		if err == nil {
			if info, err := statusFile.Stat(); err == nil {
				// Check cache (valid for 10 minutes)
				if time.Since(info.ModTime()) < statusCacheDuration {
					if cached, err := io.ReadAll(statusFile); err == nil {
						// Return cached status if file is valid and can be read
						return strings.TrimSpace(string(cached))
					}
				} else {
					// Otherwise, clear old cache and prepare to write new status after fetching
					if err = statusFile.Truncate(0); err == nil { // Clear old cache
						if _, err = statusFile.Seek(0, 0); err == nil {
							defer statusFile.Close()
							defer func() {
								statusFile.WriteString(status) // Update cache with new status after fetching
							}()
						}
					}
				}
			}
		}
	}

	client := &http.Client{Timeout: 5 * time.Second}
	status = fetchAPIStatus(client, statusAPIURL)
	return status
}

// fetchAPIStatus performs the HTTP request and interprets the response as a status indicator.
func fetchAPIStatus(client *http.Client, url string) string {
	resp, err := client.Get(url)
	if err != nil {
		return statusERR + fmt.Sprintf("request: %v", err.Error())
	}
	defer resp.Body.Close()
	var r apiStatusResponse
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return statusERR + fmt.Sprintf("reponse: %v", err.Error())
	}
	if strings.Contains(strings.ToLower(r.Status.Description), "operational") {
		return statusOK
	}
	return statusWARN + " degraded"
}
