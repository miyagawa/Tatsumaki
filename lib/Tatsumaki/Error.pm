package Tatsumaki::Error;
use strict;
use Moose;
with 'Throwable';

package Tatsumaki::Error::ClientDisconnect;
use Moose;
extends 'Tatsumaki::Error';

package Tatsumaki::Error::HTTP;
use Moose;
use HTTP::Status;
extends 'Tatsumaki::Error';

use overload q("") => sub { $_[0]->message }, fallback => 1;
has code => (is => 'rw', isa => 'Int');
has message => (is => 'rw', isa => 'Str');

around BUILDARGS => sub {
    my $orig = shift;
    my($class, $code, $msg) = @_;
    $msg ||= HTTP::Status::status_message($code);
    $class->$orig(code => $code, message => $msg);
};

package Tatsumaki::Error;

1;

