package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/spf13/cobra"
)

var mcpDir = filepath.Join("projects", "ai", "mcp-servers")

var rootCmd = &cobra.Command{
	Use:   "claudy [flags] [CLAUDE_ARGS...]",
	Short: "Launch claude with MCP server configurations",
	Long: `Launch claude with MCP server configurations.

Claudy flags:
      --mcp-list              List available MCP servers
      --mcp-servers strings   MCP servers to launch (comma-separated or repeated)

All other flags are passed through to claude.`,
	Example: `  claudy --mcp-list
  claudy --mcp-servers github,pagerduty
  claudy --mcp-servers github --mcp-servers pagerduty
  claudy --mcp-servers github --print --output-format json 'Hi'`,
	SilenceUsage:       true,
	SilenceErrors:      true,
	DisableFlagParsing: true,
	RunE:               run,
}

// parseArgs extracts claudy-specific flags from args and returns the remaining
// args to pass through to claude.
func parseArgs(args []string) (help bool, mcpList bool, mcpServers []string, rest []string) {
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--help" || args[i] == "-h":
			help = true
		case args[i] == "--mcp-list":
			mcpList = true
		case args[i] == "--mcp-servers" && i+1 < len(args):
			i++
			for s := range strings.SplitSeq(args[i], ",") {
				if s = strings.TrimSpace(s); s != "" {
					mcpServers = append(mcpServers, s)
				}
			}
		case strings.HasPrefix(args[i], "--mcp-servers="):
			val := strings.TrimPrefix(args[i], "--mcp-servers=")
			for s := range strings.SplitSeq(val, ",") {
				if s = strings.TrimSpace(s); s != "" {
					mcpServers = append(mcpServers, s)
				}
			}
		default:
			rest = append(rest, args[i])
		}
	}
	return
}

func main() {
	log.Logger = zerolog.New(zerolog.ConsoleWriter{
		Out:             os.Stderr,
		FormatTimestamp: func(i interface{}) string { return "" },
	}).With().Logger()

	if err := rootCmd.Execute(); err != nil {
		log.Fatal().Msg(err.Error())
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

func run(cmd *cobra.Command, rawArgs []string) error {
	help, mcpList, mcpServers, passArgs := parseArgs(rawArgs)

	if help {
		return cmd.Help()
	}

	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatal().Err(err).Msg("cannot determine home directory")
	}
	mcpDirPath := filepath.Join(home, mcpDir)

	if mcpList {
		return listServers(mcpDirPath)
	}

	var (
		mcpConfigs []string
		chrome     = false
	)

	for _, s := range mcpServers {
		if s == "chrome" {
			passArgs = append(passArgs, "--chrome")
			chrome = true
			continue
		}
		if s == "grafana" {
			err := runMcpGrafanaHook(cmd, rawArgs)
			if err != nil {
				return fmt.Errorf("failed to run mcp-grafana hook: %w", err)
			}
		}
		cfg := filepath.Join(mcpDirPath, s+".json")
		if _, err := os.Stat(cfg); os.IsNotExist(err) {
			return fmt.Errorf("no config for '%s' (%s)", s, cfg)
		}
		mcpConfigs = append(mcpConfigs, cfg)
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

	log.Info().Msgf("exec claude %s", strings.Join(args, " "))
	return syscall.Exec(claudePath, append([]string{"claude"}, args...), os.Environ())
}
