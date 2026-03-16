# claude-statusline

A configurable status line for [Claude Code](https://claude.ai/code) sessions.

Reads Claude Code's session JSON from stdin and renders a styled, multi-segment
status line in your terminal. Fully customizable via a TOML config file — colors,
layout, thresholds, Nerd Font icons, and more.

## Install

```sh
# Build and install to ~/.local/bin
make install
```

Wire it into Claude Code in `~/.claude/settings.json`:

```json
{
  "statusLine": { "type": "command", "command": "claude-statusline" }
}
```

## Quick Start

Works out of the box with sensible defaults — no config file needed. The default
output looks like:

```
[Opus 4.6 (1M context)] | ##########------------------------------ (27k/1M tokens) 27% | $0.25 | ⏱️ 4m 5s | 🟢
```

To customize, create `~/.config/claude-statusline.toml`:

```toml
[model]
style = "bold cyan"
symbol = "󰚩 "        # Nerd Font robot icon

[cost]
warn_threshold = 2.0
warn_style = "yellow"
critical_threshold = 5.0
critical_style = "bold red"

[context_bar]
width = 20
fill_char = "█"
empty_char = "░"
warn_threshold = 40.0
warn_style = "yellow"
critical_threshold = 80.0
critical_style = "bold red"
```

## Configuration

Config file discovery order:

1. `--config <path>` flag
2. `~/.config/claude-statusline.toml`
3. Built-in defaults

### Global Settings

```toml
# Separator between segments (also the line-wrap breakpoint)
separator = " | "

# Terminal padding reserved on the right
padding = 5

# Layout — each entry is one line, segments separated by `|` auto-wrap
# Available tokens: $model $context_bar $context_tokens $context_pct $cost $duration $status
lines = ["$model | $context_bar $context_tokens $context_pct | $cost | $duration | $status"]
```

### Modules

Every module supports these fields:

| Field       | Type   | Description                                             |
|-------------|--------|---------------------------------------------------------|
| `disabled`  | bool   | Hide this module entirely                               |
| `style`     | string | ANSI style (see [Styles](#styles))                      |
| `symbol`    | string | Prefix prepended to the value (supports Nerd Font glyphs) |
| `format`    | string | Format string with `{value}` and `{symbol}` placeholders |
| `min_width` | int    | Only show when terminal is at least this wide           |

#### `[model]` — Model Name

Displays the active Claude model name.

| Field       | Default       | Description                        |
|-------------|---------------|------------------------------------|
| `style`     | `"cyan"`      | ANSI style                         |
| `format`    | `"[{value}]"` | Wraps name in brackets by default  |
| `min_width` | `80`          | Hidden on narrow terminals         |

```toml
[model]
style = "bold fg:#7aa2f7"
symbol = "󰚩 "              # nf-md-robot
format = "{symbol}{value}"   # drop the brackets
min_width = 0                # always show
```

#### `[context_bar]` — Context Window Progress Bar

Visual bar showing context window usage. Supports threshold-based color changes.

| Field                | Default    | Description                                  |
|----------------------|------------|----------------------------------------------|
| `style`              | `"green"`  | Base color                                   |
| `width`              | `0` (auto) | Fixed char width, or 0 for auto (termWidth/3, min 40) |
| `fill_char`          | `"#"`      | Character for the filled portion             |
| `empty_char`         | `"-"`      | Character for the empty portion              |
| `warn_threshold`     | `40.0`     | % at which style switches to `warn_style`    |
| `warn_style`         | `"yellow"` | Style at warning level                       |
| `critical_threshold` | `90.0`     | % at which style switches to `critical_style`|
| `critical_style`     | `"red"`    | Style at critical level                      |

```toml
[context_bar]
width = 20
fill_char = "█"
empty_char = "░"
symbol = " "               # nf-oct-cpu
style = "fg:#7dcfff"
warn_threshold = 40.0
warn_style = "fg:#e0af68"
critical_threshold = 70.0
critical_style = "bold fg:#f7768e"
```

#### `[context_tokens]` — Token Count

Displays current/total token usage like `(27k/1M tokens)`.

| Field    | Default       | Description           |
|----------|---------------|-----------------------|
| `format` | `"({value})"` | Wrapped in parentheses by default |

```toml
[context_tokens]
style = "dim"
format = "[{value}]"   # use brackets instead of parens
```

#### `[context_pct]` — Context Percentage

Displays context usage percentage like `27%`.

| Field    | Default      | Description         |
|----------|--------------|---------------------|
| `format` | `"{value}%"` | Appends % by default |

```toml
[context_pct]
style = "bold"
```

#### `[cost]` — Session Cost

Displays total session cost in USD. Supports threshold-based color changes.

| Field                | Default    | Description                               |
|----------------------|------------|-------------------------------------------|
| `style`              | `"yellow"` | Base color                                |
| `warn_threshold`     | `0`        | USD at which style switches (0 = off)     |
| `warn_style`         | —          | Style at warning level                    |
| `critical_threshold` | `0`        | USD at which style switches (0 = off)     |
| `critical_style`     | —          | Style at critical level                   |

```toml
[cost]
symbol = "💰 "
style = "green"
warn_threshold = 2.0
warn_style = "yellow"
critical_threshold = 5.0
critical_style = "bold red"
```

#### `[duration]` — Session Duration

Displays total session wall-clock time.

| Field    | Default  | Description  |
|----------|----------|--------------|
| `symbol` | `"⏱️ "` | Timer emoji  |

```toml
[duration]
symbol = " "    # nf-fa-clock_o
style = "dim"
```

#### `[status]` — API Health

Displays Claude API operational status as an emoji indicator (`🟢`, `🟡 degraded`, `🔴 error`).

```toml
[status]
disabled = true   # hide if you don't care about API status
```

### Styles

Style strings follow Starship-compatible syntax. Combine any of the following
separated by spaces:

**Modifiers:** `bold`, `italic`, `underline`, `dimmed`

**Named foreground colors:** `black`, `red`, `green`, `yellow`, `blue`, `purple`,
`cyan`, `white` — and their `bright_*` variants (`bright_red`, `bright_cyan`, etc.)

**Hex foreground:** `fg:#RRGGBB`, `fg:#RGB`, or bare `#RRGGBB` / `#RGB`

**Named/hex background:** `bg:red`, `bg:#1a1a2e`

Examples:

```
"bold"
"red"
"bold green"
"fg:#c792ea"
"bold fg:#ff5370 bg:#1a1a2e"
"bright_cyan"
"dim italic"
```

### Nerd Fonts

If you have a [Nerd Font](https://www.nerdfonts.com/) installed in your terminal,
you can use glyph icons as `symbol` values:

```toml
[model]
symbol = "󰚩 "    # nf-md-robot

[context_bar]
symbol = " "    # nf-oct-cpu

[cost]
symbol = " "    # nf-fa-dollar

[duration]
symbol = " "    # nf-fa-clock_o
```

Browse icons at [nerdfonts.com/cheat-sheet](https://www.nerdfonts.com/cheat-sheet).

## Examples

### 1. Minimal

One clean row. Model, cost, and a compact context bar.

```toml
lines = ["$model | $cost | $context_bar $context_pct"]

[model]
min_width = 0

[cost]
warn_threshold = 2.0
warn_style = "yellow"
critical_threshold = 5.0
critical_style = "bold red"

[context_bar]
width = 15

[context_tokens]
disabled = true
```

### 2. Two-Row Dashboard

Session info on top, context details below.

```toml
lines = [
  "$model | $cost | $duration | $status",
  "$context_bar $context_tokens $context_pct",
]

[model]
style = "bold cyan"
min_width = 0

[cost]
style = "green"
warn_threshold = 2.0
warn_style = "yellow"
critical_threshold = 5.0
critical_style = "bold red"

[context_bar]
width = 30
fill_char = "█"
empty_char = "░"
```

### 3. Cost Guardian

Focused on spending awareness. No context bar clutter.

```toml
lines = ["$model | $cost | $duration | $status"]

[model]
style = "bold"
format = "{value}"
min_width = 0

[cost]
symbol = "💰 "
style = "green"
warn_threshold = 1.0
warn_style = "bold yellow"
critical_threshold = 3.0
critical_style = "bold red"

[context_bar]
disabled = true

[context_tokens]
disabled = true

[context_pct]
disabled = true
```

### 4. Tokyo Night

Hex colors from the Tokyo Night palette with Nerd Font icons.

```toml
lines = [
  "$model | $cost | $duration | $status",
  "$context_bar $context_tokens $context_pct",
]

[model]
symbol = "󰚩 "
style = "bold fg:#7aa2f7"
format = "{symbol}{value}"
min_width = 0

[cost]
symbol = " "
style = "fg:#a9b1d6"
warn_threshold = 2.0
warn_style = "fg:#e0af68"
critical_threshold = 5.0
critical_style = "bold fg:#f7768e"

[duration]
symbol = " "
style = "fg:#565f89"

[context_bar]
symbol = " "
width = 20
fill_char = "█"
empty_char = "░"
style = "fg:#7dcfff"
warn_threshold = 40.0
warn_style = "fg:#e0af68"
critical_threshold = 70.0
critical_style = "bold fg:#f7768e"

[context_tokens]
style = "fg:#565f89"

[context_pct]
style = "fg:#565f89"
```

### 5. Compact Percentage Only

Absolute minimum — just the percentage and cost.

```toml
separator = "  "
lines = ["$context_pct  $cost  $status"]

[model]
disabled = true

[context_bar]
disabled = true

[context_tokens]
disabled = true

[duration]
disabled = true
```

## Performance

`claude-statusline` runs on every prompt render, so it's built to be fast.
The full pipeline — config loading + JSON decoding + rendering + writing —
completes in **~19 µs (0.019 ms)** with only **78 allocs**. Rendering alone (pre-parsed
config and input) takes **~5 µs**.

```
goos: linux  goarch: amd64  cpu: i7-1165G7 @ 2.80GHz

Full pipeline (config load + JSON decode + render + write):
  BenchmarkRunWith                 60592   18741 ns/op    5827 B/op   78 allocs/op

Render pipeline (pre-parsed input):
  BenchmarkEndToEnd               263430    4953 ns/op    2064 B/op   43 allocs/op

Internals:
  BenchmarkRenderModules          549267    2306 ns/op    1144 B/op   25 allocs/op
  BenchmarkRenderSegment         2375802     503 ns/op     383 B/op    4 allocs/op
  BenchmarkDisplayLen            2244877     539 ns/op       0 B/op    0 allocs/op
  BenchmarkApplyFormat          12019099      92 ns/op      32 B/op    2 allocs/op

Packages:
  BenchmarkLines (layout)        5271928     226 ns/op     416 B/op    6 allocs/op
  BenchmarkParse (style)         2162178     520 ns/op     245 B/op   10 allocs/op
  BenchmarkSprint (style)       37222816      35 ns/op      64 B/op    1 allocs/op
  BenchmarkWidth (terminal)      7353873     154 ns/op       0 B/op    0 allocs/op
  BenchmarkCost (format)         6420810     182 ns/op       5 B/op    1 allocs/op
  BenchmarkDuration (format)    38799873      31 ns/op       5 B/op    1 allocs/op
  BenchmarkSI (format)          53038720      22 ns/op       3 B/op    1 allocs/op
```

Run benchmarks yourself:

```sh
make bench
```

## Building

```sh
make build          # Build for current OS/arch
make build-all      # Build for all supported platforms
make test           # Run test suite
make lint-all       # Run all linters
make install        # Build and install to ~/.local/bin
```

## License

MIT
