package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/spf13/cobra"
)

var (
	mcpDir     = os.Getenv("CLAUDE_CONFIG_MCP_DIR")
	sandboxCmd = os.Getenv("CLAUDE_CONFIG_SANDBOX_CMD")
	claudeCmd  = "claude"
)

// preset defines a named set of predefined claudy arguments.
type preset struct {
	MCPServers []string
}

var presets = map[string]preset{
	"sre": {
		MCPServers: []string{"jina", "github", "pagerduty", "incident-io", "kubernetes", "grafana", "slack", "sequential-thinking"},
	},
}

var rootCmd = &cobra.Command{
	Use:   "claudy [flags] [CLAUDE_ARGS...]",
	Short: "Launch claude with MCP server configurations",
	Long: `Launch claude with MCP server configurations.

Claudy flags:
      --mcp-list              List available MCP servers
      --mcp-servers strings   MCP servers to launch (comma-separated or repeated)
      --preset string         Use a predefined preset (e.g. sre)
      --preset-list           List available presets
      --sandbox               Run claude inside a sandbox

All other flags are passed through to claude.`,
	Example: `  claudy --mcp-list
  claudy --preset sre
  claudy --mcp-servers github,pagerduty
  claudy --mcp-servers github --mcp-servers pagerduty
  claudy --mcp-servers github --print --output-format json 'Hi'`,
	SilenceUsage:       true,
	SilenceErrors:      true,
	DisableFlagParsing: true,
	RunE:               run,
}

type parsedArgs struct {
	help       bool
	sandbox    bool
	mcpList    bool
	presetList bool
	presetName string
	mcpServers []string
	userArgs   []string
}

// parseArgs extracts claudy-specific flags from args and returns the remaining
// args to pass through to claude.
func parseArgs(args []string) parsedArgs {
	var p parsedArgs
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == "--help" || args[i] == "-h":
			p.help = true
		case args[i] == "--sandbox":
			p.sandbox = true
		case args[i] == "--mcp-list":
			p.mcpList = true
		case args[i] == "--preset-list":
			p.presetList = true
		case (args[i] == "--preset" || args[i] == "-p") && i+1 < len(args):
			i++
			p.presetName = args[i]
		case strings.HasPrefix(args[i], "--preset="):
			p.presetName = strings.TrimPrefix(args[i], "--preset=")
		case args[i] == "--mcp-servers" && i+1 < len(args):
			i++
			for s := range strings.SplitSeq(args[i], ",") {
				if s = strings.TrimSpace(s); s != "" {
					p.mcpServers = append(p.mcpServers, s)
				}
			}
		case strings.HasPrefix(args[i], "--mcp-servers="):
			val := strings.TrimPrefix(args[i], "--mcp-servers=")
			for s := range strings.SplitSeq(val, ",") {
				if s = strings.TrimSpace(s); s != "" {
					p.mcpServers = append(p.mcpServers, s)
				}
			}
		default:
			p.userArgs = append(p.userArgs, args[i])
		}
	}
	return p
}

func main() {
	// Pin the main goroutine to this OS thread. This ensures the port-forward
	// child process (started with Pdeathsig) and the subsequent syscall.Exec
	// both happen on the same thread. Without this, Exec kills all other Go
	// runtime threads, which triggers Pdeathsig prematurely on any child
	// forked from a different thread.
	runtime.LockOSThread()

	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	log.Logger = zerolog.New(zerolog.ConsoleWriter{
		Out:             os.Stderr,
		FormatTimestamp: func(i any) string { return "" },
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

func listPresets() {
	maxLen := 0
	for name := range presets {
		if len(name) > maxLen {
			maxLen = len(name)
		}
	}
	fmt.Printf("  %-*s  %s\n", maxLen, "NAME", "DESCRIPTION")
	for name, p := range presets {
		parts := []string{"--mcp-servers " + strings.Join(p.MCPServers, ",")}
		fmt.Printf("  %-*s  %s\n", maxLen, name, strings.Join(parts, " "))
	}
}

func run(cmd *cobra.Command, rawArgs []string) error {
	p := parseArgs(rawArgs)

	if p.help {
		return cmd.Help()
	}

	if mcpDir == "" {
		log.Fatal().Msg("CLAUDE_CONFIG_MCP_DIR is not set")
	}
	mcpDirPath := mcpDir

	if p.mcpList {
		return listServers(mcpDirPath)
	}

	if p.presetList {
		listPresets()
		return nil
	}

	// Apply preset if specified
	mcpServers := p.mcpServers
	if p.presetName != "" {
		pr, ok := presets[p.presetName]
		if !ok {
			return fmt.Errorf("unknown preset '%s' (use --preset-list to see available presets)", p.presetName)
		}
		mcpServers = append(pr.MCPServers, mcpServers...)
	}

	var (
		mcpConfigs []string
		chrome     = false
	)

	claudeArgs := []string{}
	userArgs := p.userArgs

	for _, s := range mcpServers {
		if s == "chrome" {
			claudeArgs = append(claudeArgs, "--chrome")
			chrome = true
			continue
		}
		if s == "grafana" {
			log.Info().Msg("configuring Grafana MCP server...")
			err := runMcpGrafanaHook(cmd, rawArgs)
			if err != nil {
				// return fmt.Errorf("failed to run mcp-grafana hook: %w", err)
				log.Err(err).Msg("failed to run mcp-grafana hook")
				continue
			}
			log.Info().Msg("configured Grafana MCP server successfully")
		}
		cfg := filepath.Join(mcpDirPath, s+".json")
		if _, err := os.Stat(cfg); os.IsNotExist(err) {
			return fmt.Errorf("no config for '%s' (%s)", s, cfg)
		}
		mcpConfigs = append(mcpConfigs, cfg)
	}

	if !chrome {
		claudeArgs = append(claudeArgs, "--no-chrome")
	}

	claudeArgs = append(claudeArgs, "--strict-mcp-config")

	if len(mcpConfigs) > 0 {
		claudeArgs = append(claudeArgs, "--mcp-config")
		claudeArgs = append(claudeArgs, mcpConfigs...)
	}
	// claudeArgs = append(claudeArgs, userArgs...)

	// Final command
	claudePath, err := exec.LookPath(claudeCmd)
	if err != nil {
		return fmt.Errorf("claude not found in PATH: %w", err)
	}

	command := claudePath
	args := []string{claudePath}

	if p.sandbox {
		sandboxPath, err := exec.LookPath(sandboxCmd)
		if err != nil {
			return fmt.Errorf("sandbox command %q not found in PATH: %w", sandboxCmd, err)
		}
		command = sandboxPath
		args = []string{sandboxPath}
	}
	args = append(args, claudeArgs...)
	args = append(args, userArgs...)

	log.Info().Msgf("exec %s %s", command, strings.Join(args[1:], " "))
	return syscall.Exec(command, args, os.Environ())
}
