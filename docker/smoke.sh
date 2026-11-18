#!/bin/bash
# Fetch every page the site links. Usage: docker/smoke.sh http://localhost:8085
set -u
BASE="${1:-http://localhost:8080}"
body=$(mktemp) || exit 1
trap 'rm -f "$body"' EXIT
PAGES=(generator "" generator/citygenerator generator/customcitygenerator generator/npcgenerator \
  generator/namegenerator generator/legendgenerator generator/rumorgenerator generator/bondgenerator \
  generator/flaggenerator generator/postinggenerator generator/magicitemgenerator \
  generator/deitygenerator generator/cuisinegenerator generator/resourcegenerator \
  generator/wantedpostergenerator generator/crittergenerator generator/worldgenerator \
  generator/multiflaggenerator)
fail=0
for p in "${PAGES[@]}"; do
  out=$(curl -s -L -o "$body" -w '%{http_code} %{size_download} %{url_effective}' "$BASE/$p")
  code=${out%% *}; rest=${out#* }; size=${rest%% *}; url=${rest#* }
  if [ "$code" != "200" ] || [ "$size" -lt 1000 ]; then echo "FAIL $BASE/$p -> $code $size"; fail=1;
  elif grep -qiE "Internal Server Error|Can.t locate|Compilation failed|#!/usr/bin/perl" "$body"; then
    echo "FAIL $BASE/$p -> $code but body is not generated output"; fail=1
  elif ! grep -q "</html>" "$body"; then
    # every page is rendered through source/Templates/base.tmpl, whose last line is
    # </html>; a 200 without it is a template that stopped wrapping, not a generator page
    echo "FAIL $BASE/$p -> $code ${size}B but the body has no </html>"; fail=1
  elif [ -z "$p" ] && [ "${url%/generator/}" = "$url" ]; then
    # the "" entry is "/": RedirectMatch must land it on /generator/. A bare 200 proves
    # nothing here because Debian's default /var/www/html/index.html still exists.
    echo "FAIL $BASE/$p -> $code but it did not land on /generator/ (ended at $url)"; fail=1
  else echo "ok   $BASE/$p $code ${size}B"; fi
done

# The controls this repo's security work shipped, pinned here because no page body shows
# them: the two entry points that were deleted (worldmap, regionmap), the body cap, and the
# two response headers. Each is one curl, and each one used to be verified by hand.
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/generator/worldmap")
[ "$code" = 404 ] || { echo "FAIL $BASE/generator/worldmap -> $code, expected 404 (deleted)"; fail=1; }
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/generator/regionmap")
[ "$code" = 404 ] || { echo "FAIL $BASE/generator/regionmap -> $code, expected 404 (deleted)"; fail=1; }
# LimitRequestBody 65536 on the CGI predicate: Apache answers 413 before any Perl starts.
code=$(yes | head -c 1048576 | curl -s -o /dev/null -w '%{http_code}' -X POST --data-binary @- "$BASE/generator/citygenerator")
[ "$code" = 413 ] || { echo "FAIL 1MB POST to $BASE/generator/citygenerator -> $code, expected 413"; fail=1; }
heads=$(curl -s -D- -o /dev/null "$BASE/generator/citygenerator" | tr -d '\r' | tr 'A-Z' 'a-z')
case "$heads" in *'cache-control: no-store'*) ;; *) echo "FAIL no Cache-Control: no-store on a CGI page"; fail=1;; esac
case "$heads" in *'content-security-policy:'*) ;; *) echo "FAIL no Content-Security-Policy header"; fail=1;; esac
exit $fail
