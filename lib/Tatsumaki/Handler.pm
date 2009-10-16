package Tatsumaki::Handler;
use strict;
use Carp ();
use Encode ();
use Moose;
use Tatsumaki::Error;

has application => (is => 'rw', isa => 'Tatsumaki::Application');
has condvar  => (is => 'rw', isa => 'AnyEvent::CondVar');
has request  => (is => 'rw', isa => 'Plack::Request');
has response => (is => 'rw', isa => 'Plack::Response', lazy_build => 1);
has args     => (is => 'rw', isa => 'ArrayRef');
has writer   => (is => 'rw');

has _write_buffer => (is => 'rw', isa => 'ArrayRef', lazy => 1, default => sub { [] });

my $class_attr = {};

sub is_nonblocking {
    my $class = ref $_[0] || $_[0];
    return $class_attr->{$class}{is_nonblocking};
}

sub nonblocking {
    my $class = shift;
    $class_attr->{$class}{is_nonblocking} = shift;
}

sub _build_response {
    my $self = shift;
    $self->request->new_response(200, [ 'Content-Type' => 'text/plain; charset=utf-8' ]);
}

sub run {
    my $self = shift;
    my $method = lc $self->request->method;
    # TODO supported_methods
    if ($self->is_nonblocking) {
        unless ($self->request->env->{'psgi.streaming'}) {
            Tatsumaki::Error::HTTP->throw(500, "nonblocking handlers need PSGI servers that support psgi.streaming");
        }
        my $cv = AE::cv;
        $self->condvar($cv);
        $self->$method(@{$self->args});
        return sub {
            my $start_response = shift;
            $cv->cb(sub {
                my $w = $start_response->(shift->recv);
                $self->writer($w) if $w;
            });
        };
    } else {
        $self->$method(@{$self->args});
        $self->flush;
        return $self->response->finalize;
    }
}

sub get_writer {
    my $self = shift;
    $self->flush unless $self->writer;
    return $self->writer;
}

sub stream_write {
    my $self = shift;
    my $writer = $self->get_writer;

    my @buf = map Encode::encode_utf8($_), @_;
    $writer->write(join '', @buf);
}

sub write {
    my $self = shift;
    my @buf = map Encode::encode_utf8($_), @_;
    push @{$self->_write_buffer}, @buf;
}

sub flush {
    my $self = shift;

    if (!$self->is_nonblocking) {
        my $body = $self->response->body || [];
        push @$body, @{$self->_write_buffer};
        $self->_write_buffer([]);
        $self->response->body($body);
    } elsif ($self->writer) {
        $self->writer->write(join '', @{$self->_write_buffer});
        $self->_write_buffer([]);
    } else {
        my $res = $self->response->finalize;
        delete $res->[2]; # gimme a writer
        $self->condvar->send($res);
        $self->writer or Carp::croak("Can't get writer object back");
        $self->flush();
    }
}

sub finish {
    my $self = shift;
    $self->flush;
    if ($self->writer) {
        $self->writer->close;
    } elsif ($self->condvar) {
        # TODO set Content-Length
        $self->condvar->send($self->response->finalize);
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__
