#!/usr/bin/perl
use strict;
use warnings;
use Tatsumaki;
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
__PACKAGE__->nonblocking(1);

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

__PACKAGE__->nonblocking(1);

sub get {
    my($self, $query) = @_;
    my $client = Tatsumaki::HTTPClient->new;
    $client->get("http://friendfeed-api.com/v2/feed/$query", sub { $self->on_response(@_) });
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

package ChatPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->nonblocking(1);

use Tatsumaki::MessageQueue;

sub get {
    my($self, $channel) = @_;
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->poll_once(sub { $self->on_new_event(@_) });
}

sub on_new_event {
    my($self, @events) = @_;
    $self->write(\@events);
    $self->finish;
}

package ChatMultipartPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->nonblocking(1);

sub get {
    my($self, $channel) = @_;
    my $mq = Tatsumaki::MessageQueue->instance($channel);

    $self->multipart_xhr_push(1);

    $mq->poll(sub {
        my @events = @_;
        for my $event (@events) {
            $self->stream_write($event);
        }
    });
}

package ChatPostHandler;
use base qw(Tatsumaki::Handler);

sub post {
    my($self, $channel) = @_;

    # TODO: decode should be done in the framework or middleware
    my $v = $self->request->params;
    my $text  = Encode::decode_utf8($v->{text});
    my $email = $v->{email};
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->publish({
        type => "message", text => $text, email => $email,
        avatar => $v->{avatar}, name => $v->{name},
        address => $self->request->address, time => scalar localtime(time),
    });
    $self->write({ success => 1 });
}

package ChatBacklogHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->nonblocking(1);

sub get {
    my($self, $channel) = @_;

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->poll_backlog(20, sub {
        my @events = @_;
        $self->write(\@events);
        $self->finish;
    });
}

package ChatRoomHandler;
use base qw(Tatsumaki::Handler);

sub get {
    my($self, $channel) = @_;
    $self->render('chat.html');
}

package main;
use File::Basename;

my $app = Tatsumaki::Application->new([
    '/stream' => 'StreamWriter',
    '/feed/(\w+)' => 'FeedHandler',
    '/chat/(\w+)/poll'  => 'ChatPollHandler',
    '/chat/(\w+)/mxhrpoll'  => 'ChatMultipartPollHandler',
    '/chat/(\w+)/post'  => 'ChatPostHandler',
    '/chat/(\w+)/backlog' => 'ChatBacklogHandler',
    '/chat/(\w+)' => 'ChatRoomHandler',
    '/' => 'MainHandler',
]);

$app->template_path(dirname(__FILE__) . "/templates");

# TODO this should be part of core
use Plack::Middleware::Static;
$app = Plack::Middleware::Static->wrap($app, path => qr/^\/static/, root => dirname(__FILE__));

if (__FILE__ eq $0) {
    require Tatsumaki::Server;
    Tatsumaki::Server->new(port => 9999)->run($app);
} else {
    return $app;
}

