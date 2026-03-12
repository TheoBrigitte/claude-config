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

## Step 2: Slack Communication (optional)

After the investigation agent completes and you have presented the report to the user, **ask the user** if they want the report posted to Slack.

If the user agrees:
1. **Check for an existing incident channel**: Search Slack for an active incident channel related to the same alert, cluster, or component. Look for channels matching patterns like `#inc-*`, `#incident-*`, or similar naming conventions
2. **If a matching channel exists**: Post the investigation report as a message in that existing channel
3. **If no matching channel exists**: Create a new incident channel using the Slack incident.io bot by invoking `/incident` in an appropriate channel (e.g., `#incidents` or `#alerts`), then post the report in the newly created channel
4. **Report format for Slack**: Adapt the investigation report to be Slack-friendly — use Slack markdown formatting, keep it concise, and include the key sections (Summary, Root Cause, Recommended Actions)
