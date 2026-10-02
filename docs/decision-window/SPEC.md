# Decision window: design spec

Status: implemented (Mike-approved design, 2026-10-01).
Mockups: `mockups/*.png` (rendered) and `mockups/*.html` (source). The live
canvas is https://claude.ai/artifact/Krk7kbbFueDi7X2ZAPocye (private to Mike).

The mockups use one real request with six options as the stress case. Content
in them is illustrative; the rules below are what to build.

## Purpose

The window exists so Mike can understand one decision request well enough to
rule on it. Ruling is the goal; asking is how he gets there; everything else is
evidence. Every layout decision follows from that order.

## Information architecture

| Tier | Contents | Place |
|---|---|---|
| 1. Always on screen | Who is asking (project, kind, when); the question in plain words; every ruling choice, each a button that explains itself; a way to ask | Pinned. Never scrolls away, never covered by anything else. |
| 2. Primary reading | The brief: what happened, what is at stake, the explainer's recommendation | Top of the scrolling body |
| 3. On demand | The conversation with the explainer | Continues below the brief |
| 4. Reference | Identifiers (plan, request, assignment, work item); the original request verbatim | Identifiers: pinned footer line when there is room, else an `IDs ▾` menu in the header. Original request: a collapsed section at the end of the body. |

Shrinking drops, it never squeezes: as space runs out, tiers leave from the
bottom up (4, then 3, then 2). Tier 1 always stays whole; only the question
clamps to fewer lines and choice explanations clamp (see Choice density).

Nothing may ever paint over anything else. Every scrolling region clips, and no
computed height may go below zero (the bug that started this redesign).

## Regions, top to bottom

1. **Header** (pinned, full width)
   - Eyebrow line: an accent dot (the request needs Mike), project, kind, raise
     time; at the right, re-summarize (icon button) and, in small windows,
     `IDs ▾`.
     - Project: the product owner from `poForRequest`. When the raiser is not a
       product owner (e.g. `process:tightbeam`), use the summarizer's `project`
       field (below); never show `UNASSIGNED` when a project can be inferred.
     - Kind: `kinds.js` `singular`, upper-cased.
     - Time: `raisedAt`, local, 12-hour (`11:58 AM`; add the date when not today).
   - Headline: the question in plain words (summarizer `question` field; until
     it arrives, the request's `subject`, then raw `question`).
2. **Body** (scrolls, clips)
   - `BRIEF`: the explainer's TL;DR and recommendation.
   - Conversation: Mike's questions and the explainer's answers, in order.
     Conversation choices that are not ruling options (`choices` blocks) render
     as small outlined buttons under the reply that offered them.
   - `ORIGINAL REQUEST` (collapsed by default): raw question, note, subject,
     options as the agent wrote them.
3. **Decide** (pinned; position depends on layout, see Layouts)
   - Label `DECIDE` and a key hint (`↑↓ ⏎ or a number`).
   - One button per ruling choice (`rulingChoices()`: keep the existing filter,
     so effort requests offer only `continue` and `dismiss`). Each button holds:
     - plain label (summarizer `choices[i].label`), bold;
     - consequence, one sentence (summarizer `choices[i].effect`, replaced by
       the explainer's `choice-effects` block when that arrives);
     - the agent's own option word, verbatim, in mono;
     - its number key, in a small keycap at the right.
4. **Ask line** (pinned under the body, in the reading column)
   - Placeholder `Ask about this request…`, keycap `/`.
5. **Footer** (pinned, full width, only when there is room)
   - Identifiers in mono: `plan <name> ↗` (opens the plan/work item),
     `request dr_…`, `assignment asg_…`, `work item wi_…`. Each is a button:
     click copies the full ID (tooltip and a brief "copied" confirmation);
     short forms are fine on screen, the copy is always the full ID.
   - Omit an identifier the request does not have.

## Layouts

Layout thresholds are window sizes in logical pixels and do not scale with
the font scale (Ctrl +/−/0); a larger font scale is absorbed by choice density
and headline clamping, not by switching to a smaller layout. Type sizes below
are at font scale 1 and do scale.

| Layout | When | Arrangement |
|---|---|---|
| Wide | width ≥ 720, height ≥ 360, and every choice fits the decide column at least as compact rows (otherwise Narrow) | Header across the top. Below it two columns: reading column (body + ask line) on the left; decide column on the right, 300–340 px (about 38% of the width), on a slightly tinted panel. Footer across the bottom when height ≥ 480; otherwise `IDs ▾` in the header. |
| Narrow | width < 720 and height ≥ 360 | One column: header, body, ask line, footer. The full choice buttons sit in the body right after the brief. Whenever they are not fully visible (scrolled above or below the viewport), a docked decide strip appears above the ask line: compact buttons (keycap + label, two per row) plus `explain choices ↑`, which scrolls the full buttons into view. |
| Minimum | height < 360, or neither Wide nor Narrow fits (Narrow needs its header, the docked choices, the ask line and about three lines of brief) | Header (question clamped to 3 lines, `IDs ▾`) and a decide strip only: compact buttons, three per row when width allows. Body, ask line and footer are hidden; the strip's hint reads `/ to ask · enlarge for the brief`. `/` shows the ask line above the strip; answers are read by enlarging the window. The window never resizes itself. |

Headline clamps: Wide 3 lines (1 line when height < 560), Narrow 4 lines,
Minimum 3 lines; full text on hover.

### Choice density (decide column)

The decide column always shows every choice without scrolling. It picks the
roomiest density at which all rows fit:

1. Full: label, consequence (wraps), option word.
2. Clamped: label, consequence on one line (elided), option word hidden.
3. Compact: label only, one line.

The full consequence is available on hover and focus in every density.

## Interaction

- Number keys `1`–`n` select a choice from anywhere except while typing in the
  ask line. Selecting arms it: the row gets the focus outline and the hint
  becomes `⏎ to record "<label>"`. Enter (or the same number again) records it.
  Clicking a button records it directly, as today.
- In the decide region, ↑↓ move between choices and Enter records.
- `/` focuses the ask line; Esc leaves it. Tab cycles body → decide → ask.
- Body scrolling keys stay as they are (arrows, Ctrl+hjkl, PageUp/PageDown,
  Ctrl+u/d, the tuned keyboard motion).
- Ctrl+, opens settings; Ctrl + / − / 0 change font scale.
- An explainer `rule` proposal arms that choice and marks it `proposed in
  conversation`; Mike still confirms with Enter or a click.
- Recording: the chosen row shows `Recording…`; other rows are disabled. No
  full-window overlay.
- Handled (recorded here or elsewhere): the decide region is replaced by the
  outcome (status, actor, determination, as `handled.sh` reports it). The body
  and identifiers stay readable.
- Errors (bridge missing, session lost, recording failed) show as one line in
  the region they affect, never as an overlay.

## Typography

Three faces, each with one job. The face says who is talking.

| Face | Used for |
|---|---|
| Newsreader (serif) | The headline question; Mike's own words (his questions in the conversation, the ask line), italic |
| IBM Plex Sans | Everything explanatory and interactive: brief, answers, choice labels and consequences |
| IBM Plex Mono | Verbatim system text: option words, identifiers, keycaps, small-caps section labels |

Bundle the fonts with the plugin (`fonts/`, both under the SIL OFL, licence
files included) and load them with `FontLoader` in the window host. They apply
to decision windows only; the bar and menus keep the theme font.

Scale at font scale 1 (Mike, 2026-10-01: everything but the headline and the
footer two sizes up from the mockups; the ask line twice its mockup size):

| Role | Face | Size / line height | Weight |
|---|---|---|---|
| Headline | Newsreader | 27 / 1.25 (21 when clamped to 1 line or Minimum, 22 Narrow) | 400 |
| Section label (`BRIEF`, `DECIDE`), key hints | Plex Mono | 13, letter-spacing 0.12em, upper case | 500 |
| Eyebrow | Plex Mono | 13, letter-spacing 0.12em, upper case | 500 (project in ink, the rest secondary) |
| Body / answers | Plex Sans | 17 / 1.6, measure ≤ 70 characters | 400 |
| Mike's words | Newsreader italic | 21 in the body, 34 in the ask line | 400 |
| Choice label | Plex Sans | 17 / 1.35 (16 compact) | 600 |
| Choice consequence | Plex Sans | 15 / 1.45 | 400 |
| Option word | Plex Mono | 13 | 400 |
| Footer identifiers | Plex Mono | 11 | 400 |
| Keycap | Plex Mono | 14, in a 24 px rounded square | 400 |

The window opens at 960 × 720 (4:3), times the font scale.

## Color

All colors come from the Omarchy theme so dark themes work; none are
hard-coded. Mixes are `mixColor(background, foreground, t)`.

| Role | Value | Mockup (current light theme) |
|---|---|---|
| Ground | `Color.background` | #F6F3EA |
| Ink | `Color.foreground` | #1C1A16 |
| Secondary text | mix 0.65 (must reach 4.5:1 on ground) | #5F5B52 |
| Faint text (option words, ID labels) | mix 0.5 | #8A857A |
| Decide panel | mix 0.05 | #EDE9DD |
| Hairlines | mix 0.14 | #DCD6C8 |
| Keycap border | mix 0.3 | #BDB6A6 |
| Accent | `Color.urgent` | #C2362D |

Accent appears in exactly two places: the needs-you dot and Mike's own words.
The armed or focused choice gets a 1 px ink outline on a ground-colored fill.
No choice looks recommended by styling.

## Content the window needs from the agents

Summarizer (`DecisionWindow.summaryPrompt`, fast, no tools) returns one JSON
object:

```json
{"project": "1-3 words", "question": "the decision as a plain question, at most 25 words",
 "parent": "2-6 plain words", "notes": "one short line",
 "choices": [{"label": "2-7 plain words", "effect": "one sentence, what choosing it causes"}]}
```

`choices` has exactly one entry per input option, in order, as today; a
missing or malformed entry falls back to the raw option word.

Explainer (`DecisionChat.briefing`): keep looking things up first. Its answer
shape becomes: a `header-summary` block (unchanged), `## TL;DR`,
`## Recommendation`, and a fenced `choice-effects` block with one
`<number>. <one sentence>` line per option. Drop the `What the options mean`
section: the choice buttons carry it now. `choices` and `rule` blocks keep
their current meaning.

## Unchanged

Topology and transport, the window host and its IPC, one window per request
and presenting it again (bridge/compositor.js), the settings window, theme
reloading, keyboard motion tuning, delegated recording rules, the message
script, notifications and the bar menu.
