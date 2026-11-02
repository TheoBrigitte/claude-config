---
name: giantswarm-diagrams
description: Use when drawing, redrawing or editing any diagram for Giant Swarm as SVG or PNG — architecture, data flow, process, sequence or deployment diagrams. Also use when asked to "draw a diagram", "improve this diagram", "make this diagram easier to read", "redraw this sketch", "turn this whiteboard photo into a diagram", or to apply Giant Swarm branding to a diagram.
---

# Giant Swarm Diagrams

Rules for creating and editing diagrams at Giant Swarm.
They apply to humans and AI agents alike.

## Workflow

1. **Read the source.** Open the sketch, screenshot or description at full zoom. Crop and zoom into dense areas.
2. **Inventory first.** List every component, every link and every label before drawing. Ask about anything ambiguous.
3. **Glossary.** Fix one name per component for the whole diagram. Reuse existing names from related diagrams.
4. **One file per source.** Name the output after the source. Never overwrite another diagram.
5. **Write the SVG.** By hand, or with a small generator script. Keep the SVG readable and editable.
6. **Render a PNG.** `rsvg-convert -z 1.5 <file>.svg -o <file>.png`. Use `-z 1.2` for very large canvases. Fallback: `inkscape --export-type=png` or headless Chromium.
7. **Look at the PNG after every change.** Check for overlaps, clipped text and lines crossing labels.
8. **Commit the SVG and the PNG together.** One commit per logical change.
9. **Hand off with assumptions.** List invented descriptions, guessed links and renamed elements.

## Diagram types

| Type | Layout |
|---|---|
| Architecture | Containers for clusters or systems. Components in columns. Data flows left to right. |
| Data flow | Sources on the left, sinks on the right. One color per flow type. |
| Process or flowchart | Steps left to right. Decisions as diamonds. One path per outcome. |
| Sequence | Actors as columns. Time flows downward. Numbered messages. |
| Deployment | Environments as containers. Clusters inside environments. Workloads inside clusters. |
| Ownership or tenancy | One color per owner or tenant, used for boxes and arrows alike. |

## Structure

- **Header:** title top-left, subtitle below it, legend top-right.
- **Orientation:** data flows left to right. Producers on the left, consumers on the right.
- **Containers:** one box per cluster, environment or system. Center the label on the box.
- **Repeated containers:** draw 2 offset cards behind the box. Add `(× N)` to the label.
- **Nesting:** a product or platform inside a cluster gets a tinted box. Center its title inside, with its logo on the left.
- **Columns:** group components in columns with uppercase section labels, e.g. `INGRESS`, `SERVICES`, `STORAGE`.
- **Configuration:** Kubernetes Custom Resources & Configuration sit below the container that reads them. Arrows point up to the reader.
- **External actors:** dashed pill boxes outside the containers.
- **Margins:** 30px between a container edge and its content. Keep margins even on all sides.
- **Alignment:** align boxes on shared rows and columns. Line up arrows with the centers of the boxes they connect.
- **Density:** one idea per diagram. Split a crowded diagram into an overview and detail views.

## Components

- **Box content:** logo (28px), name (18px bold), one-line description (13px). Center the group in the box.
- **Logos:** use official assets only. Take them from the upstream repository. Never redraw a logo.

  | Logo | Source |
  |---|---|
  | Giant Swarm icon | `giantswarm/happa`: `src/images/giantswarm_icon.svg` |
  | Giant Swarm logo | `giantswarm/brand`: `logo/` |
  | Kubernetes | `kubernetes/kubernetes`: `logo/logo.svg` |

- **Finding other logos:** search the project's GitHub tree for `logo` or `icon` files. CNCF projects also publish logos in `cncf/artwork`.
- **Embedding:** embed logos as base64 data URIs. The SVG stays a single file.
- **Giant Swarm components:** Giant Swarm Blue fill, white text, Giant Swarm icon. Mark only components Giant Swarm builds and owns.
- **Ownership tags:** add a small italic tag such as `owned by <team>` on components another team owns.
- **Storage:** draw databases and object storage as cylinders below their owner.
- **Many links from one component:** list the targets inside the box. Draw no arrow per target.
- **Containment over arrows:** a component that controls a whole box sits inside it, e.g. an operator as a band at the bottom.
- **Code cards:** monospaced YAML with a colored header strip.
  - Giant Swarm CRs: Giant Swarm Blue header, Giant Swarm icon, title "Giant Swarm CR".
  - Kubernetes resources: Kubernetes blue header, Kubernetes logo, title "Kubernetes resource".

## Arrows

Pick one color per flow type. Show every type used in the legend. Default palette:

| Flow | Color | Style |
|---|---|---|
| Write, ingest, request | `#2563eb` | solid |
| Read, query, response | `#16a34a` | solid |
| Alert, error, event | `#ea580c` | solid |
| Configuration, control | `#6b7280` | dashed `7 5` |
| Authentication | `#7c3aed` | solid, thinner |

- **Direction:** arrows point the way data flows. A caller points at what it calls. Configuration points from the source to the consumer.
- **Two-way arrows:** only when data flows both ways.
- **Routing:** horizontal and vertical segments only. Merge parallel arrows into a shared bus line.
- **Crossings:** avoid them. When a crossing is unavoidable, cut a small gap in the lower line with a halo the color of the background.
- **Labels:** 11px italic gray, a few words only, e.g. `direct`, `via proxy`, `every 5m`.
- **Owner colors:** in ownership or tenancy diagrams, color arrows by owner. Default owner palette: `#dc2626`, `#16a34a`, `#2563eb`, `#d97706`, `#7c3aed`.

## Colors

Brand colors come from the Giant Swarm styleguide.

| Use | Color |
|---|---|
| Giant Swarm components | Giant Swarm Blue `#002645` |
| Text on Giant Swarm Blue | `#ffffff`, descriptions `#cfe3f0` |
| Product or platform box | Vivid Blue tint `#ddf0fa`, border `#002645` |
| Container boxes | fill `#f8fafc`, border `#94a3b8` |
| Neutral boxes | fill `#ffffff`, border `#334155` |
| Kubernetes header | `#326ce5` |
| Titles and names | `#0f172a` |
| Labels | `#334155` |
| Descriptions | `#475569` |
| Section labels | `#64748b` |

- **Tints:** mix Vivid Blue `#009fff` into Giant Swarm White `#f0f7f9`. About 8% gives `#ddf0fa`.
- **Component tints:** give each component family a light fill and a matching border, e.g. storage `#fff7ed` / `#c2410c`, controllers `#fef2f2` / `#dc2626`, user interfaces `#fffbeb` / `#d97706`.
- **YAML highlighting:** keys `#8250df`, values `#0a3069`, colons and dashes `#6e7781`, comments `#6e7781` italic. Highlighted values stay bold in their owner color.

## Typography

| Element | Style |
|---|---|
| Title | 30px bold |
| Subtitle | 15px |
| Container labels | 17px bold |
| Component names | 18px bold |
| Descriptions | 13px |
| Section labels | 12px bold, uppercase, letter spacing 1.5px |
| Arrow labels | 11px italic |
| Code | DejaVu Sans Mono 12px, 18px line height |

- **Font:** `Noto Sans, DejaVu Sans, sans-serif`.
- **Centering:** center titles and labels on their box. Section labels stay left-aligned on their column.

## Wording

- **Title:** `<Product>: <View>`, e.g. `Developer Platform: Overview`.
- **Subtitle:** one sentence on what the diagram shows.
- **Names:** follow the glossary. One name per component, everywhere.
- **Spelling:** American English, e.g. "organization".
- **Descriptions:** a short noun phrase, e.g. "ingress controller", "DNS records", "notifications".
- **No invention:** add no component or link the source lacks. Ask when unsure. Write a description for every component. List each description the source lacks in the handoff.

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
- [ ] Names match the glossary.
- [ ] SVG and PNG are committed together.
