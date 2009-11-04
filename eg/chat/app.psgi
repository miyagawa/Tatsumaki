use strict;
use warnings;
use Tatsumaki::Error;
use Tatsumaki::Application;

package ChatPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

use Tatsumaki::MessageQueue;

sub get {
    my($self, $channel) = @_;
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    my $session = $self->request->param('session')
        or Tatsumaki::Error::HTTP->throw(500, "'session' needed");
    $session = rand(1) if $session eq 'dummy'; # for benchmarking stuff
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
use Encode;

sub post {
    my($self, $channel) = @_;

    my $v = $self->request->params;
    my $html = $self->format_message($v->{text});
    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->publish({
        type => "message", html => $html, ident => $v->{ident},
        avatar => $v->{avatar}, name => $v->{name},
        address => $self->request->address,
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

package ChatRoomHandler;
use base qw(Tatsumaki::Handler);

sub get {
    my($self, $channel) = @_;
    $self->render('chat.html');
}

package main;
use File::Basename;

my $chat_re = '[\w\.\-]+';
my $app = Tatsumaki::Application->new([
    "/chat/($chat_re)/poll" => 'ChatPollHandler',
    "/chat/($chat_re)/mxhrpoll" => 'ChatMultipartPollHandler',
    "/chat/($chat_re)/post" => 'ChatPostHandler',
    "/chat/($chat_re)" => 'ChatRoomHandler',
]);

$app->template_path(dirname(__FILE__) . "/templates");
$app->static_path(dirname(__FILE__) . "/static");

# TODO these should be an external services module
use Try::Tiny;
our @svc;
if ($ENV{TWITTER_USERNAME}) {
    my $tweet_cb = sub {
        my $channel = shift;
        my $mq = Tatsumaki::MessageQueue->instance($channel);
        return sub {
            my $tweet = shift;
            return unless $tweet->{user}{screen_name};
            $mq->publish({
                type   => "message", address => 'twitter.com',
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
        push @svc, $listener;
    }

    if (try { require AnyEvent::Twitter }) {
        my $cb = $tweet_cb->("twitter_friends");
        my $client = AnyEvent::Twitter->new(
            username => $ENV{TWITTER_USERNAME},
            password => $ENV{TWITTER_PASSWORD},
        );
        $client->reg_cb(statuses_friends => sub {
            my $self = shift;
            for (@_) { $cb->($_->[1]) }
        });
        $client->receive_statuses_friends;
        $client->start;
        warn "Twitter Friends timeline is available at /chat/twitter_friends\n";
        push @svc, $client;
    }
}

if ($ENV{FRIENDFEED_USERNAME} && try { require AnyEvent::FriendFeed::Realtime }) {
    my $mq = Tatsumaki::MessageQueue->instance("friendfeed");
    my $entry_cb = sub {
        my $entry = shift;
        $mq->publish({
            type => "message", address => 'friendfeed.com',
            name => $entry->{from}{name},
            avatar => "http://friendfeed-api.com/v2/picture/$entry->{from}{id}",
            html => $entry->{body},
            ident => $entry->{url},
        });
    };
    my $client; $client = AnyEvent::FriendFeed::Realtime->new(
        request => "/feed/$ENV{FRIENDFEED_USERNAME}/friends",
        on_entry => $entry_cb,
        on_error => sub { undef $client },
    );
    warn "FriendFeed stream is available at /chat/friendfeed\n";
    push @svc, $client;
}

if ($ENV{SUPERFEEDR_JID} && try { require AnyEvent::Superfeedr }) {
    $XML::Atom::ForceUnicode = 1;
    my $mq = Tatsumaki::MessageQueue->instance("superfeedr");
    my $entry_cb = sub {
        my($entry, $feed_uri) = @_;
        my $host = URI->new($feed_uri)->host;
        $mq->publish({
            type => "message", address => $host,
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
            my $notification = shift;
            for my $entry ($notification->entries) {
                $entry_cb->($entry, $notification->feed_uri);
            }
        },
    );
    warn "Superfeedr channel is available at /chat/superfeedr\n";
    push @svc, $superfeedr;
}

if ($ENV{ATOM_STREAM} && try { require AnyEvent::Atom::Stream }) {
    my $mq = Tatsumaki::MessageQueue->instance("sixapart");
    my $entry_cb = sub {
        my $feed = shift;
        my $host = URI->new($feed->link->href)->host;
        for my $entry ($feed->entries) {
            $mq->publish({
                type => "message", address => $host,
                name => $feed->title,
                avatar => "http://www.google.com/s2/favicons?domain=$host",
                html  => $entry->title,
                ident => $entry->link->href,
            });
        }
    };
    my $client; $client = AnyEvent::Atom::Stream->new(
        callback => $entry_cb,
        on_disconnect => sub { undef $client },
    );
    $client->connect("http://updates.sixapart.com/atom-stream.xml");
    warn "Six Apart update stream is available at /chat/sixapart\n";
    push @svc, $client;
}

if ($ENV{IRC_NICK} && $ENV{IRC_SERVER} && try { require AnyEvent::IRC::Client }) {
    my($host, $port) = split /:/, $ENV{IRC_SERVER};
    my $irc = AnyEvent::IRC::Client->new;
    $irc->reg_cb(disconnect => sub { warn @_; undef $irc });
    $irc->reg_cb(publicmsg => sub {
        my($con, $channel, $packet) = @_;
        $channel =~ s/\@.*$//; # bouncer (tiarra)
        $channel =~ s/^#//;
        if ($packet->{command} eq 'NOTICE' || $packet->{command} eq 'PRIVMSG') { # NOTICE for bouncer backlog
            my $msg = $packet->{params}[1];
            (my $who = $packet->{prefix}) =~ s/\!.*//;
            my $mq = Tatsumaki::MessageQueue->instance($channel);
            $mq->publish({
                type => "message", address => $host,
                name => $who,
                ident => "$who\@gmail.com", # let's just assume everyone's gmail :)
                text => Encode::decode_utf8($msg),
            });
        }
    });
    $irc->connect($host, $port || 6667, { nick => $ENV{IRC_NICK}, password => $ENV{IRC_PASSWORD} });
    push @svc, $irc;
}

return $app;
