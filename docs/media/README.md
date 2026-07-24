# Media for the README

| File | What it shows |
| --- | --- |
| `banner.png` | The banner the README opens on — the live strip beside the notch and the whole panel dropped below it, on a Mac. 2484 × 1460, which is 2x for a Retina display. |

Keep the banner at 2x: the README renders it at `width="100%"`, and GitHub serves
it at up to twice the column width on a Retina screen. A 1x banner is visibly
soft on every Mac the app runs on.

When the panel gains or loses a row, the banner is showing the old app — recapture
it rather than leaving it, because it is the first and often the only thing anyone
looks at.

## If you add screenshots back

Real captures are worth having, and the one thing that ruins them is scale. A
Mac captures a Retina screen at **two image pixels per screen point**, so a
300-point panel should arrive as a **600-pixel-wide** PNG and be displayed at
300. A 1x capture shown at its own width is stretched on every Retina screen,
and no amount of resizing afterwards recovers detail that was never captured.

1. Get the island into the state you want — hover it for the panel, or start
   some music for the strip.
2. Press **⇧⌘4**, then **Space**, then click the island's window. macOS captures
   just that window, with its shadow, at full resolution. (Or **⇧⌘4** and drag a
   tight box around it.)
3. Save it here, and reference it from the README with an explicit pixel
   `width=`.
4. Run `./scripts/fit-media.sh`.

That last step reads each image's real pixel width and sets the README to
display it at exactly half, so a proper 2x capture shows at full size and
nothing is ever stretched. It skips images the README references by percentage
rather than by pixels, which is why it leaves the banner alone.

## Optional: a motion clip

A short clip of the notch opening makes the README come alive. Record with
**⇧⌘5**, convert the `.mov` to an optimised `.gif`, save it here as `demo.gif`,
and add an `<img src="docs/media/demo.gif" …>` below the banner.
