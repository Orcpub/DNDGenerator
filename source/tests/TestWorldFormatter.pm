#!/usr/bin/perl -wT
###############################################################################
#
package TestWorldFormatter;

use strict;
use warnings;
use Data::Dumper;
use Exporter;
use GenericGenerator;
use WorldFormatter;
use WorldGenerator;
use AstronomyGenerator;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );

subtest 'Test World Summary' => sub {
    my $astro = AstronomyGenerator::create( { seed => 1 } );
    my $world = WorldGenerator::create( { seed => 1, 'astronomy' => $astro } );
    my $summary = WorldFormatter::printSummary($world);
    is( $summary,
              "Macurto is a large, warm planet orbiting a single star.\n"
            . "Macurto has a single moon, a fragile brown atmosphere and fresh water is common.\n"
            . "The surface of the planet is 27% covered by water.\n" );
    done_testing();
};

# printSkySummary always emits four lines, and the pinned starsystem / moons /
# celestial rolls decide the wording that makes their structure: how many stars,
# moons and celestial objects are named. World, star and moon names, the colour
# lists and the atmosphere "reason" clause are generated (printAtmosphere omits the
# reason when the world has none), so they are wildcards rather than recorded words.
subtest 'Test World Sky Summary' => sub {
    my $astro = AstronomyGenerator::create(
        { seed => 1, 'starsystem_roll' => 1, 'moons_roll' => 1, 'celestial_roll' => 1 } );
    my $world = WorldGenerator::create( { seed => 1, 'astronomy' => $astro } );
    my $summary = WorldFormatter::printSkySummary($world);
    like(
        $summary,
        qr/^.* orbits a single star: .+\.\n.* also has no moons\.\nIn the night sky, you see nothing unusual\.\nDuring the day, the sky is .+\.\n$/
    );

    $astro = AstronomyGenerator::create(
        { seed => 1, 'starsystem_roll' => 1, 'moons_roll' => 31, 'celestial_roll' => 31 } );
    $world = WorldGenerator::create( { seed => 1, 'astronomy' => $astro } );
    $summary = WorldFormatter::printSkySummary($world);
    like( $summary,
        qr/^.* orbits a single star: .+\.\n.* also has a single moon: .+\.\nIn the night sky, you see a celestial object: .+\.\nDuring the day, the sky is .+\.\n$/
    );


    $astro = AstronomyGenerator::create(
        { seed => 1, 'starsystem_roll' => 71, 'moons_roll' => 71, 'celestial_roll' => 61 } );
    $world = WorldGenerator::create( { seed => 1, 'astronomy' => $astro } );
    $summary = WorldFormatter::printSkySummary($world);
    like( $summary,
        qr/^.* orbits a binary star: .+\.\n.* also has a double moon: .+\.\nIn the night sky, you see two celestial objects: .+\.\nDuring the day, the sky is .+\.\n$/
    );


    $astro = AstronomyGenerator::create(
        { seed => 1, 'starsystem_roll' => 97, 'moons_roll' => 96, 'celestial_roll' => 93 } );
    $world = WorldGenerator::create( { seed => 1, 'astronomy' => $astro } );
    $summary = WorldFormatter::printSkySummary($world);
    like(
        $summary,
        qr/^.* orbits a trinary star: .+\.\n.* also has a triple moon: .+\.\nIn the night sky, you see three celestial objects: .+\.\nDuring the day, the sky is .+\.\n$/
    );

    done_testing();
};


subtest 'Test World Land Summary' => sub {

    my $world = WorldGenerator::create( { seed => 1, } );
    my $summary = WorldFormatter::printLandSummary($world);
    is( $summary,
              "Macurto is 760,399,542 square kilometers (with a circumference of 48,870 kilometers).\n"
            . "Surface water is rare, covering 27% of the planet.\n"
            . "Around 52% of the planet's water is fresh water.\n"
            . "The crust is split into 8 plates, resulting in 2 continents.\n" );

    done_testing();
};


subtest 'Test World Weather Summary' => sub {
    my $world = WorldGenerator::create( { seed => 1, } );
    my $summary = WorldFormatter::printWeatherSummary($world);
    is(
        $summary,
        "While Macurto has a reasonable amount of variation, the overall climate is warm.\n"
            . "Small storms are common, precipitation is rare, the atmosphere is fragile and clouds are scarce.\n"

    );

    done_testing();
};


subtest 'Test World Data Summary' => sub {
    my $world = WorldGenerator::create( { seed => 1, } );
    my $summary = WorldFormatter::printWorldDataSummary($world);
    is(
        $summary, "    <ul>
        <li>Stars: 1</li>
        <li>Moons: 1</li>
        <li>Celestial Objects: 0</li>
        <li>Weather: warm</li>
        <li>Sky: brown</li>
        <li>Size: large</li>
        <li>Year: 188 days</li>
        <li>Day: 24 hours</li>
        <li>Oceans: 27%</li>
        <li>Fresh water: common</li>
    </ul>
"
    );

    done_testing();
};


done_testing();
1;
