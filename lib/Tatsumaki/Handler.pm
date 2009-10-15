package Tatsumaki::Handler;
use strict;
use Encode;
use Moose;

has application => (is => 'rw', isa => 'Tatsumaki::Application');
has condvar  => (is => 'rw', isa => 'AnyEvent::CondVar');
has request  => (is => 'rw', isa => 'Plack::Request');
has response => (is => 'rw', isa => 'Plack::Response', lazy_build => 1);
has args     => (is => 'rw', isa => 'ArrayRef');

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
    $self->$method(@{$self->args});
    $self->finish unless $self->is_nonblocking;
}

sub write {
    my $self = shift;
    push @{$self->_write_buffer}, map Encode::encode_utf8($_), @_;
}

sub flush {
    my $self = shift;
    # FIXME do something else in non-blocking
    my $body = $self->response->body || [];
    push @$body, @{$self->_write_buffer};
    $self->_write_buffer([]);
    $self->response->body($body);
}

sub finish {
    my $self = shift;
    $self->flush;
    $self->condvar->send($self->response->finalize);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__
