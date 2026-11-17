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
# worldmap and regionmap are CGI entry points too (.htaccess gives them +ExecCGI) even
# though `use City` still stops them running.
# forward request and error logs to docker log collector: Debian's Apache logs to files
RUN a2enmod cgid deflate expires headers rewrite && a2enconf dnd \
 && chmod +x /var/www/html/generator/*generator /var/www/html/generator/worldmap /var/www/html/generator/regionmap \
 && ln -sf /dev/stdout /var/log/apache2/access.log && ln -sf /dev/stderr /var/log/apache2/error.log

# Gate 1: everything compiles under taint. worldmap/regionmap are excluded: they
# `use City`, a module that has never existed in this repo or upstream.
RUN cd /var/www/html/generator \
 && for f in $(find . -maxdepth 1 -type f | xargs grep -l '^#!/usr/bin/perl') lib/*.pm; do \
      case "$f" in *regionmap|*worldmap) continue;; esac; \
      perl -Tc -Ilib -Itests "$f" >/dev/null || exit 1; \
    done

# Gate 2: the test suite. -T and -I are on the command line because taint mode
# ignores PERL5LIB, and --exec picks a prove handler instead of guessing.
RUN cd /var/www/html/generator \
 && prove --norc -j9 --exec "perl -T -Ilib -Itests" tests/*.pm

# The suite has run; test and provisioning files should not be web-served.
RUN rm -rf /var/www/html/generator/tests /var/www/html/generator/puppet

HEALTHCHECK --interval=1m --timeout=5s --start-period=10s \
  CMD perl -MHTTP::Tiny -e 'exit(HTTP::Tiny->new->get("http://127.0.0.1/generator/")->{status} == 200 ? 0 : 1)'

EXPOSE 80
CMD ["/usr/sbin/apache2ctl","-D","FOREGROUND"]
