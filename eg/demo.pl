#!/usr/bin/perl
use strict;
use warnings;
use Tatsumaki;
use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::HTTPClient;
use Tatsumaki::Server;
use JSON;

package MainHandler;
use base qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->write("Hello World");
}

package SearchHandler;
use base qw(Tatsumaki::Handler);

__PACKAGE__->nonblocking(1);

sub get {
    my($self, $query) = @_;
    my $client = Tatsumaki::HTTPClient->new;
    $client->get("http://friendfeed-api.com/v2/feed/$query", sub { $self->on_response(@_) });
}

sub on_response {
    my($self, $res) = @_;
    if ($res->is_error) {
        Tatsumaki::Error::HTTP->throw(500);
    }
    my $json = JSON::decode_json($res->content);

    $self->response->content_type('text/html;charset=utf-8');
    $self->write("<p>Fetched " . scalar(@{$json->{entries}}) . " entries from API</p>");
    for my $entry (@{$json->{entries}}) {
        $self->write("<li>" . $entry->{body} . "</li>");
    }
    $self->finish;
}

package main;

my $app = Tatsumaki::Application->new([
    '/feed/(\w+)' => 'SearchHandler',
    '/' => 'MainHandler',
]);

Tatsumaki::Server->new(port => 9999)->run($app);
