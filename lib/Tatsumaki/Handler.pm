package Tatsumaki::Handler;
use strict;
use Carp ();
use Encode ();
use Moose;
use JSON;
use Text::MicroTemplate::File;
use Tatsumaki::Error;

has application => (is => 'rw', isa => 'Tatsumaki::Application');
has condvar  => (is => 'rw', isa => 'AnyEvent::CondVar');
has request  => (is => 'rw', isa => 'Plack::Request');
has response => (is => 'rw', isa => 'Plack::Response', lazy_build => 1);
has args     => (is => 'rw', isa => 'ArrayRef');
has writer   => (is => 'rw');
has template => (is => 'rw', isa => 'Text::MicroTemplate::File', lazy_build => 1);

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
    $self->request->new_response(200, [ 'Content-Type' => 'text/html; charset=utf-8' ]);
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
        return sub {
            my $start_response = shift;
            $cv->cb(sub {
                my $w = $start_response->(shift->recv);
                $self->writer($w) if $w;
            });
            $self->$method(@{$self->args});
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

sub get_chunk {
    my $self = shift;
    if (ref $_[0]) {
        $self->response->content_type('application/json');
        return JSON::encode_json($_[0]);
    } else {
        join '', map Encode::encode_utf8($_), @_;
    }
}

sub stream_write {
    my $self = shift;
    $self->get_writer->write($self->get_chunk(@_));
}

sub write {
    my $self = shift;
    push @{$self->_write_buffer}, $self->get_chunk(@_);
}

sub flush {
    my $self = shift;
    my($is_final) = @_;

    if ($self->writer) {
        $self->writer->write(join '', @{$self->_write_buffer});
        $self->_write_buffer([]);
    } elsif (!$self->is_nonblocking || $is_final) {
        my $body = $self->response->body || [];
        push @$body, @{$self->_write_buffer};
        $self->_write_buffer([]);
        $self->response->body($body);
    } else {
        my $res = $self->response->finalize;
        delete $res->[2]; # gimme a writer
        $self->condvar->send($res);
        $self->writer or Carp::croak("Can't get writer object back");
        $self->flush();
    }
}

sub finish {
    my($self, $chunk) = @_;
    $self->write($chunk) if defined $chunk;
    $self->flush(1);
    if ($self->writer) {
        $self->writer->close;
    } elsif ($self->condvar) {
        $self->condvar->send($self->response->finalize);
    }
}

sub _build_template {
    my $self = shift;
    my $path = $self->application->template_path;
    Text::MicroTemplate::File->new(
        include_path => ref $path eq 'ARRAY' ? $path : [ $path ],
        use_cache => 1,
    );
}

sub render {
    my($self, $file, $args) = @_;
    $args ||= {};
    $self->finish($self->template->render_file($file, { %$args, handler => $self })->as_string);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__
