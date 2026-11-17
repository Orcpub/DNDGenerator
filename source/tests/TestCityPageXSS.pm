#!/usr/bin/perl -wT
###############################################################################
#
package TestCityPageXSS;

use strict;
use warnings;
use Test::More;

# The entry points are programs, not modules, so this test runs the real CGI script as
# a child process and reads the HTML it prints. CGI.pm takes its parameters from
# REQUEST_METHOD + QUERY_STRING, so no web server is needed. The command line is a
# literal string, which is what keeps it usable under taint mode.
#
# Two live vectors are pinned here, both through the one unvalidated parameter
# (citygenerator's name): the name reflected raw in body context, and a single quote in
# the name closing the single-quoted onload='create_flag( <flag JSON> )' attribute on
# <body> and starting a new attribute.
sub page {
    my ($qs) = @_;
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = $qs;
    # Taint refuses to fork with a tainted PATH; the child needs only the system perl.
    local $ENV{PATH}           = '/usr/bin:/bin';
    my $out = `perl -T -Ilib -Itests citygenerator`;
    return defined $out ? $out : '';
}

my $angle = page('seed=1&name=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E');
ok( length($angle) > 1000, 'the page rendered' );
unlike( $angle, qr/<img src=x onerror=alert\(1\)>/, 'angle-bracket name is not reflected' );

my $quote = page("seed=1&name=x%27%20onmouseover%3Dalert(1)%20x%3D%27");
unlike( $quote, qr/onmouseover=alert\(1\)/, 'quote in name does not inject a body attribute' );
like( $quote, qr{<body[^>]*onload='[^']*'>}, 'the onload attribute stays a single quoted value' );

my $apostrophe = page('seed=1&name=O%27Brien%20the%20Second');
like( $apostrophe, qr{<body[^>]*onload='[^']*'>}, 'a name with an apostrophe keeps that attribute intact' );

my $ok_name = page('seed=1&name=Dammit%20Vandal%2C%20Jr.');
like( $ok_name, qr{<h1>Welcome to Dammit Vandal, Jr\.</h1>}, 'a normal name still renders' );

my $huge = page( 'seed=1&name=' . ( 'A' x 4000 ) );
ok( length($huge) > 1000, 'a 4000-byte name still renders a page' );
unlike( $huge, qr/A{100}/, 'an over-long name is dropped, not reflected' );

unlike( page('seed=1&name=Bj%C3%B6rn'), qr/Bj/, 'a non-ASCII name is dropped, not reflected' );

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
