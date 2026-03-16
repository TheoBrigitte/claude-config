---
name: investigate-incident
description: Investigate an incident to determine the root cause and potential impact.
---

Investigate the current incident for the Kubernetes cluster. Follow this exact sequence:

## Step 1: Investigation

Launch the `incident-investigator` subagent to perform the full investigation. Pass along any incident ID, cluster name, alert details, or other context the user has provided.

The agent will:
- Fetch alert details from PagerDuty
- Check Kubernetes state (pods, nodes, events, resources)
- Query Grafana dashboards for anomalies
- Correlate findings into a root cause hypothesis
- Write investigation notes to INVESTIGATION.md
- Propose a fix (without applying it)

If no incident reference is provided, ask the user for the incident ID or details before launching the agent.

## Step 2: Incident Management

After the investigation agent completes and you have presented the report to the user, search Slack for related incidents **before** asking the user anything.

### Search phase:
1. Search Slack for active incident channels matching patterns like `#inc-*` related to the same alert, cluster, or component
2. Search recent Slack messages and threads for keywords from the investigation (cluster name, service name, error messages)

### Present options via `AskUserQuestion`:

**If a matching incident channel and/or thread was found**, present options like:
1. Post to `#inc-<incident-name>` (the matching channel)
2. Post in thread (link to the matching thread)
3. Create a new incident via incident.io
4. Skip

**If no related Slack channel or thread was found**, present options like:
1. Create a new incident via incident.io
2. Skip

### Creating a new incident:
Use the incident.io MCP tools to create a new incident with the investigation findings (summary, severity, affected components), then post the investigation report in the newly created incident channel.

### Report format for Slack:
Adapt the investigation report to be Slack-friendly — use Slack markdown formatting, keep it concise, and include the key sections (Summary, Root Cause, Recommended Actions)
