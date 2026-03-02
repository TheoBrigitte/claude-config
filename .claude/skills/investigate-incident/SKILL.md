---
name: investigate-incident
description: Investigate an incident to determine the root cause and potential impact.
---

Investigate the current incident for the Kubernetes cluster. Follow this exact sequence:
1) Fetch the alert details from PagerDuty
2) Use kubectl to check pod status, node conditions, and recent events in the affected namespace
3) Check for resource pressure (CPU, memory, disk) on affected nodes
4) Query relevant Grafana dashboards for anomalies in the last 2 hours
5) Correlate all findings into a root cause hypothesis

Write your investigation notes to INVESTIGATION.md as you go. After identifying the root cause, propose a fix but DO NOT apply it without my approval. If any step takes more than 60 seconds, skip it and note the timeout.
If no incident reference is provided, ask the user for the incident ID or details to proceed with the investigation.
