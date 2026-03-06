---
name: generate-llms-txt
description: >
  Generate llms.txt and llms-full.txt files for a website following the llms.txt specification.
  TRIGGER when: user asks to generate llms.txt, create an LLM-friendly site index, or make a website LLM-readable.
  DO NOT TRIGGER when: user is editing an existing llms.txt or asking about the llms.txt spec in general.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent, WebFetch, WebSearch
argument-hint: <website-url>
---

# Generate llms.txt and llms-full.txt

Generate `llms.txt` and `llms-full.txt` files for the website at `$ARGUMENTS`.

If no URL is provided, ask the user for the target website URL before proceeding.

## What is llms.txt?

The `/llms.txt` file (see https://llmstxt.org/) is a markdown file that provides LLM-friendly content about a website. It helps AI models quickly understand what a site is about. There are two files:

- **llms.txt** — A concise index: title, summary blockquote, then `## Sections` with `- [Link Title](URL): One-line description` entries.
- **llms-full.txt** — The full expanded version: same structure but with the actual page content inlined under each section, separated by `---` dividers.

## Procedure

Follow these steps in order. Use parallel tool calls wherever possible.

### Phase 1: Reconnaissance

Fetch these in parallel:
1. `<site>/robots.txt` — Note any disallowed paths to respect.
2. `<site>/sitemap.xml` — Extract all URLs; group by path pattern.
3. The site's homepage — Understand what the company/project does.
4. Reference examples for format:
   - `https://platform.claude.com/llms.txt`
   - `https://modelcontextprotocol.io/llms.txt`

From the sitemap and homepage navigation, build a **complete URL inventory** grouped into logical sections (e.g., product pages, use cases, docs, blog, company).

### Phase 2: Content Crawling

Using the URL inventory from Phase 1, fetch all important pages in parallel batches (use `parallel_read_url` with up to 5 URLs per batch). Prioritize:
1. Main product/service pages
2. Use case pages
3. Documentation overview and key sections
4. Customer stories / case studies
5. About, pricing, and company pages
6. A sample of recent blog posts (not all — summarize the blog section instead)

Skip: privacy policy content, terms of service content, cookie banners, navigation chrome, footers. Extract only the meaningful content from each page.

### Phase 3: Generate llms.txt

Write `llms.txt` to the current working directory. Follow this exact format:

```markdown
# Site Name

> One paragraph summary of what this site/company/project is. Should be 2-3 sentences max, packed with the key facts an LLM needs.

Optional: One short paragraph of additional context (founded when, key stats, certifications).

## Section Name

- [Page Title](https://full-url): One-line description of what this page covers
- [Page Title](https://full-url): One-line description of what this page covers

## Another Section

- [Page Title](https://full-url): One-line description
```

Rules for llms.txt:
- The `# Title` must be the site/project name
- The `> blockquote` must be a dense, informative summary
- Group pages into logical `## Sections` (not one flat list)
- Every entry is `- [Title](URL): Description` — the description should be a single informative line, not marketing fluff
- Include 30-80 entries total (be selective — skip low-value pages)
- Do NOT include: duplicate pages, pagination pages, tag pages, author pages, or pages blocked by robots.txt

### Phase 4: Generate llms-full.txt

Write `llms-full.txt` to the current working directory. Follow this format:

```markdown
# Site Name

> Same blockquote summary as llms.txt.

Same context paragraph as llms.txt.

For a concise index of all pages, see [llms.txt](https://<site>/llms.txt).

---

## Page Title

Source: https://full-url-of-this-page

[Clean, structured markdown content of the page. Strip navigation chrome, cookie banners, footers, and duplicate content. Preserve headings, lists, tables, and quotes. Rewrite into clean prose where the raw crawl is messy.]

---

## Next Page Title

Source: https://full-url-of-next-page

[Content...]
```

Rules for llms-full.txt:
- Every `## Section` corresponds to a single page with its `Source:` URL
- Strip all navigation, footers, cookie notices, and boilerplate
- Preserve the meaningful structure: headings, lists, tables, blockquotes
- Clean up duplicated content (many CMSes repeat sections)
- For blog listing pages, include recent post titles/dates/summaries rather than full post content
- End with a `## Company Information` section consolidating: name, founded, HQ, contact, social links, certifications, key technologies

### Phase 5: Summary

After writing both files, report to the user:
- File paths and sizes
- Number of pages indexed in llms.txt
- Number of pages with full content in llms-full.txt
- Any notable gaps (pages that couldn't be fetched, sections with thin content)
