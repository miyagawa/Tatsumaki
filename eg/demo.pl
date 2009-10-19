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
__PACKAGE__->asynchronous(1);

use Tatsumaki::MessageQueue;

sub get {
    my($self, $channel) = @_;
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    my $session = $self->request->param('session')
        or Tatsumaki::Error::HTTP->throw(500, "'session' needed");
    $mq->poll_once($session, sub { $self->on_new_event(@_) });
}

sub on_new_event {
    my($self, @events) = @_;
    $self->write(\@events);
    $self->finish;
}

package ChatMultipartPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
    my($self, $channel) = @_;

    my $session = $self->request->param('session')
        or Tatsumaki::Error::HTTP->throw(500, "'session' needed");

    $self->multipart_xhr_push(1);

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->poll($session, sub {
        my @events = @_;
        for my $event (@events) {
            $self->stream_write($event);
        }
    });
}

package ChatPostHandler;
use base qw(Tatsumaki::Handler);
use HTML::Entities;

sub post {
    my($self, $channel) = @_;

    # TODO: decode should be done in the framework or middleware
    my $v = $self->request->params;
    my $text = Encode::decode_utf8($v->{text});
    my $html = $self->format_message($text);
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->publish({
        type => "message", html => $html, ident => $v->{ident},
        avatar => $v->{avatar}, name => $v->{name},
        address => $self->request->address, time => scalar localtime(time),
    });
    $self->write({ success => 1 });
}

sub format_message {
    my($self, $text) = @_;
    $text =~ s{ (https?://\S+) | ([&<>"']+) }
              { $1 ? do { my $url = HTML::Entities::encode($1); qq(<a target="_blank" href="$url">$url</a>) } :
                $2 ? HTML::Entities::encode($2) : '' }egx;
    $text;
}

package ChatBacklogHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

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

# TODO should this be in Server
use Plack::Middleware::Writer;
$app = Plack::Middleware::Writer->wrap($app);

# TODO this should be an external services module
use Try::Tiny;
if ($ENV{TWITTER_USERNAME}) {
    my $tweet_cb = sub {
        my $channel = shift;
        my $mq = Tatsumaki::MessageQueue->instance($channel);
        return sub {
            my $tweet = shift;
            return unless $tweet->{user}{screen_name};
            $mq->publish({
                type   => "message", address => 'twitter.com', time => scalar localtime,
                name   => $tweet->{user}{name},
                avatar => $tweet->{user}{profile_image_url},
                html   => ChatPostHandler->format_message($tweet->{text}), # FIXME
                ident  => "http://twitter.com/$tweet->{user}{screen_name}/status/$tweet->{id}",
            });
        };
    };

    if (try { require AnyEvent::Twitter::Stream }) {
        my $listener; $listener = AnyEvent::Twitter::Stream->new(
            username => $ENV{TWITTER_USERNAME},
            password => $ENV{TWITTER_PASSWORD},
            method   => "sample",
            on_tweet => $tweet_cb->("twitter"),
            on_eof => sub { undef $listener },
        );
        warn "Twitter stream is available at /chat/twitter\n";
    }

    if (try { require AnyEvent::Twitter }) {
        my $cb = $tweet_cb->("twitter_friends");
        my $client = AnyEvent::Twitter->new(
            username => $ENV{TWITTER_USERNAME},
            password => $ENV{TWITTER_PASSWORD},
        );
        $client->reg_cb(statuses_friends => sub {
            scalar $client;
            my $self = shift;
            for (@_) { $cb->($_->[1]) }
        });
        $client->receive_statuses_friends;
        $client->start;
        warn "Twitter Friends timeline is available at /chat/twitter_friends\n";
    }
}

if ($ENV{FRIENDFEED_USERNAME} && try { require AnyEvent::FriendFeed::Realtime }) {
    my $mq = Tatsumaki::MessageQueue->instance("friendfeed");
    my $entry_cb = sub {
        my $entry = shift;
        $mq->publish({
            type => "message", address => 'friendfeed.com', time => scalar localtime,
            name => $entry->{from}{name},
            avatar => "http://friendfeed-api.com/v2/picture/$entry->{from}{id}",
            html => $entry->{body},
            ident => $entry->{url},
        });
    };
    my $client; $client = AnyEvent::FriendFeed::Realtime->new(
        request => "/feed/$ENV{FRIENDFEED_USERNAME}/friends",
        on_entry => $entry_cb,
        on_error => sub { $client },
    );
    warn "FriendFeed stream is available at /chat/friendfeed\n";
}

if ($ENV{SUPERFEEDR_JID} && try { require AnyEvent::Superfeedr }) {
    $XML::Atom::ForceUnicode = 1;
    my $mq = Tatsumaki::MessageQueue->instance("superfeedr");
    my $entry_cb = sub {
        my($entry, $feed_uri) = @_;
        warn $feed_uri;
        my $host = URI->new($feed_uri)->host;
        $mq->publish({
            type => "message", address => $host, time => scalar localtime,
            name => $entry->title,
            avatar => "http://www.google.com/s2/favicons?domain=$host",
            html  => $entry->summary,
            ident => $entry->link->href,
        });
    };
    my $superfeedr; $superfeedr = AnyEvent::Superfeedr->new(
        debug => 0,
        jid => $ENV{SUPERFEEDR_JID},
        password => $ENV{SUPERFEEDR_PASSWORD},
        on_notification => sub {
            scalar $superfeedr;
            my $notification = shift;
            for my $entry ($notification->entries) {
                $entry_cb->($entry, $notification->feed_uri);
            }
        },
    );
    warn "Superfeedr channel is available at /chat/superfeedr\n";
}

if (__FILE__ eq $0) {
    require Tatsumaki::Server;
    Tatsumaki::Server->new(port => 9999)->run($app);
} else {
    return $app;
}
