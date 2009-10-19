package Tatsumaki::MessageQueue;
use strict;
use Moose;

use constant CV         => 0;
use constant PERSISTENT => 1;
use constant BUFFER     => 2;
use constant TIMER      => 3;

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
        my $cb = $session->[CV]->cb;

        if ($cb) {
            # currently listening: send the event right away
            my @ev = (@{$session->[BUFFER]}, @events);
            $session->[CV]->send(@ev);
            $session->[CV] = AE::cv;
            $session->[BUFFER] = [];
        } else {
            # between long poll commet: buffer the events
            push @{$session->[BUFFER]}, @events;
        }

        if ($session->[PERSISTENT]) {
            $session->[CV]->cb($cb); # poll forever
        } elsif ($cb) {
            # garbage collection
            $session->[TIMER] = AE::timer 300, 0, sub {
                delete $self->sessions->{$sid};
            };
        }
    }
    $self->append_backlog(@events);
}

sub poll_once {
    my($self, $sid, $cb, $timeout) = @_;

    my $session = $self->sessions->{$sid} ||= [ AE::cv, 0, [], undef ];
    $session->[CV]->cb(sub { $cb->($_[0]->recv) });

    # reset garbage collection timeout with the long-poll timeout
    $session->[TIMER] = AE::timer $timeout || 55, 0, sub {
        $session->[CV]->send();
        $session->[CV] = AE::cv;
    };
}

sub poll {
    my($self, $sid, $cb) = @_;
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    $self->sessions->{$sid} = [ $cv, 1, [] ];
}

1;
