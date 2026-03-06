package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"github.com/spf13/cobra"
)

var defaultTimeout = 10 * time.Minute

var mcpCmd = &cobra.Command{
	Use:   "mcp",
	Short: "Start claudy as an MCP server (stdio transport)",
	RunE:  runMCP,
}

func init() {
	mcpCmd.Flags().Duration("timeout", defaultTimeout, "default timeout for run_agent calls")
}

func runMCP(cmd *cobra.Command, args []string) error {
	timeout, _ := cmd.Flags().GetDuration("timeout")

	s := server.NewMCPServer("claudy", "1.0.0",
		server.WithInstructions(`Claudy spawns autonomous Claude Code agents that can interact with external services (GitHub, Slack, Kubernetes, PagerDuty, Prometheus, etc.) through MCP servers.

Workflow:
1. Call list_servers to see which MCP servers (integrations) are available.
2. Call run_agent with a prompt and the relevant mcp_servers to delegate a task to a new Claude agent that has access to those integrations.

Use this whenever you need to perform actions or retrieve information from external services. Each run_agent call launches an independent, stateless agent.`),
		server.WithRecovery(),
	)

	s.AddTool(listServersTool(), listServersHandler)
	s.AddTool(runAgentTool(), runAgentHandler(timeout))

	return server.ServeStdio(s)
}

// list_servers tool

func listServersTool() mcp.Tool {
	return mcp.NewTool("list_servers",
		mcp.WithDescription("List available MCP server integrations (e.g. github, slack, kubernetes, pagerduty). Call this first to discover which servers you can pass to run_agent. Returns a JSON array of {name, description}."),
	)
}

func listServersHandler(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	mcpDirPath, err := resolveMCPDir()
	if err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}

	servers, err := getServers(mcpDirPath)
	if err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}

	type entry struct {
		Name        string `json:"name"`
		Description string `json:"description"`
	}

	out := make([]entry, len(servers))
	for i, s := range servers {
		out[i] = entry{Name: s.name, Description: s.desc}
	}

	data, err := json.Marshal(out)
	if err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText(string(data)), nil
}

// run_agent tool

func runAgentTool() mcp.Tool {
	return mcp.NewTool("run_agent",
		mcp.WithDescription("Spawn an autonomous Claude Code agent to perform a task. The agent can interact with external services when given the appropriate mcp_servers (from list_servers). Use this to delegate tasks like: creating GitHub PRs, querying Prometheus metrics, managing Kubernetes resources, sending Slack messages, investigating PagerDuty incidents, etc. Returns the agent's full output."),
		mcp.WithString("prompt",
			mcp.Required(),
			mcp.Description("A detailed task description for the agent. Be specific about what you want it to do and what output you expect."),
		),
		mcp.WithArray("mcp_servers",
			mcp.Description("Which MCP servers the agent should have access to (e.g. [\"github\", \"slack\"]). Get available names from list_servers. Omit or pass [] if no external integrations are needed."),
		),
		mcp.WithString("model",
			mcp.Description("Model to use: \"sonnet\" (fast, cheap), \"opus\" (smartest), or \"haiku\" (fastest, cheapest). Defaults to sonnet."),
		),
		mcp.WithString("allowed_tools",
			mcp.Description("Restrict which tools the agent can use (comma-separated). Leave empty to allow all tools from the selected MCP servers."),
		),
		mcp.WithNumber("max_turns",
			mcp.Description("Limit the number of agentic reasoning turns. Use lower values (3-5) for simple lookups, higher (10-20) for complex multi-step tasks."),
		),
		mcp.WithNumber("timeout_seconds",
			mcp.Description("Max execution time in seconds. Defaults to 600 (10 minutes). Increase for long-running tasks."),
		),
	)
}

func runAgentHandler(defaultTimeout time.Duration) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args := req.GetArguments()

		prompt, _ := args["prompt"].(string)
		if prompt == "" {
			return mcp.NewToolResultError("prompt is required"), nil
		}

		timeout := defaultTimeout
		if ts, ok := args["timeout_seconds"].(float64); ok && ts > 0 {
			timeout = time.Duration(ts) * time.Second
		}

		mcpDirPath, err := resolveMCPDir()
		if err != nil {
			return mcp.NewToolResultError(err.Error()), nil
		}

		claudeArgs := []string{
			"--print",
			"--no-session-persistence",
			"--output-format", "json",
			"--strict-mcp-config",
			"--no-chrome",
		}

		if serverNames, ok := args["mcp_servers"].([]interface{}); ok && len(serverNames) > 0 {
			var configs []string
			for _, sn := range serverNames {
				name, _ := sn.(string)
				if name == "" {
					continue
				}
				if name == "chrome" {
					// Replace --no-chrome with --chrome
					for i, a := range claudeArgs {
						if a == "--no-chrome" {
							claudeArgs[i] = "--chrome"
							break
						}
					}
					continue
				}
				cfg := filepath.Join(mcpDirPath, name+".json")
				configs = append(configs, cfg)
			}
			if len(configs) > 0 {
				claudeArgs = append(claudeArgs, "--mcp-config")
				claudeArgs = append(claudeArgs, configs...)
			}
		}

		if model, _ := args["model"].(string); model != "" {
			claudeArgs = append(claudeArgs, "--model", model)
		}

		if allowed, _ := args["allowed_tools"].(string); allowed != "" {
			claudeArgs = append(claudeArgs, "--allowedTools", allowed)
		}

		if maxTurns, ok := args["max_turns"].(float64); ok && maxTurns > 0 {
			claudeArgs = append(claudeArgs, "--max-turns", fmt.Sprintf("%d", int(maxTurns)))
		}

		claudeArgs = append(claudeArgs, prompt)

		ctx, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()

		cmd := exec.CommandContext(ctx, "claude", claudeArgs...)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		if err := cmd.Run(); err != nil {
			errMsg := fmt.Sprintf("claude exited with error: %v", err)
			if stderr.Len() > 0 {
				errMsg += "\nstderr: " + stderr.String()
			}
			if stdout.Len() > 0 {
				errMsg += "\nstdout: " + stdout.String()
			}
			return mcp.NewToolResultError(errMsg), nil
		}

		return mcp.NewToolResultText(stdout.String()), nil
	}
}
