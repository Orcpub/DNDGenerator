#!/usr/bin/perl -wT
###############################################################################
#
package TestCritterFormatter;

use strict;
use warnings;

use CritterGenerator;
use Data::Dumper;
use Exporter;
use CritterFormatter;
use Test::More;
use XML::Simple;

use vars qw(@ISA @EXPORT_OK $VERSION $XS_VERSION $TESTING_PERL_ONLY);
use base qw(Exporter);
@EXPORT_OK = qw( );


subtest 'Test Critter Summary' => sub {
    my $critter = CritterGenerator::create( { seed => 1 } );
    my $crittertext = CritterFormatter::printSummary($critter);
    # printSummary() emits exactly two sentences, "The <name> is <a|an> <terror>
    # <basecritter> that <diet>." and "Adventurers should be wary of its <attacktype>
    # <attack>, and it's reported <ability>.", and it ends every one of them with
    # "\n " (a newline plus a space), so the trailing "\n " is part of the contract.
    # The article comes from Lingua::EN::Inflect::A(), which returns "a" or "an"
    # depending on the terror word, so only "an?" is required here. Name, terror,
    # basecritter, diet, attacktype, attack and ability are all generated, and the
    # generated phrases run to a random number of words, so those are the wildcards.
    like(
        $crittertext,
        qr{^The .+ is an? .+ .+ that .+\.\n Adventurers should be wary of its .+ .+, and it's reported .+\.\n $}
    );
    done_testing();
};

subtest 'Test Critter Description' => sub {
    my $critter = CritterGenerator::create( { seed => 1 } );
    $critter->{'covering'}=undef;
    $critter->{'subtype'}=undef;
    my $crittertext = CritterFormatter::printDescription($critter);
    like($crittertext,"/The .+ appears to be a?? .+ .+ that .+\.\n /"       );
    like($crittertext,"/It .+ with its .+\.\n When confronted, it .+\.\n/"  );

    $critter->{'covering'}="hair";
    $critter->{'subtype'}="is a dog";
    $crittertext = CritterFormatter::printDescription($critter);
    like($crittertext,"/The .+ appears to be a?? .+ .+ that .+\.\n /"       );
    like($crittertext,"/Its .+ body is covered with .+, .+ .+\.\n It .+\.\n /"       );
    like($crittertext,"/It .+ with its .+\.\n When confronted, it .+\.\n/"  );

    done_testing();
};
subtest 'Test Critter Data' => sub {
    my $critter = CritterGenerator::create( { seed => 1 } );
    my $crittertext = CritterFormatter::printData($critter);
    is($crittertext, "");
    done_testing();
};

done_testing();
1;
