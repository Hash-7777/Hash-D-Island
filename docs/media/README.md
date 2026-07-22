# Media for the README

Screenshots the README's **See it in action** section renders. Replace a file
and the README picks it up automatically — no README edits needed.

| File | What it shows | In the README |
| --- | --- | --- |
| `hero.png` | The panel open below the notch — Now Playing, AI tokens, internet, temperatures, timer. | Main shot. |
| `live.png` | The live strip beside the notch — album art + title + audio bars. | Secondary shot. |

## Swapping in a bigger shot

The current shots are captured tight (the panel is ~300px wide) and render at
their native size to stay crisp. For a larger, higher-resolution version,
recapture on a Retina display (screenshots come out at 2×) and bump the `width`
in the README's `<img>` tag to match.

## Optional: a motion clip

A short GIF of hovering the notch to open the panel makes the README pop. Record
with `⇧⌘5`, convert the `.mov` to an optimized `.gif` (e.g. with Gifski), save it
here as `demo.gif`, and add one more `<img src="docs/media/demo.gif" …>` under
the shots above.
