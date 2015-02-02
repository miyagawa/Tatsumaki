package Tatsumaki::Service;
use strict;
use warnings;

use Any::Moose;

has application => (is => 'rw', isa => 'Tatsumaki::Application', weak_ref => 1);

1;
