package BinaryApp;
use base qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    my $binary = "foo\xdabar";
    $self->binary(1);
    $self->response->content_type('text/plain; charset=latin-1');
    $self->write($binary);
}

package main;
use Plack::Test;
use Test::More;
use HTTP::Request::Common;
use Tatsumaki::Application;
$Plack::Test::Impl = "Server";

my $app = Tatsumaki::Application->new([
    '/binary'  => 'BinaryApp',
]);

test_psgi $app, sub {
    my $cb = shift;

    my $res = $cb->(GET "http://localhost/binary");
    is $res->content, "foo\xdabar";
    is length $res->content, 7;
};

done_testing;
