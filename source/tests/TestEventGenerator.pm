#!/usr/bin/perl -wT
###############################################################################
#
package TestEventGenerator;

use strict;
use warnings;
use Data::Dumper;
use EventGenerator;
use Exporter;
use GenericGenerator;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );


subtest 'test create' => sub {
    my $event;
    GenericGenerator::set_seed(1);
    $event = EventGenerator::create();
    is( $event->{'seed'}, 41630 );

    $event = EventGenerator::create( { 'seed' => 12 } );
    is( $event->{'seed'}, 12 );

    done_testing();
};

# select_base() draws from the keys of the <event> elements in xml/events.xml.
# srand fixes the sequence of rand() values but not how many of them are consumed
# before a pick, because that depends on the order Perl walks those keys, and that
# order is randomized per process. So the contract is membership in the option set,
# never a specific recorded word.
subtest 'test select_base' => sub {
    my $event;
    my $events = XML::Simple->new->XMLin('xml/events.xml');

    $event = EventGenerator::create( { 'seed' => 12 } );
    EventGenerator::select_base($event);

    is( $event->{'seed'}, 12 );
    ok( defined $event->{'base'} && exists $events->{'event'}{ $event->{'base'} },
        "base '" . ( $event->{'base'} // '' ) . "' is one of the events in events.xml" );
    is( $event->{'name'}, $event->{'base'}, 'name defaults to the base' );

    # Ten seeds rather than one: a generator that stopped consuming randomness
    # would pass the single-seed version above.
    for my $seed ( 1 .. 10 ) {
        my $e = EventGenerator::create( { 'seed' => $seed } );
        EventGenerator::select_base($e);
        ok( defined $e->{'base'} && exists $events->{'event'}{ $e->{'base'} }, "seed $seed base is valid" );
        is( $e->{'name'}, $e->{'base'}, "seed $seed name defaults to base" );
    }

    $event = EventGenerator::create( { 'seed' => 12, 'base' => 'foo' } );
    EventGenerator::select_base($event);

    is( $event->{'seed'}, 12 );
    is( $event->{'base'}, 'foo' );
    is( $event->{'name'}, 'foo' );


    done_testing();
};

subtest 'test select_modifier' => sub {
    my $event;
    $event = EventGenerator::create( { 'seed' => 12, 'base' => 'war' } );
    EventGenerator::select_modifier($event);

    is( $event->{'seed'},     12 );
    is( $event->{'base'},     'war' );
    isnt( $event->{'modifier'}, undef );
    like( $event->{'name'},     '/.+war/' );


    $event = EventGenerator::create( { 'seed' => 12, 'base' => 'war', 'modifier' => 'foo' } );
    EventGenerator::select_modifier($event);

    is( $event->{'seed'},     12 );
    is( $event->{'base'},     'war' );
    is( $event->{'modifier'}, 'foo' );
    is( $event->{'name'},     'foo war' );


    done_testing();
};


done_testing();
1;
