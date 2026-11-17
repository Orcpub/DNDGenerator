#!/usr/bin/perl -wT
###############################################################################
#
package TestBondGenerator;

use strict;
use warnings;

use Data::Dumper;
use Exporter;
use GenericGenerator qw( set_seed );
use BondGenerator;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );


subtest 'test create' => sub {
    my $bond;
    $bond = BondGenerator::create();
    foreach my $value (qw( seed other template) ){
        isnt($bond->{$value}, undef, "ensure $value is set");
    }

    # The contract is that BondGenerator::create leaves a finished sentence behind: every
    # <template> option in xml/bonds.xml is Template Toolkit text built out of [%person.N%]
    # and [%other%], so interpolation must consume every directive. Which template a seed
    # picks is hash-order dependent, so nothing about the wording itself can be asserted -
    # 2 of the 171 options ("[%person.0%] camped together recently." and "...duel to the
    # death and both lost.") resolve to the NPC's name with no "you" in it whenever
    # person.0 is the other person, which is what an earlier /you/i assertion tripped over.
    ok( defined $bond->{'template'} && length $bond->{'template'}, 'the interpolated template is not empty' );
    unlike( $bond->{'template'} // '', qr/\[/, 'no template placeholders survive interpolation' );
    
    $bond = BondGenerator::create(
        {
            'seed'        => 12,
            'other'       => 'Zeus',
            'template'    => 'Dog and [% other %] show.',
            'when_chance'   => 1,
            'reason_chance' => 1,
            'when'        => 'Silly',
            'reason'      => 'Because.'
        }
    );
    is( $bond->{'seed'},        12,                                   'ensure seed is set to 12' );
    is( $bond->{'other'},       'Zeus',                               'ensure other is set' );
    is( $bond->{'when_chance'},   1,                                    'ensure when_chance is set' );
    is( $bond->{'reason_chance'}, 1,                                    'ensure reason_chance is set' );
    is( $bond->{'when'},        'Silly',                              'ensure when is set' );
    is( $bond->{'reason'},      'Because.',                           'ensure reason is set' );
    is( $bond->{'template'},     'Silly, Dog and Zeus show. Because.', 'ensure template is sane' );

    done_testing();
};

subtest 'test when' => sub {
    my $bond;
    $bond = BondGenerator::create( {'seed' => 12, 'when_chance' => 1, 'when' => 'Silly',}  );

    is( $bond->{'when_chance'},   1,                                  'ensure when_chance is set' );
    is( $bond->{'when'},        'Silly',                              'ensure when is set' );
    like($bond->{'template'}, '/^Silly,/');

    done_testing();
};


subtest 'test select_reason' => sub {
    my $bond;
    $bond = BondGenerator::create({'seed'=>1, 'reasontype'=>'what',});
    is( $bond->{'reasontype'}, 'what', 'ensure reasontype is set' );

    $bond = BondGenerator::create({'seed'=>1, 'reasontype'=>'what', 'reason_chance'=>100});
    is( $bond->{'reasontype'}, 'what', 'ensure reasontype is set' );
    is( $bond->{'reason_chance'}, '100', 'ensure reason_chance is set' );
    is( $bond->{'reason'}, undef, 'ensure reason is not set' );


    $bond = BondGenerator::create({'seed'=>1, 'reasontype'=>'what', 'reason_chance'=>1});

    is( $bond->{'reasontype'}, 'what', 'ensure reasontype is set' );
    is( $bond->{'reason_chance'}, '1', 'ensure reason_chance is set' );
    isnt( $bond->{'reason'}, undef, 'ensure reason is set' );

    $bond = BondGenerator::create({'seed'=>1, 'reasontype'=>'what','reason_chance'=>1, 'reason'=>'because'});
    is( $bond->{'reasontype'}, 'what', 'ensure reasontype is set' );

    done_testing();
};
done_testing();
1;
