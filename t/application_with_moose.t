use strict;
use warnings;
use Test::More tests => 2;
use Test::Warn;
use Test::Requires qw/Moose/;

warning_is { use_ok 'Tatsumaki::Application'; } undef, 
           "No warnings with Moose";
