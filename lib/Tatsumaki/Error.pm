package Tatsumaki::Error;
use strict;
use Moose;
with 'Throwable';

package Tatsumaki::Error::HTTP;
use Moose;
use HTTP::Status;
extends 'Tatsumaki::Error';

has code => (is => 'rw', isa => 'Int');

around BUILDARGS => sub {
    my $orig = shift;
    my($class, $code) = @_;
    $class->$orig(code => $code);
};

package Tatsumaki::Error;

1;

