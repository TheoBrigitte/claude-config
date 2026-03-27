---
name: investigate-incident
description: Investigate an incident to determine the root cause and potential impact.
---

Investigate incident $ARGUMENTS for the Kubernetes cluster.

If no incident reference is provided, ask the user for the incident link, ID or details before executing next steps.

Follow this exact sequence:

## Step 1: Gather Recent Context

Before launching the investigation agent, collect recent informations related to the affected cluster from Slack, Github and incident.io. Run these searches **in parallel**:

### Slack
- Search for recent messages mentioning the cluster name (e.g., `gazelle`, `iridium-prod`) using `slack_search_public_and_private`
- Search for active incident channels (`#inc-*`) related to the cluster or component using `slack_search_channels`

### GitHub (giantswarm organization)
- Search for recent issues and pull requests mentioning the cluster name, affected component, or error messages using `search_issues` and `search_pull_requests` scoped to `org:giantswarm`
- If a specific app or component is involved, check its repo (`giantswarm/{component}[-app]`) for recent commits and releases using `list_commits` and `list_releases`

### incident.io
- List recent incidents using `list_incidents` — filter or scan for ones matching the cluster name or affected components

### Compile context
Summarize what you found into a brief context block:
- Any ongoing or recent incidents on the same cluster/component
- Recent Slack discussions about the cluster
- Related GitHub issues or PRs that could explain the problem
- Recent releases or commits on affected components
- Any patterns (e.g., recurring alerts, recent changes mentioned in Slack or GitHub)

Pass this context to the investigation agent in the next step.

## Step 2: Investigation

Launch the `incident-investigator` subagent to perform the full investigation. Pass along any incident ID, cluster name, alert details, or other context the user has provided — **including the context gathered in Step 1**.

The agent will:
- Fetch alert details from PagerDuty
- Check Kubernetes state (pods, nodes, events, resources)
- Query Grafana dashboards for anomalies
- Correlate findings into a root cause hypothesis
- Write investigation notes to INVESTIGATION.md
- Propose a fix (without applying it)

You MUST present the report to the user.

## Step 3: Incident Management

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
Use the incident.io MCP tools to create a new incident with the investigation findings (summary, severity, affected components).

### Posting to the incident channel:
After creating the incident (or when posting to an existing incident channel):
1. Find the incident's Slack channel (incident.io auto-creates `#inc-*` channels — search for it using `slack_search_channels`)
2. Send the investigation report directly into the channel using `slack_send_message` — do NOT draft, send it immediately
3. If the channel isn't found yet (creation delay), wait a few seconds and retry the search

### Report format for Slack:
Adapt the investigation report to be Slack-friendly — use Slack markdown formatting, keep it concise, and include the key sections (Summary, Root Cause, Recommended Actions)
