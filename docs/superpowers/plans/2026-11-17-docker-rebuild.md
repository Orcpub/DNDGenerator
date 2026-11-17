# DNDGenerator Container Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `FROM php` image with a Debian + Apache + system-Perl image that serves the Perl CGI site, and make the test suite green and repeatable so it can gate the build.

**Architecture:** One Dockerfile, single stage: runtime deps from Debian apt, the seven CPAN-only modules from a `cpanfile` via `cpanm`, Apache `mod_cgid` executing the generators in `/var/www/html/generator`. Two build gates (compile-under-taint, then `prove`) plus a host-side smoke script that fetches every page the site links.

**Tech Stack:** Perl 5.40 (Debian), Apache 2.4.71 (`mpm_event`, `cgid`, `deflate`, `expires`, `headers`, `rewrite`), Docker/Buildx, `Test::More`/`prove`, POSIX bash + curl for the smoke script.

**Spec:** `docs/superpowers/specs/2026-11-17-docker-rebuild-design.md`

## Global Constraints

- No PHP anywhere. The app is Perl CGI; `FROM php` is deleted, not upgraded.
- Base image `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` (Perl 5.40, Apache 2.4.71). Never `perl:*` images — they carry a second, from-source Perl at `/usr/local` that `/usr/bin/perl` never sees.
- Perl comes from `/usr/bin/perl` only. CPAN modules must land in the system `@INC` (`cpanm --notest`, no `--local-lib`: taint mode ignores `PERL5LIB`).
- Entrypoint scripts keep `#!/usr/bin/perl -wT`. Taint mode ignores `PERL5LIB`, so `-I` switches go on the command line and the app directory must be the CWD (relative `use lib "lib/"`, `INCLUDE_PATH => 'Templates/'`).
- Public URL contract unchanged: `/generator/<script>`, `DirectoryIndex citygenerator`, port 80 in, `/` → `/generator/`.
- Runtime deps are these apt packages, no others: `apache2`, `ca-certificates`, `libcgi-pm-perl`, `libclone-perl`, `libjson-perl`, `liblingua-en-inflect-perl`, `libnumber-format-perl`, `libswitch-perl`, `libtemplate-perl`, `libtest-exception-perl`, `libtime-parsedate-perl`, `libtimedate-perl`, `libxml-parser-perl`, `libxml-simple-perl`. (`libxml-parser-perl` is required: XML::Simple has no parser without it, and `--no-install-recommends` does not pull one.)
- CPAN-only modules are exactly the seven in `cpanfile`: `Lingua::EN::Numbers`, `Lingua::EN::Titlecase`, `Lingua::EN::Conjugate`, `Lingua::EN::Gender`, `Lingua::Conjunction`, `Template::Plugin::Lingua::EN::Inflect`, `Lingua::EN::Inflect::Number`.
- Not touched by this plan: `lib/` generation logic (except the one dead import in Task 1), `xml/*.xml`, `Templates/`, `js/`, `.github/workflows/docker.yaml`.
- `worldmap` and `regionmap` stay broken (they `use City`, a module that exists in neither this repo nor upstream) and are excluded from both gates and the smoke list. They are not linked from `Templates/base.tmpl`.
- All commands below are run from the repository root in Git Bash on Windows (Docker Desktop).

## Review Focus

- **A dependency that installs "successfully" but is absent.** `cpan install X` skips an unknown module and exits 0 — that is how the old image shipped without `Games::Dice::Roll20`. Expect `cpanm` to fail the build instead; never reintroduce `cpan install`.
- **A missing module at request time.** The original breakage: HTTP 500 on every page. Expect the compile gate to fail the build and the smoke script to fail on any non-200.
- **Apache serving the scripts as text.** Without `AllowOverride All` the `.htaccess` is ignored and `/generator/citygenerator` answers 200 with the raw script (body starting `#!/usr/bin/perl`). Expect smoke to fail on that body, not pass on the 200.
- **A seeded assertion that is not actually seeded.** `srand` pins the RNG sequence but not how many `rand()` calls the generator consumes, because hash order from `XML::Simple` is randomized per process; one seed produced six different bases. Expect updated tests to assert membership and presets, never a specific generated word.
- **A stale container behind a good image.** `docker compose up` reuses `dndgenerator:latest`. Expect the documented run command to be `docker compose up --build -d`.

---

### Task 1: Image that serves the site

**Files:**
- Create: `cpanfile`
- Create: `docker/apache.conf`
- Create: `docker/smoke.sh`
- Modify: `Dockerfile` (replace entirely)
- Modify: `docker-compose.yaml`
- Modify: `source/lib/GenericGenerator.pm:36` (delete one line)
- Modify: `source/tests/TestMagicItemFormatter.pm:1` (add shebang)
- Modify: `source/.htaccess` (Apache 2.2 → 2.4 access syntax)

**Interfaces:**
- Consumes: nothing.
- Produces: image `dndgenerator:latest` serving `/generator/`; `docker/smoke.sh <base-url>` exit 0 = every linked page returned 200 with generated content; the build gates that Task 2 appends to sit after the `a2enconf` line in `Dockerfile`.

- [ ] **Step 1: Confirm the current state is broken (this is the red run)**

```bash
docker build -t dndgenerator-old . && docker run --rm -p 8085:80 dndgenerator-old &
sleep 5 && curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8085/generator/
```
Expected: `500`, and `docker logs` of that container contains `Can't locate CGI.pm in @INC`. If the build reuses a cached layer, re-run with `--no-cache`.

- [ ] **Step 2: Create `cpanfile`**

```
# CPAN modules with no Debian package in trixie. Runtime deps that DO have Debian
# packages are installed by apt in the Dockerfile.
requires 'Lingua::EN::Numbers';
requires 'Lingua::EN::Titlecase';
requires 'Lingua::EN::Conjugate';
requires 'Lingua::EN::Gender';
requires 'Lingua::Conjunction';
requires 'Template::Plugin::Lingua::EN::Inflect';
requires 'Lingua::EN::Inflect::Number';
```

- [ ] **Step 3: Create `docker/apache.conf`**

`AllowOverride All` is what makes the app's `.htaccess` readable at all; the `Expires` block is the static-asset half of the speed goal.

```
<Directory /var/www/>
    AllowOverride All
    Require all granted
</Directory>
ServerName localhost
RedirectMatch ^/$ /generator/
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType text/css "access plus 7 days"
    ExpiresByType application/javascript "access plus 7 days"
    ExpiresByType image/png "access plus 30 days"
    ExpiresByType font/ttf "access plus 30 days"
</IfModule>
```

- [ ] **Step 4: Create `docker/smoke.sh`** (chmod +x)

The list is every target in the "Generators" menu of `source/Templates/base.tmpl`, plus the index, the `/` redirect, and `multiflaggenerator`. The body check is what catches scripts served as text or a 200-with-Perl-error.

```bash
#!/bin/bash
# Fetch every page the site links. Usage: docker/smoke.sh http://localhost:8085
set -u
BASE="${1:-http://localhost:80}"
PAGES=(generator "" generator/citygenerator generator/customcitygenerator generator/npcgenerator \
  generator/namegenerator generator/legendgenerator generator/rumorgenerator generator/bondgenerator \
  generator/flaggenerator generator/postinggenerator generator/magicitemgenerator \
  generator/deitygenerator generator/cuisinegenerator generator/resourcegenerator \
  generator/wantedpostergenerator generator/crittergenerator generator/worldgenerator \
  generator/multiflaggenerator)
fail=0
for p in "${PAGES[@]}"; do
  out=$(curl -s -L -o /tmp/smoke.body -w '%{http_code} %{size_download}' "$BASE/$p")
  code=${out%% *}; size=${out##* }
  if [ "$code" != "200" ] || [ "$size" -lt 1000 ]; then echo "FAIL $BASE/$p -> $out"; fail=1;
  elif grep -qiE "Internal Server Error|Can.t locate|Compilation failed|#!/usr/bin/perl" /tmp/smoke.body; then
    echo "FAIL $BASE/$p -> $code but body is not generated output"; fail=1
  else echo "ok   $BASE/$p $code ${size}B"; fi
done
exit $fail
```

- [ ] **Step 5: Replace `Dockerfile`**

`cpanfile` is copied before the install layer so editing dependencies invalidates it. `cpanminus`/`make` are purged inside the same layer they are installed, so no compiler ships. `libapache2-mod-perl2` is deliberately **not** installed: the app is plain CGI (`SetHandler cgi-script`), never `PerlResponseHandler`, and the spike measured no reason to carry it. The `prove` gate is added in Task 2, which is why it is absent here.

```dockerfile
# Perl CGI + Apache. debian:trixie-slim = Perl 5.40 / Apache 2.4.71, pinned by digest.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
ENV DEBIAN_FRONTEND=noninteractive

COPY cpanfile /opt/dnd-deps/cpanfile

# Runtime deps from apt; the CPAN-only ones from cpanfile. cpanminus/make exist only
# inside this layer: purging here keeps compilers and tooling out of the shipped image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      apache2 ca-certificates \
      libcgi-pm-perl libclone-perl libjson-perl liblingua-en-inflect-perl \
      libnumber-format-perl libswitch-perl libtemplate-perl libtest-exception-perl \
      libtime-parsedate-perl libtimedate-perl libxml-parser-perl libxml-simple-perl \
      cpanminus make \
 && cpanm --notest --quiet --installdeps /opt/dnd-deps \
 && apt-get purge -y --auto-remove cpanminus make \
 && rm -rf /var/lib/apt/lists/*

COPY source /var/www/html/generator/
COPY docker/apache.conf /etc/apache2/conf-available/dnd.conf
RUN a2enmod cgid deflate expires headers rewrite && a2enconf dnd

# Gate 1: everything compiles under taint. worldmap/regionmap are excluded: they
# `use City`, a module that has never existed in this repo or upstream.
RUN cd /var/www/html/generator \
 && for f in $(find . -maxdepth 1 -type f | xargs grep -l '^#!/usr/bin/perl') lib/*.pm; do \
      case "$f" in *regionmap|*worldmap) continue;; esac; \
      perl -Tc -Ilib -Itests "$f" >/dev/null || exit 1; \
    done

HEALTHCHECK --interval=1m --timeout=5s --start-period=10s \
  CMD perl -MHTTP::Tiny -e 'exit(HTTP::Tiny->new->get("http://127.0.0.1/generator/")->{status} == 200 ? 0 : 1)'

EXPOSE 80
CMD ["/usr/sbin/apache2ctl","-D","FOREGROUND"]
```

- [ ] **Step 6: Delete the dead import in `source/lib/GenericGenerator.pm`**

Remove the line `use Games::Dice::Roll20;` (line 36). Nothing calls it — the only references are the commented-out lines near `#my $dice = Games::Dice::Roll20->new();`, and dice are rolled by the local `d()` sub. The distribution is off CPAN (backpan only), so `cpanm` cannot resolve it and must fail.

- [ ] **Step 7: Fix the two source-tree nits**

Add `#!/usr/bin/perl -wT` as the first line of `source/tests/TestMagicItemFormatter.pm` (it is the only one of the 44 test files with no shebang, which makes `prove`'s handler choice ambiguous).

In `source/.htaccess`, replace each of the three `Order allow,deny` / `Allow from all` / `Satisfy All` groups with `Require all granted`, keeping `Options +ExecCGI`, `SetHandler cgi-script`, the `<Files ~ ...>` patterns and the `RedirectMatch 404` and `DirectoryIndex` lines as they are.

- [ ] **Step 8: Replace `docker-compose.yaml`**

```yaml
services:
  web:
    image: dndgenerator:latest
    build: .
    container_name: dndgenerator
    restart: unless-stopped
    ports:
      - 80:80
```

- [ ] **Step 9: Build and verify the site**

```bash
docker compose build --no-cache 2>&1 | tail -20
docker compose up -d
bash docker/smoke.sh http://localhost:80
```
Expected: build succeeds; smoke prints 19 `ok` lines and exits 0 (`echo $?` → `0`). Then confirm the speed claim and the lean image:
```bash
docker images --format '{{.Repository}} {{.Size}}' | grep dndgenerator      # ~248MB, was 940MB-1.1GB
curl -s -o /dev/null -w '%{time_total}s %{size_download}B\n' http://localhost/generator/citygenerator
curl -s -H 'Accept-Encoding: gzip' -o /dev/null -w '%{size_download}B\n' http://localhost/generator/citygenerator
```
Expected: gzip transfer about 22.5% of the plain size (measured 22.3%–22.9% over ten seeds). Add `?seed=` to both requests: every request generates a new page, so the two byte counts above are of two different pages and the ratio they imply is noise.

- [ ] **Step 10: Verify the gates can fail**

A gate that cannot fail is decoration. Three checks, each reverted immediately after:

```bash
# a) a module the app needs but the image lacks must break the compile gate
docker run --rm dndgenerator:latest sh -c 'sed -i "s/^use CGI;/use CGI; use NoSuch::Module;/" /var/www/html/generator/citygenerator && cd /var/www/html/generator && perl -Tc -Ilib citygenerator'; echo "exit=$?"
# b) an unknown name in cpanfile must fail the build, not be skipped (the old 'cpan install' behaviour)
printf "requires 'NoSuch::Module';\n" >> cpanfile && docker compose build 2>&1 | tail -5; git checkout cpanfile
```
Expected: (a) `Can't locate NoSuch/Module.pm`, exit non-zero; (b) the build fails with `Couldn't find module or a distribution NoSuch::Module`, proving `cpanm` cannot hide a bad dependency the way `cpan install` did. Confirm `cpanfile` is back to the seven modules from Step 2.

- [ ] **Step 11: Commit**

```bash
git add Dockerfile cpanfile docker docker-compose.yaml source/lib/GenericGenerator.pm source/tests/TestMagicItemFormatter.pm source/.htaccess
git commit -m "fix(docker): rebuild on Debian + system Perl so the site serves again

The image was FROM php, which now resolves to a PHP 8.5 CLI image with no Apache,
and the app never used PHP: it is Perl CGI. CGI.pm had also left the Debian perl
package, so every page 500'd. Adds the real dependency set (apt + cpanfile), a
taint-mode compile gate, Apache wiring the .htaccess needs, and a smoke check of
every page the site links. Drops the dead Games::Dice::Roll20 import, which is off
CPAN and was being silently skipped by 'cpan install'."
```

---

### Task 2: Green, repeatable suite that gates the build

**Files:**
- Modify: `source/tests/TestEventGenerator.pm:31-51`
- Modify: `source/tests/TestFlagGenerator.pm:70-147`
- Modify: `source/tests/TestCritterFormatter.pm:21-27`
- Modify: `source/tests/TestWorldFormatter.pm:30-85`
- Modify: `source/tests/TestGenericGenerator.pm:279` (same class, found at the 30-run bar)
- Modify: `source/tests/TestBondGenerator.pm:28` (same class, found at the 30-run bar)
- Modify: `source/tests/TestMapJSONFormatter.pm:25` (same class, found at the 30-run bar)
- Modify: `source/tests/TestCityscapeFormatter.pm:69` (same class, found at the 30-run bar)
- Modify: `runtest.sh`
- Modify: `Dockerfile` (append the `prove` gate and the post-suite cleanup)

**Interfaces:**
- Consumes: Task 1's image (deps + `libtest-exception-perl`, `prove` from the `perl` package).
- Produces: `docker build .` that also runs the suite; a suite whose result does not change between runs.

**Why eight files change, not four:** `GenericGenerator::set_seed` does `srand $seed`, which fixes the RNG *sequence* but not how many `rand()` calls happen before a pick — that depends on the order Perl iterates the hashes `XML::Simple` built, and Perl randomizes hash order per process. Measured: `EventGenerator::create({seed=>12})` + `select_base` returned six different bases over ten runs. So assertions on specific generated words cannot be re-recorded; assert the contract instead. The three `roll`-pinned cases in `TestWorldFormatter` keep their rolls, because rolls do drive the sentence structure.

The four files above are only the ones that failed on the first inspection. After they were fixed, 5 of 30 full-suite runs still failed: `TestGenericGenerator.pm:279`, `TestBondGenerator.pm:28`, `TestMapJSONFormatter.pm:25` and `TestCityscapeFormatter.pm:69` — all the same hash-order class, each one visible only as a rare single-run failure. Those four files changed too, and the acceptance bar moved from 10 consecutive green runs to 30.

- [ ] **Step 1: Run the suite and record the failures (red run)**

```bash
docker build --progress=plain . 2>&1 | grep -E "^tests/|Result:|Failed test" | tail -20
```
Not yet gated in the build, so run it directly instead:
```bash
docker run --rm dndgenerator:latest sh -c 'cd /var/www/html/generator && prove --norc -j9 --exec "perl -T -Ilib -Itests" tests/*.pm' 2>&1 | tail -12
```
Expected: `Result: FAIL` naming `TestCritterFormatter`, `TestFlagGenerator`, `TestWorldFormatter` and sometimes `TestEventGenerator`. Run it three times: the failing set is not identical each time — that is the flakiness being fixed.

- [ ] **Step 2: Rewrite `TestEventGenerator.pm` `test select_base`**

`select_base` picks `base` from `keys %{ $event_data->{'event'} }` (the `name` attribute of each `<event>` in `xml/events.xml`) and then sets `name` to that base. Assert membership and that relationship; keep the existing preset assertions in the same subtest (`{ base => 'foo' }` must come back unchanged) because those already pass and are the meaningful ones:

```perl
my $events = XML::Simple->new->XMLin('xml/events.xml');
$event = EventGenerator::create( { seed => 12 } );
EventGenerator::select_base($event);
is( $event->{'seed'}, 12 );
ok( defined $event->{'base'} && exists $events->{'event'}{ $event->{'base'} },
    "base '" . ( $event->{'base'} // '' ) . "' is one of the events in events.xml" );
is( $event->{'name'}, $event->{'base'}, 'name defaults to the base' );
```
`XML::Simple` is already imported in that file. Then repeat the same pair of assertions over ten seeds so a run that stopped consuming randomness would be noticed:

```perl
for my $seed ( 1 .. 10 ) {
    my $e = EventGenerator::create( { seed => $seed } );
    EventGenerator::select_base($e);
    ok( defined $e->{'base'} && exists $events->{'event'}{ $e->{'base'} }, "seed $seed base is valid" );
    is( $e->{'name'}, $e->{'base'}, "seed $seed name defaults to base" );
}
```
Ten seeds rather than one: a generator that stopped consuming randomness would pass the single-seed version. Keep the existing preset assertions in the subtest as well.

- [ ] **Step 3: Rewrite the two `TestFlagGenerator.pm` subtests**

`generate_division` picks `division->{name}` from `keys %{ $flag_data->{division}{option} }` and `generate_overlay` likewise from `overlay/option` in `xml/flag.xml`; `side`/`count` come from the chosen option's `feature` entries, so they are only meaningful for a chosen name. Replace `is( $flag->{'division'}->{'name'}, 'diagonal' )` and `is( $flag->{'overlay'}->{'name'}, 'quad' )` / `is( $flag->{'overlay'}->{'side'}, 'sw' )` with membership against the XML, keeping every preset assertion in both subtests:

```perl
my $flags = XML::Simple->new->XMLin('xml/flag.xml');
$flag = FlagGenerator::create( { seed => 41630 } );
FlagGenerator::generate_division($flag);
ok( exists $flags->{'division'}->{'option'}{ $flag->{'division'}->{'name'} },
    'division ' . $flag->{'division'}->{'name'} . ' is one of the divisions in flag.xml' );
```
and the same shape for `overlay` against `$flags->{'overlay'}->{'option'}`.

- [ ] **Step 4: Loosen `TestCritterFormatter.pm` `Test Critter Summary`**

Two claims in the first draft of this step were wrong, and the pattern it gave fails 400 of 400 runs. First: `printSummary` really does end each sentence with `".\n "` (a newline **plus** a space — see the two `$content.=` lines in `source/lib/CritterFormatter.pm`), so a pattern that omits that trailing space is the thing that never matches. Second: the article is produced by `Lingua::EN::Inflect::A()`, which returns `a` or `an` depending on the generated terror word, so `is a.+` cannot hold; the shipped form is `is an?`. Keep every word the template guarantees and wildcard only the generated phrases — actual output looks like:

```
The Dark-crested Rxomd Camel is a cute camel that paralyses its prey and eats it alive.
Adventurers should be wary of its massive horns, and it's reported unearthly wail.
```

```perl
like(
    $crittertext,
    qr{^The .+ is an? .+ .+ that .+\.\n Adventurers should be wary of its .+ .+, and it's reported .+\.\n $}
);
```
Leave `Test Critter Description` and `Test Critter Data` alone; they pass.

- [ ] **Step 5: Rewrite `TestWorldFormatter.pm` `Test World Sky Summary`**

`printSkySummary` always emits exactly four lines whose shape is driven by the pinned `starsystem_roll` / `moons_roll` / `celestial_roll`, while names (`Macurto`, `Chale`), colours and the atmosphere "reason" clause are random. Keep the roll-driven words, wildcard the rest, and drop the `which is partially due to pollution` clause (the reason is randomly absent — see `printAtmosphere`). The first of the four cases becomes:

```perl
like( $summary,
    qr/^.* orbits a single star: .+\.\n.* also has no moons\.\nIn the night sky, you see nothing unusual\.\nDuring the day, the sky is .+\.\n$/s
);
```
Apply the same rule to the other three cases in that subtest: keep `a binary star` / `a double moon` / `two celestial objects` and `a trinary star` / `a triple moon` / `three celestial objects`, drop every recorded proper noun, adjective list and `pollution` clause. Keep `Test World Land Summary`, `Test World Weather Summary` and the two remaining subtests as they are.

- [ ] **Step 6: Fix `runtest.sh` so the documented runner works**

`prove` reads `-l lib/` as the blib switch plus a stray file argument, and with no `--exec` it aborts on a handler tie. In both `prove` invocations replace `-l lib/` with `-Ilib -Itests` and add `--exec "perl -T -Ilib -Itests"`. Do not change the `profile`/`cover` branches beyond that substitution.

- [ ] **Step 7: Verify the suite is green and repeatable**

```bash
docker run --rm dndgenerator:latest sh -c 'cd /var/www/html/generator && for i in $(seq 1 30); do prove --norc -j9 --exec "perl -T -Ilib -Itests" tests/*.pm > /tmp/s$i.log 2>&1 || echo "run $i FAILED"; done; grep -l "Result: FAIL" /tmp/s*.log; echo "done"'
```
Expected: no `run N FAILED`, no filenames printed by `grep -l`, then `done`. Thirty runs, not ten: ten consecutive green runs were achieved while the suite still failed 5 of 30 runs, so ten is not a bar that proves repeatability.

- [ ] **Step 8: Add the suite gate to `Dockerfile`, after the Gate 1 block**

```dockerfile
# Gate 2: the test suite. -T and -I are on the command line because taint mode
# ignores PERL5LIB, and --exec picks a prove handler instead of guessing.
RUN cd /var/www/html/generator \
 && prove --norc -j9 --exec "perl -T -Ilib -Itests" tests/*.pm

# The suite has run; test and provisioning files should not be web-served.
RUN rm -rf /var/www/html/generator/tests /var/www/html/generator/puppet
```

- [ ] **Step 9: Build and smoke again**

```bash
docker compose build 2>&1 | grep -E "Result:|ERROR" ; echo "build exit=$?"
docker compose up -d --force-recreate && bash docker/smoke.sh http://localhost:80 && echo "SMOKE OK"
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/generator/tests/TestCityGenerator.pm
```
Expected: `Result: PASS`, build exit `0`, `SMOKE OK`, and `404` for the removed test file.

- [ ] **Step 10: Verify Gate 2 can fail**

```bash
sed -i "s/1;\$/is( 1, 2, 'deliberate failure' );\n1;/" source/tests/TestRumorGenerator.pm
docker compose build 2>&1 | tail -6; echo "build exit=$?"
git checkout source/tests/TestRumorGenerator.pm
```
Expected: `Result: FAIL` from the prove step and a non-zero build exit. After the `git checkout`, `docker compose build` must succeed again.

- [ ] **Step 11: Commit**

```bash
git add source/tests runtest.sh Dockerfile
git commit -m "test: assert what the generators guarantee instead of recorded random output

srand pins the RNG sequence but not how many rand() calls a generator consumes,
since the order it walks the XML-derived hashes is randomized per process; one seed
yielded six different event bases. The eight red files now assert membership in the
xml/*.xml option sets, honour preset pass-through, and match the wording the
formatters actually emit. prove also gets an explicit --exec so it no longer aborts
the whole run on a handler tie, and the suite now gates the image build."
```

---

### Task 3: Tell the truth in the README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1's `cpanfile`/`docker/smoke.sh`, Task 2's build gate.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Replace the dependency and usage sections**

Delete the `cpan install ...` one-liner and the "Uses the following CPAN Dependancies" paragraph: those names are wrong in both directions (they list `List::MoreUtils`, `Email::Date::Format` and `Test::Harness`, which no code imports, and omit `CGI`, the XML parser and `Switch`). In their place, state that the runtime deps are apt packages listed in `Dockerfile`, the CPAN-only ones are in `cpanfile`, and the test suite runs as part of `docker build` (so a dependency problem fails the build instead of the first page load). Keep the project description, the fork/credit paragraph and the screenshot.

- [ ] **Step 2: Document how to run and check it**

```
docker compose up --build -d
bash docker/smoke.sh http://localhost:80
```
plus `http://localhost/generator/` for a browser, and a note that `--build` is what makes `up` pick up changes.

- [ ] **Step 3: Document the known-broken pair, as future work**

Add a short "Known issues" section: `worldmap` and `regionmap` return HTTP 500 because they `use City`, a module that has never been in this repository or in the upstream `CityGenerator/CityGenerator` it was forked from. Note that neither is linked from the site's Generators menu — the world map is drawn in the browser from JSON by `source/js/WorldMap.js` — and that a follow-up could write a small `City.pm` over `CityGenerator`. Also note `Vagrantfile` + `source/puppet` are the retired pre-Docker provisioning path.

- [ ] **Step 4: Verify the documented commands work verbatim**

```bash
docker compose down && docker compose up --build -d && bash docker/smoke.sh http://localhost:80
```
Expected: `SMOKE OK` output, exit 0, using only commands copied from the README.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: describe the real dependencies, run and check steps

The old CPAN list was both wrong and incomplete, and there was no mention of the
worldmap/regionmap endpoints being broken."
```

---

## Follow-up work, not in this plan

- `worldmap` / `regionmap`: write the missing `City.pm` over `CityGenerator`, or delete the two scripts.
- `.github/workflows/docker.yaml`: retired actions (`checkout@v2`, `build-push-action@v2`, `::set-output`), and add a PR workflow that runs `docker build` (which now runs the suite) plus `docker/smoke.sh`.
- Retire `Vagrantfile` and `source/puppet`, and the CentOS-era `source/puppet/modules`.
- Making generation itself deterministic (sorted key iteration in `GenericGenerator`) — it would change output for existing saved seeds, so it needs its own decision.
