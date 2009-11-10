#!/usr/bin/perl
use strict;
use warnings;
use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::HTTPClient;
use JSON;

package XMPPHandler;
use base qw(Tatsumaki::Handler::XMPP);
__PACKAGE__->asynchronous(1);

use JSON;
use URI;

sub post {
    my $self = shift;

    my $message = $self->xmpp_message;

    my $uri = URI->new("http://ajax.googleapis.com/ajax/services/language/translate");
    $uri->query_form(v => "1.0", langpair => "en|ja", q => $message->body);

    my $client = Tatsumaki::HTTPClient->new;
    $client->get($uri, $self->async_cb(sub { $self->on_response($message, @_) }));
}

sub on_response {
    my($self, $message, $res) = @_;
    my $result = JSON::decode_json($res->content);
    my $text   = $result->{responseData}{translatedText};

    $message->reply($text);
    $self->finish;
}

package main;
use Tatsumaki::Service::XMPP;

my $svc = Tatsumaki::Service::XMPP->new(
    $ENV{XMPP_JID}, $ENV{XMPP_PASSWORD},
);

my $app = Tatsumaki::Application->new([
    '/_services/xmpp/chat' => 'XMPPHandler',
]);

$app->add_service($svc);
$app;
