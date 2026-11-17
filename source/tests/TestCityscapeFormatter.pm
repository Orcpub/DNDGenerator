#!/usr/bin/perl -wT
###############################################################################
#
package TestCityscapeFormatter;

use strict;
use warnings;
use CityGenerator;
use CityscapeFormatter;
use Data::Dumper;
use Exporter;
use GenericGenerator;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );

subtest 'Test Cityscape walls' => sub {
    my $city = CityGenerator::create( { seed => 1, 'wall_chance_roll' => 100 } );
    CityGenerator::flesh_out_city($city);
    my $cityscape = CityscapeFormatter::printWalls($city);
    is( $cityscape,
        'No walls currently surround the city.'
    );

    $city = CityGenerator::create( { seed => 1, 'wall_chance_roll' => 1, 'walls'=>{'height'=>'90', 'condition'=>'borked', 'material'=>'jello', 'style'=>'shingle'} } );
    CityGenerator::flesh_out_city($city);
    $cityscape = CityscapeFormatter::printWalls($city);
    like( $cityscape,
        '/Visitors are greeted with a borked jello shingle that is 90 meters tall. The city wall protects the core .+% of the city, with .+ towers spread along the .+ kilometer wall./',
        "ensure walls are printing"
    );

    $city = CityGenerator::create( { seed => 1,  } );
    CityGenerator::flesh_out_city($city);
    $cityscape = CityscapeFormatter::printWalls($city);
    isnt( $cityscape, undef, "ensure something is returned" );

    done_testing();
};

subtest 'Test Cityscape streets' => sub {
    my $city = CityGenerator::create( { seed => 1 } );
    CityGenerator::flesh_out_city($city);
    $city->{'streets'}->{'mainroads'}=1;
    $city->{'streets'}->{'roads'}=1;

    my $cityscape = CityscapeFormatter::printStreets($city);
    like( $cityscape, '/There is .+ leading to .+/',   "ensure streets are printing"    );

    $city->{'streets'}->{'mainroads'}=2;
    $city->{'streets'}->{'roads'}=2;

    $cityscape = CityscapeFormatter::printStreets($city);
    like( $cityscape, '/There are .+ leading to .+/',   "ensure streets are printing"    );




    done_testing();
};

subtest 'Test Cityscape districts' => sub {
    my $city = CityGenerator::create( { seed => 1 } );
    CityGenerator::flesh_out_city($city);
    my $cityscape = CityscapeFormatter::printDistricts($city);

    # generate_districts (lib/CityGenerator.pm) takes each <option> in xml/districts.xml by
    # chance, and how many rolls it spends before reaching an option depends on the order
    # that hash is walked, so the district count of a seed is not fixed (measured 5 or 6 for
    # seed 1 over 120 processes, but a 2 district city is legal output). printDistricts
    # joins the names with Lingua::EN::Inflect::conjunction(), which uses serial commas only
    # for three or more names, so the previous ": .+, and .+\." pattern silently required a
    # 3+ district city. Match the frame printDistricts guarantees for the districts this
    # city actually has, then check the names it emitted.
    my @districts = sort keys %{ $city->{'districts'} };
    if ( @districts > 1 ) {
        like(
            $cityscape,
            qr/^The city is broken into the following districts: .+ and .+\. \n$/,
            scalar(@districts) . " districts are joined into one sentence"
        );
        my ($listed) = $cityscape =~ /^The city is broken into the following districts: (.+)\. \n$/;
        my @names = split /,\s+and\s+|,\s+|\s+and\s+/, $listed // '';
        ok( !( grep { !length } @names ), 'no empty district name is listed' );
        is_deeply( [sort @names], \@districts, 'the sentence lists exactly the city districts' );
    } elsif ( @districts == 1 ) {
        like( $cityscape, qr/^The city includes an? \Q$districts[0]\E district\. \n$/,
            'a single district is named in the singular frame' );
    } else {
        is( $cityscape, "There are no defined districts in this city. \n", 'no districts says so' );
    }

    $city->{'districts'} ={'foo'=>{},};
    $cityscape = CityscapeFormatter::printDistricts($city);
    is( $cityscape, 
        "The city includes a foo district. \n",
        "ensure district is printed"
     );

    $city->{'districts'} ={};
    $cityscape = CityscapeFormatter::printDistricts($city);
    is( $cityscape, 
        "There are no defined districts in this city. \n",
        "ensure district is printed"
     );

    done_testing();
};

subtest 'Test Cityscape housing' => sub {
    my $city = CityGenerator::create( { 'seed' => 1, 'housing'=>{'wealthy'=>9,'average'=>8,'poor'=>4} } );
    CityGenerator::flesh_out_city($city);
    my $cityscape = CityscapeFormatter::printHousingList($city);
    is( $cityscape, "Among housing, there are 9 wealthy residences, 8 average homes and 4 dilapidated homes." );

    done_testing();
};



done_testing();
1;
