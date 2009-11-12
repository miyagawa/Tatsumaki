package Tatsumaki::HTTPClient;
use strict;
use AnyEvent::HTTP ();
use HTTP::Request::Common ();
use HTTP::Request;
use HTTP::Response;
use Tatsumaki;
use Any::Moose;

has timeout => (is => 'rw', isa => 'Int', default => sub { 30 });
has agent   => (is => 'rw', isa => 'Str', default => sub { join "/", __PACKAGE__, $Tatsumaki::VERSION });

sub get    { _request(GET => @_) }
sub head   { _request(HEAD => @_) }
sub post   { _request(POST => @_) }
sub put    { _request(PUT => @_) }
sub delete { _request(DELETE => @_) }

sub _request {
    my $cb     = pop;
    my $method = shift;
    my $self   = shift;
    no strict 'refs';
    my $req = &{"HTTP::Request::Common::$method"}(@_);
    $self->request($req, $cb);
}

sub request {
    my($self, $request, $cb) = @_;

    my $headers = $request->headers;
    $headers->{'user-agent'} = $self->agent;

    my %options = (
        timeout => $self->timeout,
        headers => $headers,
        body    => $request->content,
    );

    AnyEvent::HTTP::http_request $request->method, $request->uri, %options, sub {
        my($body, $header) = @_;
        my $res = HTTP::Response->new($header->{Status}, $header->{Reason}, [ %$header ], $body);
        $cb->($res);
    };
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
