# Docker rebuild — serve the Perl site again (2026-11-17)

## Intent and why

`docker build .` + `docker compose up` must produce a container that actually serves the
DNDGenerator site again. Today the app answers HTTP 500 on every page, and the build only
"works" because stale layer cache hides it. The base image is the wrong tool: the app is
Perl CGI, never PHP.

## Current state (measured on this machine, 2026-11-17)

| Check | Result |
|---|---|
| `FROM php` today | `php:8.5-cli`, Debian 13.7, **0 apache packages** — Apache only exists because `libapache2-mod-perl2` drags it in |
| Built container, `GET /generator/` | 500 — `Can't locate CGI.pm in @INC` (Debian split `CGI` out of the `perl` package) |
| Legacy `--no-cache` build | "succeeds" while `cpan install Games::Dice::Roll20` fails with `Could not expand` and is **skipped silently** (cpan exit 0) |
| Legacy image size | 940 MB – 1.1 GB |
| `use lib` / `INCLUDE_PATH` | relative (`lib/`, `Templates/`) — the app must be run from its own directory |
| Test suite | 40–42 of 44 files green, varies by run; the suite cannot even finish as documented |
| `worldmap`, `regionmap` | 500 — `use City ...` and `City.pm` does not exist in this repo **or** in upstream `CityGenerator/CityGenerator` |
| Same seed, same call, 10 runs | `EventGenerator::create({seed=>12})` + `select_base` returned 6 different bases: celebration, disaster, festival, hunt, raid, war |

Spike on `debian:trixie-slim` (throwaway, `/tmp/spike`, no repo changes): 17 of 19 generators
return 200, 255 MB image, 0.13–0.45 s per page, gzip 51 KB page → 10 KB.

## Goals

- Clean-cache build (`docker build --no-cache .`) succeeds, and success means the site answers.
- One dependency list, no silent skips: every dependency installed by a step that fails loudly.
- Tests run as part of the build, green and repeatable; test-only and build-only tooling kept out of
  the runtime image.
- Every link in the site's own "Generators" menu verified working by the build.
- Serve as fast as this CGI design allows: compression, cache headers, no wasted runtime.
- Same public contract: `http://host/generator/<script>`, `DirectoryIndex citygenerator`.

## Non-goals

- No PHP. No PHP 7 → 8 upgrade — there is no PHP code here.
- No rewrite to PSGI/Plack or persistent handlers.
- No new generators, no template or styling changes.
- `worldmap` and `regionmap` stay as they are (documented as not working). The site's own nav does
  not link them: the world map is drawn in the browser from JSON (`Templates/worldgenerator_content.tmpl`
  + `js/WorldMap.js`). Future work.

## Anti-goals

- A build that passes while a dependency is missing (exactly today's failure mode).
- Shipping `gcc`, `make`, `cpanminus`, or test fixtures in the runtime image.
- Unpinned `:latest` base that silently changes under us again.

## Constraints

- Scripts keep `#!/usr/bin/perl -wT` (taint mode) and relative `lib/` + `Templates/` paths, so
  the app stays in one directory executed by `mod_cgid` (which chdirs to the script directory).
- Perl from Debian (`/usr/bin/perl`), so CPAN modules land in the same `@INC` the shebang uses.
  `perl:*` images are ruled out: their from-source perl at `/usr/local` is a *second* perl that
  `mod_perl`/`/usr/bin/perl` never sees.
- Apache 2.4 on Debian 13: the app's `.htaccess` needs `AllowOverride All` to be read at all —
  without it Apache serves the scripts as plain text (verified: 200 + file size, no CGI).

## Approaches

**A. Keep `FROM php:8.5`, add the missing Debian perl packages.**
Smallest diff. Trades: ~200 MB of unused PHP interpreter, and the base keeps drifting under us
(the current breakage is exactly that drift). Rejected — it preserves the misdiagnosis.

**B. Debian + Apache + system Perl, PHP deleted. ← chosen** (you delegated the pick)
`debian:trixie-slim` + `apache2`; runtime deps from Debian packages; the handful of CPAN-only
modules from `cpanm`. Build tools installed in the build and gone from the final layer.
Trades: a rewritten Dockerfile, and a dependency split across two mechanisms (apt + cpanfile).

**C. Drop Apache too — PSGI/fcgiwrap.**
Leanest runtime. Trades: rewrites `.htaccess`/URL wiring and every script's request handling for
no user-visible gain. Rejected.

## Decisions (mine, since you said "you decide")

1. **Base:** `debian:trixie-slim` pinned to a digest, tag `trixie-slim` in a comment. Perl 5.40,
   Apache 2.4.71.
2. **Runtime deps (apt):** `apache2`, `libcgi-pm-perl`, `libxml-simple-perl`, **`libxml-parser-perl`**
   (XML::Simple needs a parser and `--no-install-recommends` does not pull one — verified failure:
   `XMLin() requires either XML::SAX or XML::Parser`), `libtemplate-perl`, `liblingua-en-inflect-perl`,
   `libnumber-format-perl`, `libtimedate-perl`, `libtime-parsedate-perl`, `libclone-perl`,
   `libjson-perl`, `libswitch-perl` (`namegenerator` uses `Switch`).
3. **CPAN-only deps (`cpanm --notest`):** `Lingua::EN::Numbers`, `Lingua::EN::Titlecase`,
   `Lingua::EN::Conjugate`, `Lingua::EN::Gender`, `Lingua::Conjunction`,
   `Template::Plugin::Lingua::EN::Inflect`, `Lingua::EN::Inflect::Number` — no Debian packages
   exist for these (checked against trixie). Listed in a new `cpanfile` so `composer`-style
   `cpanm --installdeps .` is the single source of truth.
4. **Delete `use Games::Dice::Roll20;`** from `lib/GenericGenerator.pm`. The distribution is off
   CPAN (backpan only), so `cpan install` skipped it and the build lied; nothing uses the module —
   the only references are two commented-out lines, and dice are rolled by the local `d()` sub.
   `cpanm` does the opposite of `cpan`: it fails loudly, so a stale name can't hide again.
5. **Drop deps the README claims but the code never imports:** `List::MoreUtils`,
   `Email::Date::Format`, `Test::Harness`.
6. **mod_perl:** the app is plain CGI (`SetHandler cgi-script`), so `mod_perl` is unused. Keep the
   package only if removing it turns out to change image size materially; measure, don't guess.
7. **Apache config:** a small `docker/apache.conf` copied to `conf-available` + `a2enconf`, holding
   `AllowOverride All` / `Require all granted` for `/var/www/`, `ServerName`, and
   `RedirectMatch ^/$ /generator/`. No `sed -i` on `apache2.conf`. Modules: `cgid rewrite deflate
   expires headers`. Static `css/js/img/fonts` get `Expires`/`Cache-Control`.
8. **`.htaccess` modernised** from Apache 2.2 `Order allow,deny` / `Satisfy All` to
   `Require all granted` (2.4-native; `mod_access_compat` is deprecated).
9. **Speed:** `mod_deflate` + cache headers are the cheap wins (measured 51 KB → 10 KB on a city
   page). The ~0.13–0.45 s per page is Perl starting per CGI request; going below ~100 ms means
   persistent handlers, which is a non-goal here. `mpm_event` stays as Debian configures it.
10. **Build layout:** one stage. `gcc`/`libc6-dev` are not needed at all (the CPAN modules are pure
    Perl); only `make` is (Module::Build/MakeMaker dists). Build deps are purged with
    `apt-get purge --auto-remove` inside the same `RUN` that installs them, so the final layer is
    clean without a multi-stage file. Measured 255 MB (legacy: 940 MB–1.1 GB).
11. **`docker-compose.yaml`:** keep port 80 mapping, add `restart: unless-stopped`, drop the retired
    `version:` key.
12. **Docs:** README's CPAN one-liner replaced by "the deps live in `cpanfile` +
    `Dockerfile`" and the corrected run instructions.
13. **Out of scope here:** `.github/workflows/docker.yaml` still uses retired actions
    (`checkout@v2`, `build-push-action@v2`, `::set-output`). It only publishes releases, not the
    build; separate change unless you want it in the same pass.

## What gates the build (you chose: fix the tests to match the code)

All three, in this order, each one able to fail the build:

1. **Compile under taint:** `perl -Tc` for every entrypoint script and every `lib/*.pm`. This is
   what would have caught the original breakage (missing `CGI.pm`, missing XML parser, dead
   `Games::Dice::Roll20` import) at build time instead of at first request.
2. **Test suite:** `prove` over `tests/*.pm`, green and deterministic.
3. **Smoke check:** fetch `/generator/` and the 17 scripts the site links, fail on anything that is
   not HTTP 200 with real generated output. Kept as a small repo script so you can run it against a
   running container too.

### Test work, and why exact values are impossible

The suite is red on any modern Perl, and it is not a porting bug:

| File | Failing today | Why |
|---|---|---|
| `tests/TestMagicItemFormatter.pm` | aborts the whole `prove` run | no `#!` line, so prove cannot choose a handler: `There is a tie between ...Executable and ...Perl` |
| `tests/TestFlagGenerator.pm` | 2 asserts (`diagonal`→`diagquads`, `quad`/`sw`→`slash`/undef) | hard-coded outcomes of `srand`-seeded rolls |
| `tests/TestWorldFormatter.pm` | 1 assert, sky summary | same |
| `tests/TestCritterFormatter.pm` | 1 assert, description regex | regex assumes one wording; the template + `Lingua::EN::Inflect` produce variants |
| `tests/TestEventGenerator.pm` | 2 asserts, flaky (`festival`→`war`→`trial`) | same, and varies run to run |

**Scope correction, measured during implementation:** the four flaky files in that table became
**eight** changes. After those four were fixed, 5 of 30 full-suite runs still failed —
`tests/TestGenericGenerator.pm:279`, `tests/TestBondGenerator.pm:28`,
`tests/TestMapJSONFormatter.pm:25`, `tests/TestCityscapeFormatter.pm:69` — all of them the same
hash-order class, each showing up as a rare single-run failure rather than a standing red assert.
Those four files changed on the same principle, and the acceptance bar moved from 10 consecutive
green runs to 30, because ten green runs were reached while the suite still failed 5 of 30.

`srand $seed` in `GenericGenerator::set_seed` fixes the RNG *sequence*, but the number of `rand()`
calls consumed before a pick depends on the order Perl iterates the hashes `XML::Simple` built from
`xml/*.xml`, and Perl randomizes hash order per process. That is the 6 outcomes for one seed.
**So no fixed expected value can be re-recorded and stay green.** The updated tests will assert what
the code actually guarantees instead:

- a generated base/division/overlay/sky value is **one of** the names defined in the matching
  `xml/*.xml`, and is defined at all;
- a preset passed in (`{ base => 'foo' }`, `{ division => { name => 'stripes', count => 13 } }`) is
  honoured exactly — these are the assertions that were always meaningful;
- formatter output matches the wording the template really emits (loosened to the template's real
  shape, still checking the parts that matter: leading article, the "Adventurers should be wary" tail,
  no `undef` leaking into prose);
- no test depends on which key `keys %hash` returns first.

Also plumbing the fork never set up: `tests/TestMagicItemFormatter.pm` gets the same `#!` line as
the other 43, and `runtest.sh` gets the invocation that actually works (`-I lib -I tests`; it
currently passes `-l lib/`, which `prove` reads as the blib switch plus a stray file argument).

**Out of test scope:** making generation itself deterministic. Sorting key iteration in
`GenericGenerator` would do it, but it changes what the generators produce for existing saved seeds,
so it is not part of getting the container back.

## Site links to check today

From `Templates/base.tmpl` (the "Generators" menu in your screenshot) — 17 targets, all must be 200:
`citygenerator`, `customcitygenerator`, `npcgenerator`, `namegenerator`, `legendgenerator`,
`rumorgenerator`, `bondgenerator`, `flaggenerator`, `postinggenerator` (Help Wanted),
`magicitemgenerator`, `deitygenerator`, `cuisinegenerator`, `resourcegenerator` ("So you're looking
for"), `wantedpostergenerator`, `crittergenerator`, `worldgenerator`, plus the `/generator/` index
itself and `/` redirecting to it. Measured in the spike: all 17 return 200.

`multiflaggenerator`, `regionmap`, `worldmap`, `genstats` are not in the nav; `multiflaggenerator`
and `genstats` still work and will be checked, `regionmap`/`worldmap` are the known-broken pair.

## Left to the builder

Exact step order and layer boundaries in the Dockerfile; whether the smoke check is a `RUN` in the
image or a script in the repo; naming of `docker/apache.conf`.
