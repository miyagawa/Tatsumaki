package Tatsumaki::MessageQueue;
use strict;
use Moose;
use Try::Tiny;
use Scalar::Util;

has channel  => (is => 'rw', isa => 'Str');
has backlog  => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has sessions => (is => 'rw', isa => 'HashRef', default => sub { +{} });

our $BacklogLength = 30; # TODO configurable

my %instances;

sub instance {
    my($class, $name) = @_;
    $instances{$name} ||= $class->new(channel => $name);
}

sub append_backlog {
    my($self, @events) = @_;
    my @new_backlog = (reverse(@events), @{$self->backlog});
    $self->backlog([ splice @new_backlog, 0, $BacklogLength ]);
}

sub publish {
    my($self, @events) = @_;

    for my $sid (keys %{$self->sessions}) {
        my $session = $self->sessions->{$sid};
        my $cb = $session->{cv}->cb;

        if ($cb) {
            # currently listening: flush and send the events right away
            my @ev = (@{$session->{buffer}}, @events);
            $self->flush_events($sid, @ev);
        } else {
            # between long poll comet: buffer the events
            # TODO: limit buffer length
            push @{$session->{buffer}}, @events;
        }

        if ($session->{persistent}) {
            $session->{cv}->cb($cb); # poll forever
        }
    }
    $self->append_backlog(@events);
}

sub flush_events {
    my($self, $sid, @events) = @_;

    my $session = $self->sessions->{$sid} or return;
    try {
        $session->{cv}->send(@events);
        $session->{cv} = AE::cv;
        $session->{buffer} = [];

        # no reconnection for 30 seconds: clear the session
        $session->{timer} = AE::timer 30, 0, sub {
            delete $self->sessions->{$sid};
        } unless $session->{persistent};
    } catch {
        /Tatsumaki::Error::ClientDisconnect/ and delete $self->sessions->{$sid};
    };
}

sub poll_once {
    my($self, $sid, $cb, $timeout) = @_;

    my $is_new;
    my $session = $self->sessions->{$sid} ||= do {
        $is_new = 1;
        + { cv => AE::cv, persistent => 0, buffer => [] };
    };

    $session->{cv}->cb(sub { $cb->($_[0]->recv) });

    # reset garbage collection timeout with the long-poll timeout
    $session->{timer} = AE::timer $timeout || 55, 0, sub {
        Scalar::Util::weaken $self;
        $self->flush_events($sid);
    };

    # flush backlog for a new session
    if ($is_new) {
        my @events = reverse grep defined, @{$self->backlog};
        $self->flush_events($sid, @events) if @events;
    }
}

sub poll {
    my($self, $sid, $cb) = @_;
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    $self->sessions->{$sid} = {
        cv => $cv, persistent => 1, buffer => [],
    };
}

1;
