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
      libnumber-format-perl libswitch-perl libtemplate-perl \
      # needed by the test gate below
      libtest-exception-perl \
      libtime-parsedate-perl libtimedate-perl libxml-parser-perl libxml-simple-perl \
      cpanminus make \
 && cpanm --notest --quiet --installdeps /opt/dnd-deps \
 && apt-get purge -y --auto-remove cpanminus make \
 && rm -rf /var/lib/apt/lists/*

COPY source /var/www/html/generator/
COPY docker/apache.conf /etc/apache2/conf-available/dnd.conf
# git records every file under source/ as 100644, so the exec bit a CGI script needs is
# missing from a Linux checkout; set it in the image instead of trusting the build host.
# Derive the list, do not enumerate it: same predicate as Gate 1, a regular file at the
# root of the document root whose first two bytes are `#!`. That covers the 17 *generator
# scripts and genstats (bash, not a page). A new entry point
# must also be added to the second list: the <Files> stanzas in source/.htaccess.
# No blanket `COPY --chmod=755`: that marks css, js, images and templates executable too.
# Strip exec from every regular file before the loop: a Windows build context marks every
# file 0755, and the mode in the image must not depend on which host ran the build.
# Directories keep their mode, so Apache can still traverse the tree.
# forward request and error logs to docker log collector: Debian's Apache logs to files
RUN a2enmod cgid deflate expires headers && a2enconf dnd \
 && sed -i 's/^ServerTokens OS$/ServerTokens Prod/; s/^ServerSignature On$/ServerSignature Off/' /etc/apache2/conf-available/security.conf \
 && sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf \
 && mkdir -p /var/run/apache2 \
 && chown -R www-data:www-data /var/log/apache2 /var/run/apache2 \
 && find /var/www/html/generator -type f -exec chmod a-x {} + \
 && for f in /var/www/html/generator/*; do \
      if [ -f "$f" ] && head -c2 "$f" | grep -q '#!'; then chmod +x "$f"; fi; \
    done \
 && ln -sf /dev/stdout /var/log/apache2/access.log && ln -sf /dev/stderr /var/log/apache2/error.log

# Gate 1: everything compiles under taint.
RUN cd /var/www/html/generator \
 && for f in $(find . -maxdepth 1 -type f | xargs grep -l '^#!/usr/bin/perl') lib/*.pm; do \
      perl -Tc -Ilib -Itests "$f" >/dev/null || exit 1; \
    done

# Gate 2: the test suite. -T and -I are on the command line because taint mode
# ignores PERL5LIB, and --exec picks a prove handler instead of guessing.
RUN cd /var/www/html/generator \
 && prove --norc -j9 --exec "perl -T -Ilib -Itests" tests/*.pm

# The suite has run; test and provisioning files should not be web-served.
RUN rm -rf /var/www/html/generator/tests /var/www/html/generator/puppet

# The master process runs as www-data on an unprivileged port: nothing in the image binds
# port 80, and the pid/log directories are owned by www-data for the same reason. The CMD
# stays apache2ctl because Debian's envvars sets APACHE_RUN_USER/APACHE_RUN_GROUP and
# APACHE_PID_FILE, which apache2.conf expands; the bare `apache2` binary does not source it.
HEALTHCHECK --interval=1m --timeout=5s --start-period=10s \
  CMD perl -MHTTP::Tiny -e 'exit(HTTP::Tiny->new->get("http://127.0.0.1:8080/generator/")->{status} == 200 ? 0 : 1)'

EXPOSE 8080
USER www-data
CMD ["/usr/sbin/apache2ctl","-D","FOREGROUND"]
