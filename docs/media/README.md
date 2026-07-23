# Media for the README

Screenshots the README's **See it in action** section renders.

| File | What it shows |
| --- | --- |
| `hero.png` | The panel open below the notch — Now Playing, AI tokens, internet, temperatures, timer. |
| `live.png` | The live strip beside the notch — album art, title, audio bars. |

## Capture them at 2x, or they will look soft

A Mac captures a Retina screen at **two image pixels per screen point**, so a
300-point panel should arrive as a **600-pixel-wide** PNG. Displaying that at
300 gives one image pixel per screen pixel, which is what makes it crisp.

The original shots were about 300 pixels wide — a 1x capture — and the README
asked for them at 300 and 360 wide. Stretching a 1x image on a Retina screen is
exactly what makes a screenshot look pixelated, and no amount of resizing after
the fact recovers detail that was never captured.

**To recapture:**

1. Get the island into the state you want — hover it for the panel, or start
   some music for the strip.
2. Press **⇧⌘4**, then **Space**, then click the island's window. macOS captures
   just that window, with its shadow, at full Retina resolution.
   (Or press **⇧⌘4** and drag a tight box around it.)
3. Save the result over `hero.png` or `live.png` here.
4. Run `./scripts/fit-media.sh`.

That last step reads each image's real pixel width and sets the README to
display it at exactly half — so a proper 2x capture shows at full size and stays
sharp, and nothing is ever stretched again. The script warns you if an image
still looks like a 1x capture.

## Optional: a motion clip

A short clip of the notch opening makes the README come alive. Record with
**⇧⌘5**, convert the `.mov` to an optimised `.gif`, save it here as `demo.gif`,
and add one more `<img src="docs/media/demo.gif" …>` beneath the shots.
