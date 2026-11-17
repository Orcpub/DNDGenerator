# The six CPAN modules with no Debian package in trixie. Runtime deps that DO have Debian
# packages are installed by apt in the Dockerfile.
requires 'Lingua::EN::Numbers';
requires 'Lingua::EN::Titlecase';
requires 'Lingua::EN::Conjugate';
requires 'Lingua::EN::Gender';
requires 'Lingua::Conjunction';
requires 'Template::Plugin::Lingua::EN::Inflect';
