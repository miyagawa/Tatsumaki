#!/usr/bin/perl
use strict;
use warnings;
use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::HTTPClient;
use JSON;

package MainHandler;
use base qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->write("Hello World");
}

package StreamWriter;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
    my $self = shift;
    $self->response->content_type('text/plain');

    my $try = 0;
    my $t; $t = AE::timer 0, 0.1, sub {
        $self->stream_write("Current UNIX time is " . time . "\n");
        if ($try++ >= 10) {
            undef $t;
            $self->finish;
        }
    };
}

package FeedHandler;
use base qw(Tatsumaki::Handler);

__PACKAGE__->asynchronous(1);

sub get {
    my($self, $query) = @_;
    my $client = Tatsumaki::HTTPClient->new;
    $client->get("http://friendfeed-api.com/v2/feed/$query", $self->async_cb(sub { $self->on_response(@_) }));
}

sub on_response {
    my($self, $res) = @_;
    if ($res->is_error) {
        Tatsumaki::Error::HTTP->throw(500, $res->status_line);
    }
    my $json = JSON::decode_json($res->content);

    $self->response->content_type('text/html;charset=utf-8');
    $self->write("<p>Fetched " . scalar(@{$json->{entries}}) . " entries from API</p>");
    for my $entry (@{$json->{entries}}) {
        $self->write("<li>" . $entry->{body} . "</li>\n");
    }
    $self->finish;
}

package main;
use File::Basename;

my $app = Tatsumaki::Application->new([
    '/stream' => 'StreamWriter',
    '/feed/(\w+)' => 'FeedHandler',
    '/' => 'MainHandler',
]);

if (__FILE__ eq $0) {
    require Tatsumaki::Server;
    Tatsumaki::Server->new(port => 9999)->run($app);
} else {
    return $app;
}
