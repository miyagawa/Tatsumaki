package HelloApp;
use base qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    Tatsumaki::Error::HTTP->throw(500, "Oops");
}

package AsyncApp;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
    my $self = shift;
    Tatsumaki::Error::HTTP->throw(500, "Oops");
}


package AsyncDelayedApp;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
    my $self = shift;
    my $t; $t = AE::timer 0, 0, $self->safe_cb(sub {
        Tatsumaki::Error::HTTP->throw(500, "Oops");
        undef $t;
    });
}

package main;
use Plack::Test;
use Test::More;
use HTTP::Request::Common;
use Tatsumaki::Application;
$Plack::Test::Impl = "Server";

my $app = Tatsumaki::Application->new([
    '/hello'  => 'HelloApp',
    '/async2' => 'AsyncDelayedApp',
    '/async'  => 'AsyncApp',
]);

test_psgi app => $app, client => sub {
    my $cb = shift;

    my $res = $cb->(GET "http://localhost/hello");
    is $res->code, 500;
    is $res->content, 'Oops';

    $res = $cb->(GET "http://localhost/async");
    is $res->code, 500;
    is $res->content, 'Oops';

    $res = $cb->(GET "http://localhost/async2");
    is $res->code, 500;
    is $res->content, 'Oops';
};

done_testing;
