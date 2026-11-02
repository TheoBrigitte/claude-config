---
name: architecture-diagrams
description: Use when creating, redrawing or editing an architecture diagram as SVG or PNG, especially Giant Swarm Observability Platform diagrams. Also use when asked to "improve this diagram", "make this diagram easier to read", "redraw this architecture", or to apply Giant Swarm branding to a diagram.
---

# Architecture Diagrams

Rules for creating and editing the Observability Platform architecture diagrams.
They apply to humans and AI agents alike.

Reference diagrams, in `~/projects/tmp/`:

- `observability-platform-architecture.svg`: High Level Architecture
- `observability-platform-full-picture.svg`: Full Picture Architecture
- `observability-platform-apps-simple.svg`: Overview
- `observability-platform-multi-tenancy.svg`: Multi-Tenancy

## Workflow

1. Start from a source image or sketch. Read it at full zoom. List every component and every link before drawing.
2. Create one output file per source. Name it after the source. Never overwrite another diagram.
3. Write the SVG by hand, or with a small generator script. Keep the SVG readable and editable.
4. Render a PNG with `rsvg-convert -z 1.5 <file>.svg -o <file>.png`. Use `-z 1.2` for very large canvases.
5. Look at the PNG after every change. Check for overlaps, clipped text and lines crossing labels.
6. Commit the SVG and the PNG together. One commit per logical change.
7. List every assumption in the hand-off message: invented descriptions, guessed links, renamed elements.

## Structure

- **Header:** title top-left, subtitle below it, legend top-right.
- **Orientation:** users on the left, workload clusters on the right. Data enters from the right and reaches users on the left.
- **Clusters:** one neutral box per cluster. The label sits centered above the box.
- **Multiple clusters:** draw 2 offset cards behind the box. Add `(× N)` to the label.
- **Observability Platform:** a tinted box inside the central cluster. Title centered inside, with the Giant Swarm icon on its left.
- **Columns:** group components in columns with uppercase section labels, e.g. `QUERY & ALERT`, `STORE`, `INGEST`.
- **Configuration:** Kubernetes Custom Resources & Configuration sit below their cluster. Arrows point up to the component that reads them.
- **External actors:** dashed pill boxes outside the clusters, e.g. External target, PagerDuty.
- **Margins:** 30px between a container edge and its content.
- **Alignment:** align boxes on shared columns and rows. Line up arrows with the centers of the boxes they connect.

## Components

- **Box content:** logo (28px), name (18px bold), one-line description (13px). Center the group in the box.
- **Logos:** use official assets only.

  | Component | Source |
  |---|---|
  | Grafana | `grafana/grafana`: `public/img/grafana_icon.svg` |
  | Mimir, Alertmanager | `grafana/grafana`: `public/app/features/alerting/unified/rule-list/components/img/mimir_logo.svg` |
  | Loki | `grafana/grafana`: `public/app/features/loki-helpers/loki_icon.svg` |
  | Tempo | `grafana/tempo`: `cmd/tempo/app/static/tempo-icon.png` |
  | Alloy | `grafana/alloy`: `docs/sources/assets/alloy_icon_orange.svg` |
  | Giant Swarm | `giantswarm/happa`: `src/images/giantswarm_icon.svg` |
  | Kubernetes | `kubernetes/kubernetes`: `logo/logo.svg` |

- **Embedding:** embed logos as base64 data URIs. The SVG stays a single file.
- **Giant Swarm components:** Giant Swarm Blue fill, white text, Giant Swarm icon. Examples: API, Operator Layer, Observability Operator, Silence Operator, Log Exporter, Giant Swarm CRs.
- **Storage backends:** each backend has an object storage cylinder below it.
- **Many links from one component:** list the targets inside the box. Draw no arrow per target.
- **Containment over arrows:** a component that controls a whole box sits inside it, e.g. the Operator Layer as a band at the bottom of the platform box.
- **Code cards:** monospaced YAML with a colored header strip.
  - Giant Swarm CRs: Giant Swarm Blue header, Giant Swarm icon, title "Giant Swarm CR".
  - Kubernetes resources: Kubernetes blue header, Kubernetes logo, title "Kubernetes resource".

## Arrows

One color per flow type. Show every type in the legend.

| Flow | Color | Style |
|---|---|---|
| Ingest (write path) | `#2563eb` | solid |
| Query (read path) | `#16a34a` | solid |
| Alerting | `#ea580c` | solid |
| Configuration | `#6b7280` | dashed `7 5` |
| Authentication | `#7c3aed` | solid, thinner |

- **Direction:** arrows point the way data flows. A querier points at what it queries. Configuration points from the source to the consumer.
- **Two-way arrows:** only when data flows both ways.
- **Routing:** horizontal and vertical segments only. Merge parallel arrows into a shared bus line.
- **Crossings:** avoid them. When a crossing is unavoidable, cut a small gap in the lower line with a halo the color of the background.
- **Labels:** 11px italic gray, a few words only, e.g. `direct`, `via Alloy`, `remote write`, `send data`.
- **Tenant diagrams:** color by tenant. Shared `#dc2626`, product `#16a34a`, checkout `#2563eb`.

## Colors

| Use | Color |
|---|---|
| Giant Swarm components | Giant Swarm Blue `#002645` |
| Text on Giant Swarm Blue | `#ffffff`, descriptions `#cfe3f0` |
| Observability Platform box | Vivid Blue tint `#ddf0fa`, border `#002645` |
| Cluster boxes | fill `#f8fafc`, border `#94a3b8` |
| Neutral boxes | fill `#ffffff`, border `#334155` |
| Storage backends | fill `#fff7ed`, border `#c2410c` |
| Alloy agents | fill `#fef2f2`, border `#dc2626` |
| Grafana | fill `#fffbeb`, border `#d97706` |
| Kubernetes header | `#326ce5` |
| Titles and names | `#0f172a` |
| Labels | `#334155` |
| Descriptions | `#475569` |
| Section labels | `#64748b` |

- **Brand colors:** take them from the Giant Swarm styleguide. Tints mix Vivid Blue `#009fff` into Giant Swarm White `#f0f7f9`.
- **YAML highlighting:** keys `#8250df`, values `#0a3069`, colons and dashes `#6e7781`, comments `#6e7781` italic. Tenant values stay bold in their tenant color.

## Typography

| Element | Style |
|---|---|
| Title | 30px bold |
| Subtitle | 15px |
| Cluster and platform labels | 17px bold |
| Component names | 18px bold |
| Descriptions | 13px |
| Section labels | 12px bold, uppercase, letter spacing 1.5px |
| Arrow labels | 11px italic |
| Code | DejaVu Sans Mono 12px, 18px line height |

- **Font:** `Noto Sans, DejaVu Sans, sans-serif`.
- **Centering:** center titles and labels on their box. Section labels stay left-aligned on their column.

## Wording

- **Title:** `Observability Platform: <View>`, e.g. `Observability Platform: Overview`.
- **Subtitle:** one sentence on what the diagram shows.
- **Names:** use these names everywhere.

  | Thing | Name |
  |---|---|
  | Central cluster | Central Platform cluster |
  | Customer clusters | Workload Clusters (× N) |
  | Platform box | Observability Platform |
  | Entry point | API, description "Observability API" |
  | Operators band | Operator Layer, description "Configures all components of the Observability Platform" |
  | Configuration box | Kubernetes Custom Resources & Configuration |

- **Spelling:** American English, e.g. "organization".
- **Descriptions:** a short noun phrase, e.g. "metrics", "logs agent", "notifications".
- **Ownership tags:** keep `not Atlas` on components owned by other teams.
- **No invention:** add no component, link or detail that the source lacks. Ask when unsure.

## SVG pitfalls

- **CSS beats attributes:** a class rule overrides presentation attributes such as `stroke`, `text-anchor` or `font-size`. Use `style="..."` or a more specific selector such as `.name.on-gs`.
- **Escaping:** write `&` as `&amp;` in text.
- **Halos:** the halo color must match the background behind the crossing.
- **Text width:** estimate about 10.4px per character at 18px bold, about 6.9px at 13px. Check the render.
- **Monospace indentation:** one character is 7.22px at 12px. Set `x` per indent level.

## Review checklist

- [ ] Title and subtitle follow the wording rules.
- [ ] Legend lists every arrow type used.
- [ ] No text overlaps a line, a box edge or other text.
- [ ] Every arrow points the way data flows.
- [ ] Every crossing has a halo gap.
- [ ] Giant Swarm components use Giant Swarm Blue and the icon.
- [ ] Logos are official assets.
- [ ] Margins are even inside every container.
- [ ] Names and spelling match the wording table.
- [ ] SVG and PNG are committed together.
