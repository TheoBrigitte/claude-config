---
name: standup
description: Write a standup report of what I did for Giant Swarm on a given day, from my GitHub and Slack activity. Use when the user asks for a standup, a daily summary, or "what did I do today/yesterday/on <date>".
argument-hint: [today | yesterday | YYYY-MM-DD]
---

Write a standup for $ARGUMENTS.

## Step 1: Resolve the date

- No argument or `today` → today's date.
- `yesterday` → today minus one day.
- Any other value → parse it as a date and normalise to `YYYY-MM-DD`.

Use `date -d '<value>' +%F` to resolve it. Stop and ask if the value does not parse.

## Step 2: Identify me

- GitHub: call `mcp__github__get_me` for the login (expected `TheoBrigitte`).
- Slack: call `mcp__slack__slack_read_user_profile` with no user for my user ID.

## Step 3: Collect GitHub activity

Scope every query to `org:giantswarm` and the resolved `<date>`. Run the searches in parallel:

| What | Tool | Query |
|---|---|---|
| PRs opened | `mcp__github__search_pull_requests` | `author:<login> org:giantswarm created:<date>` |
| PRs merged | `mcp__github__search_pull_requests` | `author:<login> org:giantswarm merged:<date>` |
| PRs reviewed | `mcp__github__search_pull_requests` | `reviewed-by:<login> org:giantswarm updated:<date> -author:<login>` |
| PRs commented | `mcp__github__search_pull_requests` | `commenter:<login> org:giantswarm updated:<date> -author:<login>` |
| Issues opened | `mcp__github__search_issues` | `author:<login> org:giantswarm created:<date>` |
| Issues commented | `mcp__github__search_issues` | `commenter:<login> org:giantswarm updated:<date>` |
| Issues closed | `mcp__github__search_issues` | `assignee:<login> org:giantswarm closed:<date>` |
| Open PRs | `mcp__github__search_pull_requests` | `author:<login> org:giantswarm is:open updated:<date>` |

`updated:<date>` matches any update by anyone. For reviewed and commented hits, confirm my activity on that date with `mcp__github__pull_request_read` or `mcp__github__issue_read`. Drop hits without my activity on that date.

## Step 4: Collect Slack activity

Search with `mcp__slack__slack_search_public_and_private`:

- `from:<@USER_ID> on:<date>`

Page through all results. For messages inside a thread, read the thread with `mcp__slack__slack_read_thread` to get the topic. Skip trivial messages: greetings, emoji-only, "thanks", "ok".

## Step 5: Group the activity

- Merge GitHub and Slack items about the same topic into one entry. Match on repo, PR or issue link, cluster name, incident name, or customer.
- Classify each entry:
  - **Done**: merged PRs, closed issues, finished reviews, resolved incidents, answered questions.
  - **In progress**: open PRs, ongoing investigations, unresolved threads.
  - **Blockers**: only items where I wrote that I am blocked or waiting on someone.
- Drop sections with no entries.

## Step 6: Write the file

Write `standup.<date>.md` in the current working directory. Read the file first if it exists, and ask before overwriting it.

Format:

```markdown
# Standup <date>

## Done
- <topic>: <what I did, one short sentence>
  - https://github.com/giantswarm/<repo>/pull/<n>
  - https://gigantic.slack.com/archives/<channel>/p<ts>

## In progress
- <topic>: <current state, one short sentence>
  - <links>

## Blockers
- <topic>: <who or what I wait on>
  - <links>
```

Rules:
- One entry per topic. One sentence per entry. Under 15 words.
- Start each sentence with a past-tense verb for Done and a present-tense verb for In progress.
- Print full URLs on their own line. Never wrap URLs in markdown link syntax, backticks, or brackets.
- At most 3 links per entry. Prefer the PR or issue link, then the Slack thread permalink.
- Only include what the collected data shows. Never invent work, outcomes, or links.

## Step 7: Report

Print the file path and the file content to the user.
