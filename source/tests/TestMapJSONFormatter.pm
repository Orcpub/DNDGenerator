#!/usr/bin/perl -wT
###############################################################################
#
package TestMapJSONFormatter;

use strict;
use warnings;

use CityGenerator;
use Data::Dumper;
use Exporter;
use JSON;
use MapJSONFormatter;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );


subtest 'Test MapJSON' => sub {
    my $city = CityGenerator::create( { seed => 1 } );
    CityGenerator::flesh_out_city($city);
    my $json = MapJSONFormatter::printCityMapJSON($city);

    # printCityMapJSON returns JSON->new->utf8->encode($mapdata), and JSON emits hash keys
    # in perl's hash order - which is randomized per process - so the old '/"seed":1,/'
    # pattern only held while "seed" happened to be the first key. Parse the document.
    my $mapdata = decode_json($json);
    is( ref $mapdata, 'HASH', 'the map data is a json object' );
    is( $mapdata->{'seed'}, 1, 'the pinned seed is in the document' );
    is( $mapdata->{'seed'}, $city->{'seed'}, 'the seed is the city seed, not a recorded value' );

    # Keys the browser actually reads: Templates/citygenerator_content.tmpl assigns this
    # object to citydata and calls new CityMap(citydata). js/CityMap.js reads seed,
    # diameter, area, wall, roads, mainroads, biome_color, city_cell_count,
    # maxdistrictpercent, maxsingledistrictpercent and districts, and its VoronoiMap
    # superclass (js/VoronoiMap.js) reads total_cell_count; the template supplies the
    # canvas itself. map.districts is used as an array (length, [i] -> .name) downstream.
    for my $key (qw( seed diameter area roads mainroads biome_color city_cell_count
        total_cell_count maxdistrictpercent maxsingledistrictpercent ))
    {
        ok( defined $mapdata->{$key}, "consumed key $key is present and defined" );
    }
    is( ref $mapdata->{'districts'}, 'ARRAY', 'districts is a json array, as CityMap.js expects' );
    ok( !grep( { !length $_ } @{ $mapdata->{'districts'} } ), 'every district name is non-empty' );
    is( scalar @{ $mapdata->{'districts'} }, scalar keys %{ $city->{'districts'} },
        'one district per key in the city' );

    # js guards on `if (this.wall)` and reads wall.height, and printCityMapJSON only emits
    # the wall object when the city actually has walls, so the two must agree.
    is( ( defined $mapdata->{'wall'} ) ? 1 : 0,
        ( defined $city->{'walls'}->{'height'} && $city->{'walls'}->{'height'} > 0 ) ? 1 : 0,
        'wall is present exactly when the city has wall height' );

    # printCityMapJSON documents total_cell_count as spanning 150-1000 for the whole
    # size_modifier range; the canvas scale in js depends on staying inside it.
    cmp_ok( $mapdata->{'total_cell_count'}, '>=', 150, 'total_cell_count is within the documented range' );
    cmp_ok( $mapdata->{'total_cell_count'}, '<=', 1000, 'total_cell_count is within the documented range' );

    done_testing();
};


done_testing();
1;
