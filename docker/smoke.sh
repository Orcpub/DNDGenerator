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
  out=$(curl -s -L -o /tmp/smoke.body -w '%{http_code} %{size_download} %{url_effective}' "$BASE/$p")
  code=${out%% *}; rest=${out#* }; size=${rest%% *}; url=${rest#* }
  if [ "$code" != "200" ] || [ "$size" -lt 1000 ]; then echo "FAIL $BASE/$p -> $code $size"; fail=1;
  elif grep -qiE "Internal Server Error|Can.t locate|Compilation failed|#!/usr/bin/perl" /tmp/smoke.body; then
    echo "FAIL $BASE/$p -> $code but body is not generated output"; fail=1
  elif ! grep -q "</html>" /tmp/smoke.body; then
    # every page is rendered through source/Templates/base.tmpl, whose last line is
    # </html>; a 200 without it is a template that stopped wrapping, not a generator page
    echo "FAIL $BASE/$p -> $code ${size}B but the body has no </html>"; fail=1
  elif [ -z "$p" ] && [ "${url%/generator/}" = "$url" ]; then
    # the "" entry is "/": RedirectMatch must land it on /generator/. A bare 200 proves
    # nothing here because Debian's default /var/www/html/index.html still exists.
    echo "FAIL $BASE/$p -> $code but it did not land on /generator/ (ended at $url)"; fail=1
  else echo "ok   $BASE/$p $code ${size}B"; fi
done
exit $fail
