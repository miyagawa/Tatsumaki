package Tatsumaki::MessageQueue;
use strict;
use Moose;

has channel => (is => 'rw', isa => 'Str');

my $waiters = {}; # channel => \@waiters

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    $class->$orig(channel => $_[0]);
};

sub waiters {
    my $self = shift;
    return $waiters->{$self->channel} ||= [];
}

sub clear_waiters {
    my $self = shift;
    $waiters->{$self->channel} = [];
}

sub publish {
    my $self = shift;
    for my $w (@{$self->waiters}) {
        $w->send(@_);
    }
    $self->clear_waiters;
}

sub poll {
    my $self = shift;
    my $cb = shift;
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    push @{$self->waiters}, $cv;
}

1;
