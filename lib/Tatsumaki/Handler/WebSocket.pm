package Tatsumaki::Handler::WebSocket;
use strict;
use Any::Moose;
extends 'Tatsumaki::Handler';

use Encode;
use JSON;
use Tatsumaki;
use Tatsumaki::Error;
use Scalar::Util;

has _handle => (is => 'rw', isa => 'AnyEvent::Handle');

sub get {
    my $self = shift;

    unless ($self->is_asynchronous && $self->request->env->{'psgi.nonblocking'}) {
        Tatsumaki::DEBUG && $self->debug("asynchrnous(1) should be set");
        Tatsumaki::Error::HTTP->throw(405);
    }

    my $env = $self->request->env;

    unless (    $env->{HTTP_CONNECTION} eq 'Upgrade'
            and $env->{HTTP_UPGRADE} eq 'WebSocket'
            and $env->{HTTP_ORIGIN} ) {
        Tatsumaki::Error::HTTP->throw(400, "WebSocket Upgrade headers expected");
    }

    my $handshake = join "\015\012",
        "HTTP/1.1 101 Web Socket Protocol Handshake",
        "Upgrade: WebSocket",
        "Connection: Upgrade",
        "WebSocket-Origin: $env->{HTTP_ORIGIN}",
        "WebSocket-Location: ws://$env->{HTTP_HOST}$env->{SCRIPT_NAME}$env->{PATH_INFO}",
        '', '';

    my $fh = $env->{'psgix.io'}
        or Tatsumaki::Error::HTTP->throw(501, "This server does not support psgix.io extension");

    my $h = AnyEvent::Handle->new( fh => $fh );
    $h->on_error(sub {
        warn 'err: ', $_[2];
        undef $h;
        # TODO raise client disconnect?
    });

    $h->push_write($handshake);

    $h->on_read(sub {
        $_[0]->push_read( line => "\xff", sub {
            my ($h, $data) = @_;
            $data =~ s/^\0//;
            Scalar::Util::weaken $self;
            $self->on_receive_message($data);
        });
    });

    $self->_handle($h);
    $self->open;
}

sub on_receive_message {
    my($self, $message) = @_;
    Tatsumaki::DEBUG && $self->debug("Received $message");
}

sub get_chunk {
    my $self = shift;
    if (ref $_[0]) {
        JSON::encode_json $_[0];
    } else {
        Encode::encode_utf8 $_[0];
    }
}

sub stream_write {
    shift->write(@_);
}

sub write {
    my $self = shift;
    my $message = $self->get_chunk(@_);
    Tatsumaki::DEBUG && $self->debug("Writing $message");
    $self->_handle->push_write("\x00" . $message . "\xff");
}

sub finish {
    my $self = shift;
    $self->_handle->push_shutdown;
    $self->_handle(undef);
}

sub open {
    my $self = shift;
    Tatsumaki::DEBUG && $self->debug("open() is not implemented in " . ref($self) . ". Doing nothing");
}

1;

__END__

=head1 NAME

Tatsumaki::Handler::WebSocket - WebSocket handler base class

=head1 SYNOPSIS

  package MyApp::Handler::WebSocketEcho;
  use parent qw(Tatsumaki::Handler::WebSocket);

  sub open {
      my $self = shift;
      # handshake is done. register event callbacks: push
  }

  sub on_receive_message {
      my($self, $message) = @_;
      # fired whenever you receive message from clients: pull
      $self->write("You said: " . $message);
  }

=head1 SEE ALSO

L<Tatsumaki>

=cut
