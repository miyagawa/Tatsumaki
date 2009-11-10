package Tatsumaki::Service::XMPP;
use Moose;
extends 'Tatsumaki::Service';

use constant DEBUG => $ENV{TATSUMAKI_XMPP_DEBUG};

use AnyEvent::XMPP::Client;
use Carp ();
use HTTP::Request::Common;
use HTTP::Message::PSGI;
use namespace::clean -except => 'meta';

has jid      => (is => 'rw', isa => 'Str');
has password => (is => 'rw', isa => 'Str');
has xmpp     => (is => 'rw', isa => 'AnyEvent::XMPP::Client', lazy_build => 1);

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    if (@_ == 2) {
        $class->$orig(jid => $_[0], password => $_[1]);
    } else {
        $class->$orig(@_);
    }
};

sub _build_xmpp {
    my $self = shift;
    my $xmpp = AnyEvent::XMPP::Client->new(debug => DEBUG);
    $xmpp->add_account($self->jid, $self->password);
    $xmpp->reg_cb(
        error => sub { Carp::croak @_ },
        message => sub {
            my($client, $acct, $msg) = @_;

            return unless $msg->any_body;

            # TODO refactor this
            my $req = POST "/_services/xmpp/chat", [ from => $msg->from, to => $acct->jid, body => $msg->body ];
            my $env = $req->to_psgi;
            $env->{'tatsumaki.xmpp'} = {
                client  => $client,
                account => $acct,
                message => $msg,
            };
            $env->{'psgi.streaming'} = 1;

            my $res = $self->application->($env);
            $res->(sub { my $res = shift }) if ref $res eq 'CODE';
        },
        contact_request_subscribe => sub {
            my($client, $acct, $roster, $contact) = @_;
            $contact->send_subscribed;

            my $req = POST "/_services/xmpp/subscribe", [ from => $contact->jid, to => $acct->jid ];
            my $env = $req->to_psgi;
            $env->{'tatsumaki.xmpp'} = {
                client  => $client,
                account => $acct,
                contact => $contact,
            };
            $env->{'psgi.streaming'} = 1;

            my $res = $self->application->($env);
            $res->(sub { my $res = shift }) if ref $res eq 'CODE';
        },
    );
    $xmpp;
}

sub start {
    my($self, $application) = @_;
    $self->xmpp->start;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
