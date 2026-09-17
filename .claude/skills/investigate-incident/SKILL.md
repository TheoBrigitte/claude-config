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

## Step 4: Ask How to Resolve

Once the investigation is done (even if inconclusive), stop and ask the user what to do for resolution. List the options you found — fix, workaround, silence, escalate, leave as is — with your recommendation. Wait for the answer before going further.

## Step 5: Post Incident Summary

This is the LAST step — do it only after the user answered Step 4, so the summary reflects what was actually decided.

Post a one-liner summary of the alert in `#oncall-atlas` (https://gigantic.slack.com/archives/C04UMF3KV3K) with `mcp__slack__slack_send_message`. Send it immediately — do NOT draft it for review.

One-liner format:

```
<status icon> <identifier> - <description>, <links>
```

- **status icon**:
  - `:large_green_circle:` — the alert is fully resolved
  - `:large_orange_circle:` — the alert is mitigated (silence, workaround in place, ...) but not resolved
  - `:red_circle:` — the alert is still ongoing and needs attention from team atlas
- **identifier**:
  - `<alertname>/<cluster id>` when it's only one alert on one cluster
  - `<alertname>` only when it affects multiple clusters
  - `<cluster id>` only when it's a cluster-wide problem with multiple related alerts
- **description**: summarize in 25 words maximum — the root cause or ongoing problem, and what was done for resolution/mitigation; if silenced, say so and until when
- **links**: maximum 2 links — a Slack channel or thread with more information about this incident, a GitHub issue with more information if any. Omit links you don't have; never fabricate one.
