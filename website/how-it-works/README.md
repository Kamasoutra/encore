# How it works

The site's fourth page: [Floorplan](https://github.com/haydenschmitty/floorplan)'s map of the code (MIT, Hayden Smith; license kept here and published with the page), in the site's colours and in two languages. `website/build.py` builds it through `build.mjs`.

- `map/architecture.json`, `map/descriptions/`: what the map says, in French. Edit these, never `floorplan/` at the root, which `refresh.sh` overwrites and Git ignores.
- `map/encore-map.html`: Floorplan's export, generated.
- `cases.mjs`: the situations in the panel, FR and EN. `since` shows the "New" tag while it equals the site's version.
- `en.mjs`: the English text of the map.
- `skin.css`, `build.mjs`: the look, and the patches to Floorplan's viewer. A patch that no longer applies stops the build.
- `split-column.js`: on the overview, a last column much taller than the others is dealt into two close staggered columns. ELK lays the pairs out with their ports where the cards will be, so it draws the links itself.

## At every release, once the code is final

1. Bump the version, `LATEST` in `website/features.py` included.
2. Describe what changed: new files in `map/architecture.json` and `map/descriptions/`, their English in `en.mjs`; a case in `cases.mjs` for each new feature touching your data. Reread the cases: each sentence is a claim about the code.
3. Run `website/how-it-works/refresh.sh`. It ends with `check.mjs`, which the Release workflow runs too: a tag whose map is stale does not ship.
4. Open both pages. Check every case plays to its end, no text is cut at the overview, part and file levels, and nothing scrolls on a laptop screen.
5. Commit, tag. The GitHub links point to the tag, so they keep matching this map.
