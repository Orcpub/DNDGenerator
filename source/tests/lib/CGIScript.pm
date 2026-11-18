#!/usr/bin/perl -wT
###############################################################################
#
package CGIScript;

# Test helper: run one of the CGI entry points as a child process and return everything
# it printed, headers included. The entry points are programs, not modules, so this is how
# a test reaches the parameter handling and the output they write.
#
# CGI.pm takes its parameters from REQUEST_METHOD + QUERY_STRING, so no web server is
# needed. The command line is a literal string, which is what keeps the fork usable under
# taint mode, and PATH is set to a literal because taint refuses to fork with a tainted one.
#
# Lives in tests/lib/ on purpose: tests/*.pm is the suite's file glob, so a helper at
# tests/ would be run as a test with no plan in it.

use strict;
use warnings;
use Exporter;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION);
use base qw(Exporter);
@EXPORT_OK = qw( page );

sub page {
    my ( $script, $qs ) = @_;
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = $qs;
    local $ENV{PATH}           = '/usr/bin:/bin';
    my $out = `perl -T -Ilib -Itests $script`;
    return defined $out ? $out : '';
}

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
