---
name: investigate-incident
description: Investigate an incident to determine the root cause and potential impact.
argument-hint: [pagerduty-incident-link | pagerduty-incident-id]
---

Investigate incident $ARGUMENTS for the Kubernetes cluster.

If no incident reference is provided, ask the user for the incident link, ID or details before executing next steps.

Follow this exact sequence:

## Step 1: Gather Recent Context

Launch the `incident-context-gatherer` subagent to collect recent context from PagerDuty, Slack, GitHub, and incident.io related to the affected cluster. Pass along the incident reference, cluster name, alert details, component names, and any other context the user has provided.

Pass this context to the investigation agent in the next step.

## Step 2: Investigation

Launch the `incident-investigator` subagent to perform the full investigation. Pass along any incident ID, cluster name, alert details, or other context the user has provided — **including the context gathered in Step 1**.

You MUST present the report to the user.

## Step 3: Incident Management

After the investigation agent completes and you have presented the report to the user, run the search phase below first — do NOT prompt the user until the second context-gathering pass is complete.

### Search phase:
Launch the `incident-context-gatherer` subagent again, this time including any new information learned during the investigation (root cause, affected components, error messages, related services). This second pass may surface Slack threads, incidents, or GitHub activity that weren't relevant before but match the investigation findings.

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
Use `mcp__incident-io__create_incident` to create a new incident with the investigation findings (summary, severity, affected components).

### Posting to the incident channel:
After creating the incident (or when posting to an existing incident channel):
1. Find the incident's Slack channel (incident.io auto-creates `#inc-*` channels — search for it using `mcp__slack__slack_search_channels`)
2. Send the investigation report directly into the channel using `mcp__slack__slack_send_message` — do NOT draft, send it immediately

### Report format for Slack:
Adapt the investigation report to be Slack-friendly — use Slack markdown formatting, keep it concise, and include the key sections (Summary, Root Cause, Recommended Actions)
