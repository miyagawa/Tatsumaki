package CaptureApp;
use base qw(Tatsumaki::Handler);

sub get {
    my ($self, @params) = @_;
    $self->response->content_type('text/plain; charset=latin-1');
    $self->write(scalar @params);
}

package main;
use Plack::Test;
use Test::More;
use HTTP::Request::Common;
use Tatsumaki::Application;
$Plack::Test::Impl = "Server";

my $app = Tatsumaki::Application->new([
    '/capture/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/([^/]+)/'  => 'CaptureApp',
]);

test_psgi $app, sub {
    my $cb = shift;

    my $res = $cb->(GET "http://localhost/capture/1/2/3/4/5/6/7/8/9/10/");
    is $res->content, "10";
};

done_testing;
