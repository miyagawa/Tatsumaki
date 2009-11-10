package Tatsumaki::MessageQueue;
use strict;
use Moose;
use Try::Tiny;
use Scalar::Util;
use Time::HiRes;
use constant DEBUG => $ENV{TATSUMAKI_DEBUG};

has channel  => (is => 'rw', isa => 'Str');
has backlog  => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has sessions => (is => 'rw', isa => 'HashRef', default => sub { +{} });

our $BacklogLength = 30; # TODO configurable

my %instances;

sub instance {
    my($class, $name) = @_;
    $instances{$name} ||= $class->new(channel => $name);
}

sub backlog_events {
    my $self = shift;
    reverse grep defined, @{$self->backlog};
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
        if ($session->{cv}->cb) {
            # currently listening: flush and send the events right away
            my @ev = (@{$session->{buffer}}, @events);
            $self->flush_events($sid, @ev);
        } else {
            # between long poll comet: buffer the events
            # TODO: limit buffer length
            warn "Buffering new events for $sid" if DEBUG;
            push @{$session->{buffer}}, @events;
        }
    }
    $self->append_backlog(@events);
}

sub flush_events {
    my($self, $sid, @events) = @_;

    my $session = $self->sessions->{$sid} or return;
    try {
        my $cb = $session->{cv}->cb;
        $session->{cv}->send(@events);
        $session->{cv} = AE::cv;
        $session->{buffer} = [];

        if ($session->{persistent}) {
            $session->{cv}->cb($cb);
        } else {
            $session->{timer} = AE::timer 30, 0, sub {
                Scalar::Util::weaken $self;
                warn "Sweep $sid (no long-poll reconnect)" if DEBUG;
                undef $session;
                delete $self->sessions->{$sid};
            };
        }
    } catch {
        /Tatsumaki::Error::ClientDisconnect/ and do {
            warn "Client $sid disconnected" if DEBUG;
            undef $session;
            delete $self->sessions->{$sid};
        };
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
        warn "Timing out $sid long-poll" if DEBUG;
        $self->flush_events($sid);
    };

    # flush backlog for a new session
    if ($is_new) {
        my @events = $self->backlog_events;
        $self->flush_events($sid, @events) if @events;
    }
}

sub poll {
    my($self, $sid, $cb) = @_;

    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    my $s = $self->sessions->{$sid} = {
        cv => $cv, persistent => 1, buffer => [],
    };

    my @events = $self->backlog_events;
    $self->flush_events($sid, @events) if @events;
}

1;
