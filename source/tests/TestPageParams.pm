#!/usr/bin/perl -wT
###############################################################################
#
package TestPageParams;

use strict;
use warnings;
use lib 'tests/lib';
use CGIScript qw( page );
use Test::More;

# The city page's `name` is not the only parameter the site takes. flaggenerator reads
# seed/cityid/continent/region, cuisinegenerator and resourcegenerator read seed,
# worldgenerator reads worldid — all with no check at all, and each value is printed back
# into the page (Template Toolkit AUTO_ESCAPE is off). So the pages take the same rule the
# city page takes: a parameter is accepted when it is digits, and dropped when it is not.
#
# The payload needs no quote and no attribute breakout on the reflected pages; the
# worldgenerator payload is the attribute-breakout shape, because that page puts worldid
# inside the single-quoted href='worldgenerator?worldid=…' in Templates/worldnav.tmpl.

my $angle = page( 'flaggenerator', 'seed=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E' );
ok(   length($angle) > 1000,                          'flaggenerator renders a page for a hostile seed' );
unlike( $angle, qr/<img src=x onerror=alert\(1\)>/,   'flaggenerator does not reflect a hostile seed' );
like( page( 'flaggenerator', 'seed=12345678' ), qr{Flag 12345678!}, 'flaggenerator still takes a numeric seed' );

unlike(
    page( 'cuisinegenerator', 'seed=%3C%2Ftitle%3E%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E' ),
    qr{</title><img src=x onerror=alert\(1\)>},
    'cuisinegenerator does not reflect a hostile seed out of <title>'
);
unlike(
    page( 'resourcegenerator', 'seed=%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E' ),
    qr/<img src=x onerror=alert\(1\)>/,
    'resourcegenerator does not reflect a hostile seed'
);

like(
    page( 'worldgenerator', "worldid=x%27%20onmouseover%3Dalert(1)%20x%3D%27" ),
    qr{<a [^>]*href='worldgenerator\?worldid=[^']*'>},
    'worldgenerator keeps the worldid link a single quoted attribute'
);

# Task 6 deleted the ?type=dump output branch; the Custom City form's "Dump it?" checkbox
# submits exactly that value, so the control has to go with it.
unlike( page( 'customcitygenerator', 'seed=1' ), qr/value="dump"/, 'the Custom City form has no dead Dump control' );

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
