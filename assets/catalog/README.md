# Catalog photos

Drop your photos here. This one folder feeds **all four surfaces** — the
PanelVault iPhone app, the Worker app, the Warehouse app, and PanelVault Cloud
in the browser. There is no second copy to keep in step: the website serves
these files directly, and the three Xcode projects reference this folder, so a
photo added here ships everywhere the next time each app is built.

```
assets/catalog/
  manufacturers/   one logo per brand      abb.png
  components/      one photo per part      abb-s201-1p.jpg
  index.json       generated — do not edit by hand
```

## Adding photos

1. Copy the files into `manufacturers/` or `components/`.
2. Run the matcher from the repo root:

```bash
python3 tools/sync_catalog_images.py
```

It prints what matched, what did not, and rewrites `index.json`. Nothing shows
up in the apps or the website until `index.json` lists it.

To have the tool rename loose filenames to their canonical catalog id:

```bash
python3 tools/sync_catalog_images.py --rename
```

## Naming

Exact ids always win. `abb-s201-1p.jpg` is matched to the part with that id, no
guessing involved. Everything else is matched by normalizing the filename and
comparing it against the manufacturer, model, and poles of every catalog part,
so these all resolve too:

| Filename | Resolves to |
| --- | --- |
| `abb-s201-1p.jpg` | `abb-s201-1p` (exact id) |
| `ABB S201 1P.jpg` | `abb-s201-1p` |
| `ABB S201.png` | `abb-s201-1p` — only if one S201 part exists |
| `Acti9 iC60N.jpg` | `schneider-ic60n` |
| `ABB.png` | the ABB manufacturer |
| `ABB logo.png` | the ABB manufacturer (`logo` is stripped) |
| `Mean Well.png` | the `mean-well` manufacturer |

A name that matches more than one part is reported as ambiguous rather than
guessed at, with the candidate ids listed — rename it to the id you meant.

## Formats

`.png`, `.jpg`, `.jpeg`, `.heic`, `.webp`. PNG with transparency is the right
choice for logos: the apps render them in a bubble that assumes a cut-out mark,
and the website drops them on both light and dark backgrounds.

Keep the long side at or below **1400px**. These files ship inside the app
binary, so 199 full-resolution camera originals would add hundreds of megabytes
to every install.

## What the apps do with them

A photo here is a *default*, never a lock. The precedence at every render site
is the same:

1. a photo the user took or picked on the device, then
2. the photo in this folder, then
3. the SF Symbol for the part's category (components) or the coloured initials
   (manufacturers).

So a worker photographing the actual part on the bench still overrides the
catalog photo on their device, exactly as before.
