---
name: investigate-incident
description: Investigate an incident to determine the root cause and potential impact.
argument-hint: [pagerduty-incident-link | pagerduty-incident-id]
---

Investigate incident $ARGUMENTS for the Kubernetes cluster.

If no incident reference is provided, ask the user for the incident link, ID or details before executing next steps.

Follow this exact sequence:

## Step 1: Investigation

Launch the `incident-investigator` subagent to perform the full investigation. Pass along any incident ID, cluster name, alert details, or other context the user has provided.

You MUST present the report to the user.

## Step 2: Gather Context & Correlate Similar Incidents

After the investigation agent completes and you have presented the report to the user, run the context-gathering phase below — do NOT prompt the user until it is complete.

Launch the `incident-context-gatherer` subagent to collect context from PagerDuty, Slack, GitHub, and incident.io. Include all information learned during the investigation (root cause, affected components, error messages, related services, cluster name). This pass surfaces Slack threads, related incidents, or GitHub activity that match the investigation findings.

## Step 3: Incident Management

After the context-gathering phase completes, proceed with incident management — do NOT prompt the user until this step is ready.

### Present options via `AskUserQuestion`:

**If a matching Slack incident channel and/or thread was found**, present options like:
1. Post to `#inc-<incident-name>` (the matching channel)
2. Post in thread (link to the matching thread)
3. Create a new incident via incident.io
4. Skip

**If no related Slack channel or thread was found**, present options like:
1. Create a new incident via incident.io
2. Skip

### Creating a new incident:
Create a new incident in incident.io with the investigation findings (summary, severity, affected components).

### Posting to the incident channel:
After creating the incident (or when posting to an existing incident channel):
1. Find the incident's Slack channel (incident.io auto-creates `#inc-*` channels)
2. Send the investigation report into the Slack channel and upload the full report as canvas — do NOT draft, send it immediately
