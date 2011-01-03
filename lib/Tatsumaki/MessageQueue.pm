package Tatsumaki::MessageQueue;
use strict;

use AnyEvent;
use Any::Moose;
use Scalar::Util;
use Time::HiRes;
use constant DEBUG => $ENV{TATSUMAKI_DEBUG};

has channel => (is => 'rw', isa => 'Str');
has backlog => (is => 'rw', isa => 'ArrayRef', default => sub { [] });
has clients => (is => 'rw', isa => 'HashRef', default => sub { +{} });

our $BacklogLength = 30; # TODO configurable

my %instances;

sub channels {
    values %instances;
}

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
            $self->flush_events($client_id, @events);
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
    local $@;
    eval {
        my $cb = $client->{cv}->cb;
        $client->{cv}->send(@events);
        $client->{cv} = AE::cv;
        $client->{buffer} = [];

        if ($client->{persistent}) {
            $client->{cv}->cb($cb);
        } else {
            undef $client->{longpoll_timer};
            $client->{reconnect_timer} = AE::timer 30, 0, sub {
                Scalar::Util::weaken $self;
                warn "Sweep $client_id (no long-poll reconnect)" if DEBUG;
                undef $client;
                delete $self->clients->{$client_id};
            };
        }
    };
    if ($@ && $@ =~ /Tatsumaki::Error::ClientDisconnect/) {
        warn "Client $client_id disconnected" if DEBUG;
        undef $client;
        delete $self->clients->{$client_id};
    }
}

sub poll_once {
    my($self, $client_id, $cb, $timeout) = @_;

    my $is_new;
    my $client = $self->clients->{$client_id} ||= do {
        $is_new = 1;
        + { cv => AE::cv, persistent => 0, buffer => [] };
    };

    if ( $client->{longpoll_timer} ) {
        # close last connection from the same client_id
        $self->flush_events($client_id);
        undef $client->{longpoll_timer};
    }
    undef $client->{reconnect_timer};

    $client->{cv}->cb(sub { $cb->($_[0]->recv) });

    # reset garbage collection timeout with the long-poll timeout
    # $timeout = 0 is a valid timeout for interval-polling
    $timeout = 55 unless defined $timeout;
    $client->{longpoll_timer} = AE::timer $timeout || 55, 0, sub {
        Scalar::Util::weaken $self;
        warn "Timing out $client_id long-poll" if DEBUG;
        $self->flush_events($client_id);
    };

    if ($is_new) {
        # flush backlog for a new client
        my @events = $self->backlog_events;
        $self->flush_events($client_id, @events) if @events;
    }elsif ( @{ $client->{buffer} } ) {
        # flush buffer for a long-poll client
        $self->flush_events($client_id, @{ $client->{buffer} });
    }
}

sub poll {
    my($self, $client_id, $cb) = @_;

    # TODO register client info like names and remote host in $client
    my $cv = AE::cv;
    $cv->cb(sub { $cb->($_[0]->recv) });
    my $s = $self->clients->{$client_id} = {
        cv => $cv, persistent => 1, buffer => [],
    };

    my @events = $self->backlog_events;
    $self->flush_events($client_id, @events) if @events;
}

1;

__END__

=encoding utf-8

=for stopwords

=head1 NAME

Tatsumaki::MessageQueue - Message Queue system for Tatsumaki

=head1 SYNOPSIS

To publish a message, you first create an instance of the message queue on
a specific channel:

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->publish({
        type => "message", data => $your_data,
        address => $self->request->address,
        time => scalar Time::HiRes::gettimeofday,
    });

Later, in a handler, you can poll for new messages:

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    my $client_id = $self->request->param('client_id')
        or Tatsumaki::Error::HTTP->throw(500, "'client_id' needed");
    $mq->poll_once($client_id, sub { $self->write(\@_); $self->finish; });

Additionally, if you are using Multipart XmlHttpRequest (MXHR) you can use
the event API, and run a callback each time a new message is published:

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $mq->poll($client_id, sub {
        my @events = @_;
        for my $event (@events) {
            $self->stream_write($event);
        }
    });

=head1 DESCRIPTION

Tatsumaki::MessageQueue is a simple message queue, storing all messages in
memory, and keeping track of a configurable backlog.  All polling requests
are made with a C<$client_id>, and the message queue keeps track of a buffer
per client, to ensure proper message delivery.

=head1 CONFIGURATION

=over

=item BacklogLength

To configure the number of messages in the backlog, set 
C<$Tatsumaki::MessageQueue::BacklogLength>.  By default, this is set to 30.

=back

=head1 METHODS

=head2 publish

This method publishes a message into the message queue, for immediate 
consumption by all polling clients.

=head2 poll($client_id, $code_ref)

This is the event-driven poll mechanism, which accepts a callback as the
second parameter. It will stream messages to the code ref passed in. 

=head2 poll_once($client_id, $code_ref)

This method returns all messages since the last poll to the code reference
passed as the second parameter.

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Tatsumaki>

=cut
