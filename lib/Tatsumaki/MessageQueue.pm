package Tatsumaki::MessageQueue;
use strict;
use Any::Moose;
use Try::Tiny;
use Scalar::Util;
use Time::HiRes;
use constant DEBUG => $ENV{TATSUMAKI_DEBUG};

has channel => (is => 'rw', isa => 'Str');
has backlog => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has clients => (is => 'rw', isa => 'HashRef', default => sub { +{} });

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

    for my $client_id (keys %{$self->clients}) {
        my $client = $self->clients->{$client_id};
        if ($client->{cv}->cb) {
            # currently listening: flush and send the events right away
            my @ev = (@{$client->{buffer}}, @events);
            $self->flush_events($client_id, @ev);
        } else {
            # between long poll comet: buffer the events
            # TODO: limit buffer length
            warn "Buffering new events for $client_id" if DEBUG;
            push @{$client->{buffer}}, @events;
        }
    }
    $self->append_backlog(@events);
}

sub flush_events {
    my($self, $client_id, @events) = @_;

    my $client = $self->clients->{$client_id} or return;
    try {
        my $cb = $client->{cv}->cb;
        $client->{cv}->send(@events);
        $client->{cv} = AE::cv;
        $client->{buffer} = [];

        if ($client->{persistent}) {
            $client->{cv}->cb($cb);
        } else {
            $client->{timer} = AE::timer 30, 0, sub {
                Scalar::Util::weaken $self;
                warn "Sweep $client_id (no long-poll reconnect)" if DEBUG;
                undef $client;
                delete $self->clients->{$client_id};
            };
        }
    } catch {
        /Tatsumaki::Error::ClientDisconnect/ and do {
            warn "Client $client_id disconnected" if DEBUG;
            undef $client;
            delete $self->clients->{$client_id};
        };
    };
}

sub poll_once {
    my($self, $client_id, $cb, $timeout) = @_;

    my $is_new;
    my $client = $self->clients->{$client_id} ||= do {
        $is_new = 1;
        + { cv => AE::cv, persistent => 0, buffer => [] };
    };

    $client->{cv}->cb(sub { $cb->($_[0]->recv) });

    # reset garbage collection timeout with the long-poll timeout
    # $timeout = 0 is a valid timeout for interval-polling
    $timeout = 55 unless defined $timeout;
    $client->{timer} = AE::timer $timeout || 55, 0, sub {
        Scalar::Util::weaken $self;
        warn "Timing out $client_id long-poll" if DEBUG;
        $self->flush_events($client_id);
    };

    # flush backlog for a new client
    if ($is_new) {
        my @events = $self->backlog_events;
        $self->flush_events($client_id, @events) if @events;
    }
}

sub poll {
    my($self, $client_id, $cb) = @_;

    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    my $s = $self->clients->{$client_id} = {
        cv => $cv, persistent => 1, buffer => [],
    };

    my @events = $self->backlog_events;
    $self->flush_events($client_id, @events) if @events;
}

1;
