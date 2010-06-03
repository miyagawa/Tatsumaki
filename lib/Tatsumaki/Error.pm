package Tatsumaki::Error;
use strict;
use Any::Moose;

sub throw {
    my($class, @rest) = @_;
    die $class->new(@rest);
}

package Tatsumaki::Error::ClientDisconnect;
use Any::Moose;
extends 'Tatsumaki::Error';

package Tatsumaki::Error::HTTP;
use Any::Moose;
use HTTP::Status;
extends 'Tatsumaki::Error';

use overload q("") => sub { $_[0]->message }, fallback => 1;
has code => (is => 'rw', isa => 'Int');
has content_type => (is => 'rw', isa => 'Str', default => 'text/plain');
has message => (is => 'rw', isa => 'Str');

around BUILDARGS => sub {
    my $orig = shift;
    my($class, $code, $msg, $ct) = @_;
    $msg ||= HTTP::Status::status_message($code);
    $class->$orig(code => $code, content_type => ($ct // 'text/plain'), message => $msg);
};

package Tatsumaki::Error;

1;

