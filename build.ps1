# Builds both language versions of the site into docs/.
#
# Run this instead of `quarto render`. A bare `quarto render` has no profile and
# would produce a site with no navbar at all — every navbar/footer key lives in
# _quarto-en.yml / _quarto-pt.yml, because Quarto profiles CONCATENATE arrays
# rather than replacing them, so those keys cannot sit in the shared base.
#
# Layout produced:
#   docs/         dispatcher only - a single index.html that sends the bare root
#                 to /pt/, plus redirect stubs for the pre-/en/ English URLs
#   docs/en/      English
#   docs/pt/      Portuguese
#
# The two versions are siblings, so every in-tree link resolves relatively and a
# visitor stays in whichever version they entered - no JavaScript involved. The
# only page that decides anything is the root dispatcher.
#
# docs/ is wiped and rebuilt each time so that files deleted from the source do
# not linger in the published site. The staging dirs (_site-en, _site-pt) are
# gitignored.

Set-Location $PSScriptRoot

foreach ($d in "_site-en", "_site-pt", "docs") {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction Stop }
}

# Deliberately NOT $ErrorActionPreference = "Stop" around the quarto calls. In
# Windows PowerShell 5.1 that turns anything a native executable writes to stderr
# into a terminating error — so a harmless Quarto warning would abort the build
# even though quarto exited 0. The exit code is the only reliable signal.
Write-Host "==> Rendering English" -ForegroundColor Cyan
quarto render --profile en
if ($LASTEXITCODE -ne 0) { throw "English render failed (exit $LASTEXITCODE)" }

Write-Host "==> Rendering Portuguese" -ForegroundColor Cyan
quarto render --profile pt
if ($LASTEXITCODE -ne 0) { throw "Portuguese render failed (exit $LASTEXITCODE)" }

Write-Host "==> Assembling docs/" -ForegroundColor Cyan

# blog/index-pt.qmd is the Portuguese twin of blog/index.qmd and renders to
# blog/index-pt.html. It cannot declare `output-file: index.html` — two sources
# aiming at one output crashes `quarto preview` (see the note in that file) — so
# it is moved into place here.
if (Test-Path _site-pt\blog\index-pt.html) {
    Move-Item _site-pt\blog\index-pt.html _site-pt\blog\index.html -Force -ErrorAction Stop
    # The name is baked into the generated metadata (search index, sitemap,
    # listings) and into each page's canonical link, so those have to follow the
    # rename or PT search sends people to a 404.
    Get-ChildItem _site-pt -Recurse -Include *.html, *.json, *.xml |
        ForEach-Object {
            $t = [IO.File]::ReadAllText($_.FullName)
            if ($t.Contains("index-pt.html")) {
                [IO.File]::WriteAllText($_.FullName, $t.Replace("index-pt.html", "index.html"))
            }
        }
}
# Defensive: under `preview` (not `render`) Quarto ignores the profile's render
# exclusions, so the wrong language's twin can appear in a tree.
Remove-Item _site-en\blog\index-pt.html -ErrorAction SilentlyContinue

New-Item -ItemType Directory docs | Out-Null
Move-Item _site-en docs\en -ErrorAction Stop
Move-Item _site-pt docs\pt -ErrorAction Stop

# Quarto treats a .qmd excluded from a profile's `render:` list as a *resource*
# and copies the source file into that profile's output — so blog/index.qmd lands
# in the pt tree and blog/index-pt.qmd in the en one. Left in place they end up
# inside docs/, where the next render/preview discovers them as stray inputs whose
# ../assets/ includes no longer resolve from that depth, and the build dies with
# "unable to open file ../assets/html/particles-embed.html". Drop them here: docs/
# is published HTML, no .qmd belongs in it either way.
$strays = Get-ChildItem docs -Recurse -Filter *.qmd -ErrorAction SilentlyContinue
if ($strays) {
    $strays | Remove-Item -Force
    Write-Host "    removed $($strays.Count) stray .qmd from docs/" -ForegroundColor DarkGray
}

# .nojekyll tells GitHub Pages to serve site_libs/ (directories starting with an
# underscore are otherwise dropped). It is listed under resources: so Quarto
# copies it, but only the root copy matters.
if (-not (Test-Path docs\.nojekyll)) { New-Item -ItemType File docs\.nojekyll | Out-Null }

Write-Host "==> Root dispatcher and legacy redirects" -ForegroundColor Cyan

# The bare root is a door, not a page: it always opens onto Portuguese. Stateless
# on purpose - it remembers nothing, because it does not have to. Anyone who wants
# English is already inside /en/, where every link keeps them.
@'
<!DOCTYPE html>
<html lang="pt">
<head>
<meta charset="utf-8">
<title>Raphael Ludwig</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="https://raphaludwig.github.io/pt/">
<meta http-equiv="refresh" content="0; url=pt/">
<script>location.replace("pt/" + location.hash);</script>
</head>
<body><p><a href="pt/">Raphael Ludwig</a> &middot; <a href="en/">English</a></p></body>
</html>
'@ | Set-Content docs\index.html -Encoding utf8

# Legacy. Before /en/ existed the English site WAS the root, and those URLs are
# out in the world. Every English page therefore keeps a stub at its old address
# pointing at the new one. Relative hrefs, not absolute: the site does not have to
# be served from a domain root (see the same note in assets/html/lang-switch.html).
#
# docs/index.html is deliberately not among them - it is the dispatcher, and the
# old English home now lives at /en/. That is the one URL this layout changes.
$stubs = 0
Get-ChildItem docs\en -Recurse -Filter *.html | ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path docs\en).Path.Length + 1).Replace([char]92, '/')
    if ($rel -eq 'index.html') { return }
    $up = '../' * ($rel.Split('/').Count - 1)
    $target = "$up" + "en/$rel"
    $dest = Join-Path docs $rel.Replace('/', [char]92)
    New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="robots" content="noindex">
<link rel="canonical" href="$target">
<meta http-equiv="refresh" content="0; url=$target">
<script>location.replace("$target" + location.hash);</script>
</head>
<body><p>This page moved to <a href="$target">$target</a>.</p></body>
</html>
"@ | Set-Content $dest -Encoding utf8
    $stubs++
}
Write-Host "    $stubs legacy redirect stub(s)" -ForegroundColor DarkGray

# A stub cannot stand in for a PDF - the old /cv/*.pdf links have to resolve to
# actual bytes, so those are copied rather than redirected.
if (Test-Path docs\en\cv) {
    New-Item -ItemType Directory docs\cv -Force | Out-Null
    Copy-Item docs\en\cv\*.pdf docs\cv\ -Force
}

Write-Host "==> Done. docs/ rebuilt (dispatcher at root, en/ and pt/ beside it)." -ForegroundColor Green
