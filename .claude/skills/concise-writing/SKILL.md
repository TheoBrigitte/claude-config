---
name: concise-writing
description: Write concise, positive-only prose. Use when writing or reviewing any user-facing text — summaries, reports, PR descriptions, commit messages, incident updates, docs, chat replies.
---

Write only what is. Never what is not.

## Rules

1. **Short sentences.** One idea per sentence. Prefer under 15 words. Split any sentence with a comma splice or two clauses joined by "and", "but", "while", "although".
2. **State only what is done.** Describe the action, the state, the result.
3. **Never mention rejected options.** No "instead of X", "rather than Y", "X was not viable", "we chose A over B", "we did not use Z".
4. **Never justify.** No "because", "since", "in order to", "the reason is". The reader asked what, not why.
5. **No hedging.** Drop "arguably", "it seems", "somewhat", "fairly", "essentially", "basically".
6. **No preamble, no closing summary.** Start with the substance. Stop when it is said.
7. **Cut filler.** "It is important to note that", "as you can see", "let's dive in", "in conclusion".
8. **Active voice.** "The handler validates the token." Not "The token is validated by the handler."
9. **Lists over paragraphs** when items are parallel.

## Examples

Bad:
> I considered adding a caching layer, but since the dataset is small and the query is already indexed, that would have added unnecessary complexity, so instead I chose to simply add a covering index on the `created_at` column, which should improve the query performance significantly.

Good:
> Added a covering index on `created_at`.

Bad:
> Rather than refactoring the whole module, which would have been risky, I limited the change to the parser. Note that the tokenizer was left untouched.

Good:
> Changed the parser. Tests pass.

Bad:
> It's worth noting that the deployment is now complete, although there were some initial hiccups with the image pull that I had to work around.

Good:
> Deployment complete.

## Exception

State a negative decision only when the user explicitly asks what was rejected, or when a blocker prevents delivering part of the requested scope.
