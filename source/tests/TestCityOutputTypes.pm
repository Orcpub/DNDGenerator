#!/usr/bin/perl -wT
###############################################################################
#
package TestCityOutputTypes;

use strict;
use warnings;
use lib 'tests/lib';
use CGIScript qw( page );
use Test::More;

# The city page's ?type= switch is user-reachable. It used to answer ?type=dump with a
# Data::Dumper of the whole generated object (measured 409 KB against a 46 KB page, and
# every internal key in it) and ?type=post with the submitted parameters echoed back.
# Both branches are gone, so those queries must fall through to the normal page; the two
# formats the site's own tooling uses must keep working.
my $dump = page( 'citygenerator', 'seed=1&type=dump' );
unlike( $dump,   qr/\$VAR1/,      'type=dump prints no Data::Dumper' );
like(   $dump,   qr{</html>},     'type=dump falls through to the page' );

my $post = page( 'citygenerator', 'seed=1&type=post&name=TopSecretName' );
unlike( $post, qr/\$VAR1/, 'type=post prints no Data::Dumper' );
like(   $post, qr{<h1>Welcome to TopSecretName</h1>}, 'type=post falls through to the page, name included' );

my $json = page( 'citygenerator', 'seed=1&type=json' );
like( $json, qr/\{\s*"/, 'type=json still returns a JSON object' );

my $xml = page( 'citygenerator', 'seed=1&type=xml' );
like( $xml, qr/<\?xml version/, 'type=xml still returns XML' );

like( page( 'citygenerator', 'seed=1&type=nonsense' ), qr{</html>}, 'an unknown type falls through to the page' );

done_testing();

1;

__END__


=head1 AUTHOR

Jesse Morgan (morgajel)  C<< <morgajel@gmail.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2013, Jesse Morgan (morgajel) C<< <morgajel@gmail.com> >>. All rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation version 2
of the License.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=head1 DISCLAIMER OF WARRANTY

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
