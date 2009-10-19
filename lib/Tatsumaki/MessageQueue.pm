package Tatsumaki::MessageQueue;
use strict;
use Moose;

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

sub poll_backlog {
    my($self, $length, $cb) = @_;
    my @events = grep defined, @{$self->backlog}[0..$length-1];
    $cb->(reverse @events);
}

sub publish {
    my($self, @events) = @_;

    for my $sid (keys %{$self->sessions}) {
        my $session = $self->sessions->{$sid};
        my $cb = $session->{cv}->cb;

        if ($cb) {
            # currently listening: flush and send the events right away
            my @ev = (@{$session->{buffer}}, @events);
            $session->{cv}->send(@ev);
            $session->{cv} = AE::cv;
            $session->{buffer} = [];
        } else {
            # between long poll comet: buffer the events
            push @{$session->{buffer}}, @events;
        }

        if ($session->{persistent}) {
            # TODO there's no sweeper for the persistent push: there should be
            $session->{cv}->cb($cb); # poll forever
        } elsif ($cb) {
            # garbage collection
            $session->{timer} = AE::timer 300, 0, sub {
                delete $self->sessions->{$sid};
            };
        }
    }
    $self->append_backlog(@events);
}

sub poll_once {
    my($self, $sid, $cb, $timeout) = @_;

    my $session = $self->sessions->{$sid} ||= {
        cv => AE::cv, persistent => 0, buffer => [],
    };
    $session->{cv}->cb(sub { $cb->($_[0]->recv) });

    # reset garbage collection timeout with the long-poll timeout
    $session->{timer} = AE::timer $timeout || 55, 0, sub {
        $session->{cv}->send();
        $session->{cv} = AE::cv;
    };
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
