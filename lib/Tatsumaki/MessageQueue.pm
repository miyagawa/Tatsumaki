package Tatsumaki::MessageQueue;
use strict;
use Moose;

has channel => (is => 'rw', isa => 'Str');
has backlog => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has waiters => (is => 'rw', isa => 'ArrayRef', default => sub { [] });

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

    my @persistent;
    for my $w (@{$self->waiters}) {
        my $cb = $w->[0]->cb;
        $w->[0]->send(@events);
        if ($w->[1]) {
            push @persistent, do {
                my $cv = AE::cv;
                $cv->cb($cb);
                [ $cv, 1 ];
            };
        }
    }
    $self->append_backlog(@events);
    $self->waiters(\@persistent);
}

sub poll_once {
    my $self = shift;
    # FIXME If publish happens between poll -> poll then the events doesn't get delivered
    # poll should first check if there's anything left for this client
    my $cb = shift;
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    push @{$self->waiters}, [ $cv, 0 ];
}

sub poll {
    my $self = shift;
    my $cb = shift;
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    push @{$self->waiters}, [ $cv, 1 ];
}

1;
