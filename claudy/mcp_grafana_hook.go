package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/rs/zerolog/log"
	"github.com/spf13/cobra"
)

const (
	grafanaURL         = "http://localhost:3000"
	grafanaNamespace   = "monitoring"
	grafanaService     = "svc/grafana"
	grafanaLocalPort   = "3000"
	grafanaServicePort = "3000"
	serviceAccountName = "claude"
	grafanaSecretName  = "grafana"
	grafanaOrgCRName   = "shared-org"
)

//func init() {
//	rootCmd.AddCommand(mcpGrafanaHookCmd)
//}

var mcpGrafanaHookCmd = &cobra.Command{
	Use:   "mcp-grafana-hook",
	Short: "Claude Code hook to setup Grafana MCP server prerequisites",
	Long: `Setup hook for the mcp-grafana MCP server.

This command is designed to be used as a Claude Code SessionStart hook.
It performs the following setup operations:
  1. Starts a kubectl port-forward to the Grafana service in the monitoring namespace
  2. Creates a Grafana service account token
  3. Sets GRAFANA_SERVICE_ACCOUNT_TOKEN via CLAUDE_ENV_FILE`,
	RunE: runMcpGrafanaHook,
}

// kubectlContext returns the kubectl context to use for Grafana operations.
// It derives it from the current context by keeping only the first two
// dash-separated segments.
// Example: "teleport.giantswarm.io-sardine-us01-smfct-prd" → "teleport.giantswarm.io-sardine"
func kubectlContext() (string, error) {
	out, err := exec.Command("kubectl", "config", "current-context").Output()
	if err != nil {
		return "", fmt.Errorf("get current kubectl context: %w", err)
	}
	current := strings.TrimSpace(string(out))
	parts := strings.SplitN(current, "-", 3)
	if len(parts) < 2 {
		return current, nil
	}
	ctx := parts[0] + "-" + parts[1]
	log.Debug().Str("current", current).Str("derived", ctx).Msg("derived kubectl context")
	return ctx, nil
}

func runMcpGrafanaHook(cmd *cobra.Command, args []string) error {
	// envFile := os.Getenv("CLAUDE_ENV_FILE")

	// Derive the kubectl context to use
	kubeCtx, err := kubectlContext()
	if err != nil {
		return err
	}

	// Step 1: Start kubectl port-forward (skip if port already open)
	if portOpen(grafanaLocalPort) {
		log.Warn().Msg("port " + grafanaLocalPort + " already open, skipping port-forward")
	} else {
		log.Debug().Msg("starting kubectl port-forward to grafana")
		pfCmd := exec.Command("kubectl", "--context", kubeCtx, "--namespace", grafanaNamespace,
			"port-forward", grafanaService, grafanaLocalPort+":"+grafanaServicePort)
		pfCmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
		if err := pfCmd.Start(); err != nil {
			return fmt.Errorf("failed to start port-forward: %w", err)
		}
		log.Debug().Int("pid", pfCmd.Process.Pid).Msg("port-forward started")

		if err := waitForPort(grafanaLocalPort, 30*time.Second); err != nil {
			_ = pfCmd.Process.Kill()
			return fmt.Errorf("port-forward not ready: %w", err)
		}
		log.Debug().Msg("port-forward is ready")
	}

	// Step 2: Get Grafana org ID from GrafanaOrganization CR
	orgID, err := getGrafanaOrgID(kubeCtx)
	if err != nil {
		return fmt.Errorf("failed to get grafana org ID: %w", err)
	}
	log.Debug().Str("orgID", orgID).Msg("got grafana org ID")

	// Step 3: Get Grafana admin credentials from k8s secret (with local cache)
	adminUser, adminPass, err := getGrafanaAdminCreds(kubeCtx)
	if err != nil {
		return fmt.Errorf("failed to get grafana admin credentials: %w", err)
	}
	log.Debug().Str("user", adminUser).Msg("got grafana admin credentials")

	err = os.Setenv("GRAFANA_USERNAME", adminUser)
	if err != nil {
		return fmt.Errorf("failed to set GRAFANA_USERNAME env var: %w", err)
	}

	err = os.Setenv("GRAFANA_PASSWORD", adminPass)
	if err != nil {
		return fmt.Errorf("failed to set GRAFANA_PASSWORD env var: %w", err)
	}

	saID, err := findServiceAccount(adminUser, adminPass, serviceAccountName, orgID)
	if err != nil {
		return fmt.Errorf("failed to search service accounts: %w", err)
	}

	if saID == 0 {
		saID, err = createServiceAccount(adminUser, adminPass, serviceAccountName, orgID)
		if err != nil {
			return fmt.Errorf("failed to create service account: %w", err)
		}
		log.Debug().Int("id", saID).Msg("created service account")
	} else {
		log.Debug().Int("id", saID).Msg("found existing service account")
	}

	tokenName := "claude-" + strconv.FormatInt(time.Now().Unix(), 10)
	token, err := createServiceAccountToken(adminUser, adminPass, saID, tokenName, orgID)
	if err != nil {
		return fmt.Errorf("failed to create service account token: %w", err)
	}
	log.Debug().Msg("created service account token")

	// Step 3: Set environment variable via CLAUDE_ENV_FILE
	//if envFile != "" {
	//	f, err := os.OpenFile(envFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	//	if err != nil {
	//		return fmt.Errorf("failed to open CLAUDE_ENV_FILE: %w", err)
	//	}
	//	defer f.Close()
	//	fmt.Fprintf(f, "export GRAFANA_SERVICE_ACCOUNT_TOKEN=%s\n", token)
	//	log.Info().Msg("wrote GRAFANA_SERVICE_ACCOUNT_TOKEN to CLAUDE_ENV_FILE")
	//} else {
	log.Debug().Msg("setting GRAFANA_SERVICE_ACCOUNT_TOKEN environment variable for this session")
	return os.Setenv("GRAFANA_SERVICE_ACCOUNT_TOKEN", token)
	//}
}

func portOpen(port string) bool {
	conn, err := net.DialTimeout("tcp", "localhost:"+port, time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func waitForPort(port string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if portOpen(port) {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("timeout waiting for port %s", port)
}

// getGrafanaAdminCreds fetches admin user/password from the k8s secret
// "grafana" in the monitoring namespace.
func getGrafanaAdminCreds(kubeCtx string) (string, string, error) {
	log.Debug().Msg("fetching grafana admin credentials from k8s secret")
	out, err := exec.Command("kubectl", "--context", kubeCtx, "get", "secret", "-n", grafanaNamespace,
		grafanaSecretName, "-o", "jsonpath={.data}").Output()
	if err != nil {
		return "", "", fmt.Errorf("kubectl get secret: %w", err)
	}

	var secretData map[string]string
	if err := json.Unmarshal(out, &secretData); err != nil {
		return "", "", fmt.Errorf("parse secret data: %w", err)
	}

	adminUser, err := base64Decode(secretData["admin-user"])
	if err != nil {
		return "", "", fmt.Errorf("decode admin-user: %w", err)
	}
	adminPass, err := base64Decode(secretData["admin-password"])
	if err != nil {
		return "", "", fmt.Errorf("decode admin-password: %w", err)
	}

	return adminUser, adminPass, nil
}

func base64Decode(s string) (string, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// getGrafanaOrgID fetches the org ID from the GrafanaOrganization CR.
func getGrafanaOrgID(kubeCtx string) (string, error) {
	log.Debug().Msg("fetching grafana org ID from GrafanaOrganization CR")
	out, err := exec.Command("kubectl", "--context", kubeCtx, "-n", grafanaNamespace,
		"get", "grafanaorganizations", grafanaOrgCRName,
		"-o", "jsonpath={.status.orgID}").Output()
	if err != nil {
		return "", fmt.Errorf("kubectl get grafanaorganizations: %w", err)
	}
	orgID := strings.TrimSpace(string(out))
	if orgID == "" {
		return "", fmt.Errorf("empty orgID in GrafanaOrganization %s", grafanaOrgCRName)
	}
	return orgID, nil
}

func grafanaRequest(method, path, adminUser, adminPass, orgID string, body interface{}) (*http.Response, error) {
	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, grafanaURL+path, reqBody)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(adminUser, adminPass)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-Grafana-Org-Id", orgID)

	return http.DefaultClient.Do(req)
}

func findServiceAccount(adminUser, adminPass, name, orgID string) (int, error) {
	resp, err := grafanaRequest("GET", "/api/serviceaccounts/search?query="+name, adminUser, adminPass, orgID, nil)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("search service accounts: %s: %s", resp.Status, body)
	}

	var result struct {
		ServiceAccounts []struct {
			ID   int    `json:"id"`
			Name string `json:"name"`
		} `json:"serviceAccounts"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, err
	}

	for _, sa := range result.ServiceAccounts {
		if sa.Name == name {
			return sa.ID, nil
		}
	}
	return 0, nil
}

func createServiceAccount(adminUser, adminPass, name, orgID string) (int, error) {
	resp, err := grafanaRequest("POST", "/api/serviceaccounts", adminUser, adminPass, orgID, map[string]interface{}{
		"name": name,
		"role": "Editor",
	})
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("create service account: %s: %s", resp.Status, body)
	}

	var result struct {
		ID int `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, err
	}
	return result.ID, nil
}

func createServiceAccountToken(adminUser, adminPass string, saID int, tokenName, orgID string) (string, error) {
	resp, err := grafanaRequest("POST", fmt.Sprintf("/api/serviceaccounts/%d/tokens", saID), adminUser, adminPass, orgID, map[string]interface{}{
		"name": tokenName,
	})
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("create token: %s: %s", resp.Status, body)
	}

	var result struct {
		Key string `json:"key"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	return result.Key, nil
}
