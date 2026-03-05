package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var (
	colorInfo  = color.New(color.FgBlue)
	colorError = color.New(color.FgRed)
	mcpDir     = filepath.Join("projects", "ai", "mcp-servers")
)

var (
	mcpList    bool
	mcpServers []string
)

var rootCmd = &cobra.Command{
	Use:   "claudy [flags] [-- CLAUDE_ARGS...]",
	Short: "Launch claude with MCP server configurations",
	Example: `  claudy --mcp-list
  claudy --mcp-servers github,pagerduty
  claudy --mcp-servers github --mcp-servers pagerduty
  claudy --mcp-servers github -- --dangerously-skip-permissions`,
	SilenceUsage:  true,
	SilenceErrors: true,
	Args:          cobra.ArbitraryArgs,
	RunE:          run,
}

func init() {
	rootCmd.Flags().BoolVar(&mcpList, "mcp-list", false, "List available MCP servers")
	rootCmd.Flags().StringSliceVar(&mcpServers, "mcp-servers", nil, "MCP servers to launch (comma-separated or repeated)")
}

func logInfo(msg string) {
	colorInfo.Fprint(os.Stderr, "INFO")
	fmt.Fprintf(os.Stderr, "  %s\n", msg)
}

func logError(msg string) {
	colorError.Fprint(os.Stderr, "ERROR")
	fmt.Fprintf(os.Stderr, " %s\n", msg)
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		logError(err.Error())
		os.Exit(1)
	}
}

func serverDescription(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var cfg struct {
		MCPServers map[string]struct {
			Description string `json:"description"`
		} `json:"mcpServers"`
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return ""
	}
	for _, v := range cfg.MCPServers {
		return v.Description
	}
	return ""
}

type serverEntry struct {
	name string
	desc string
}

func listServers(mcpDirPath string) error {
	entries, err := filepath.Glob(filepath.Join(mcpDirPath, "*.json"))
	if err != nil {
		return err
	}

	servers := []serverEntry{{name: "chrome", desc: "Browser automation via Claude in Chrome extension. (builtin)"}}
	maxLen := len("chrome")
	for _, f := range entries {
		name := strings.TrimSuffix(filepath.Base(f), ".json")
		if len(name) > maxLen {
			maxLen = len(name)
		}
		servers = append(servers, serverEntry{name: name, desc: serverDescription(f)})
	}

	fmt.Printf("  %-*s  %s\n", maxLen, "NAME", "DESCRIPTION")
	for _, s := range servers {
		fmt.Printf("  %-*s  %s\n", maxLen, s.name, s.desc)
	}
	return nil
}

func run(cmd *cobra.Command, passArgs []string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		logError(fmt.Sprintf("cannot determine home directory: %v", err))
		os.Exit(1)
	}
	mcpDirPath := filepath.Join(home, mcpDir)

	if mcpList {
		return listServers(mcpDirPath)
	}

	var (
		mcpConfigs []string
		chrome     = false
	)

	if len(mcpServers) > 0 {
		for _, s := range mcpServers {
			s = strings.TrimSpace(s)
			if s == "" {
				continue
			}
			if s == "chrome" {
				passArgs = append(passArgs, "--chrome")
				chrome = true
				continue
			}
			cfg := filepath.Join(mcpDirPath, s+".json")
			if _, err := os.Stat(cfg); os.IsNotExist(err) {
				return fmt.Errorf("no config for '%s' (%s)", s, cfg)
			}
			mcpConfigs = append(mcpConfigs, cfg)
		}
	}

	if !chrome {
		passArgs = append(passArgs, "--no-chrome")
	}

	args := []string{"--strict-mcp-config"}
	if len(mcpConfigs) > 0 {
		args = append(args, "--mcp-config")
		args = append(args, mcpConfigs...)
	}
	args = append(args, passArgs...)

	claudePath, err := exec.LookPath("claude")
	if err != nil {
		return fmt.Errorf("claude not found in PATH: %w", err)
	}

	logInfo("exec claude " + strings.Join(args, " "))
	return syscall.Exec(claudePath, append([]string{"claude"}, args...), os.Environ())
}
