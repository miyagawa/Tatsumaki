use Plack::Test;
use Test::More;
use HTTP::Request::Common;
use Tatsumaki::Application;

package HelloApp;
use base qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->write("Hello World");
}

package main;
my $app = Tatsumaki::Application->new([ '/' => 'HelloApp' ]);

test_psgi $app, sub {
    my $cb = shift;
    my $res = $cb->(GET "http://localhost/");
    ok $res->is_success;
    is $res->code, 200;
    is $res->content, 'Hello World';

    $res = $cb->(GET "http://localhost/foo");
    is $res->code, 404;

    $res = $cb->(POST "http://localhost/");
    is $res->code, 405;
};

done_testing;
