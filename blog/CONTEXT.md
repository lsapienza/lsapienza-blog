# Blog graphics

Conventions for every ggplot2 chart published on the blog, implemented in `R/theme_blog.R`
and applied via `theme_blog()`, `pal_blog()`, `accent_blog()`, `scale_color_blog()`,
`scale_fill_blog()`, `scale_x_date_blog()`, `caption_blog()`.

## Language

**Tier**:
One of the three named slices of the green-slate palette (`pal_blog(tier = ...)`):
`main` (1-2 series, close tones), `contrast` (2-3 series, maximally distinct within the
green-slate family), `extended` (3+ series, full 5-tone ramp).
_Avoid_: "palette" alone (ambiguous between a tier and the whole green-slate family).

**Accent**:
A highlight hue reserved for elements *outside* the green-slate family —
bars, saldo/balance series, a prior-vs-posterior reference line, anything meant to read as
"not one of the main series." Not a tier. Chosen via `accent_blog(tone = ...)`, one of six
tones: `cool` (plum/wine, `#7a3b4a`, default), `warm` (terracotta, `#b5654a`), `gold`
(mustard, `#9c7a3c`), `petrol` (petrol blue, `#3f6b7a`), `earth` (ochre/brown, `#7a5233`),
`flower` (light violet, `#9b7cb8`). Pick a second tone deliberately when a chart needs two
accents at once — e.g. `cool` for an observed series and `gold` for its underlying
fundamento/decomposition — favoring tones far apart in hue so they don't collide (`cool` and
`warm` are close in hue and read as similar unless only one is in use).
_Avoid_: "contrast" (that name is taken by the tier above; accent is a separate concept).

**Green-slate family**:
The five anchor tones every tier is built from — `slate_darkest` (`#2f3e46`), `slate_dark`
(`#3f5f56`), `slate_mid` (`#52796f`), `sage_light` (`#84a98c`), `sage_pale` (`#cad2c5`).
Sourced from the site's own palette (`assets/css/theme.scss` — `--pal-text`, `--pal-accent`).
