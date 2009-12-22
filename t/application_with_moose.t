use strict;
use warnings;
use Test::Requires qw/Moose Test::Warn/;
use Test::More tests => 2;
use Test::Warn;

warning_is { use_ok 'Tatsumaki::Application'; } undef, 
           "No warnings with Moose";
