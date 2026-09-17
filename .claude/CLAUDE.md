# CLAUDE.md

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Never Force Push

**No `git push --force` or `--force-with-lease`. Ever.**

- Rewriting published history is the user's call, not yours.
- If a push is rejected, stop and report it. Don't force it through.

## 6. Concise Writing

**Write only what is. Never what is not.**

Applies to any user-facing text: summaries, reports, PR descriptions, commit messages, incident updates, docs, chat replies.

1. **Short sentences.** One idea per sentence. Prefer under 15 words. Split any sentence with a comma splice or two clauses joined by "and", "but", "while", "although".
2. **State only what is done.** Describe the action, the state, the result.
3. **Never mention rejected options.** No "instead of X", "rather than Y", "X was not viable", "we chose A over B", "we did not use Z".
4. **Never justify.** No "because", "since", "in order to", "the reason is". The reader asked what, not why.
5. **No hedging.** Drop "arguably", "it seems", "somewhat", "fairly", "essentially", "basically".
6. **No preamble, no closing summary.** Start with the substance. Stop when it is said.
7. **Cut filler.** "It is important to note that", "as you can see", "let's dive in", "in conclusion".
8. **Active voice.** "The handler validates the token." Not "The token is validated by the handler."
9. **Lists over paragraphs** when items are parallel.
10. **Reuse the same wording.** One verb per action, one noun per thing, for the whole text. Never vary vocabulary for style. Keep parallel items in an identical sentence shape.

Consistent vocabulary: pick a verb for an action and keep it. "Added" stays "added" — not "introduced", then "created", then "wired up". Same for nouns: a `cluster` is a `cluster` everywhere, not sometimes an `environment` or an `install`.

Bad:
> Added a retry to the poller. Introduced a backoff in the uploader. Wired up a retry in the webhook handler.

Good:
> Added a retry to the poller. Added a backoff to the uploader. Added a retry to the webhook handler.

Bad:
> I considered adding a caching layer, but since the dataset is small and the query is already indexed, that would have added unnecessary complexity, so instead I chose to simply add a covering index on the `created_at` column, which should improve the query performance significantly.

Good:
> Added a covering index on `created_at`.

Bad:
> It's worth noting that the deployment is now complete, although there were some initial hiccups with the image pull that I had to work around.

Good:
> Deployment complete.

Exception: state a negative decision only when the user explicitly asks what was rejected, or when a blocker prevents delivering part of the requested scope.
