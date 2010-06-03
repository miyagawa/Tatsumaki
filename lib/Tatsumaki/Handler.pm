package Tatsumaki::Handler;
use strict;
use AnyEvent;
use Carp ();
use Encode ();
use Any::Moose;
use MIME::Base64 ();
use JSON;
use Try::Tiny;
use Tatsumaki::Error;

has application => (is => 'rw', isa => 'Tatsumaki::Application');
has condvar  => (is => 'rw', isa => 'AnyEvent::CondVar');
has request  => (is => 'rw', isa => 'Tatsumaki::Request');
has response => (is => 'rw', isa => 'Tatsumaki::Response', lazy_build => 1);
has args     => (is => 'rw', isa => 'ArrayRef');
has writer   => (is => 'rw');
has mxhr     => (is => 'rw', isa => 'Bool');
has mxhr_boundary => (is => 'rw', isa => 'Str', lazy => 1, lazy_build => 1);

has _write_buffer => (is => 'rw', isa => 'ArrayRef', lazy => 1, default => sub { [] });

sub head   { shift->get(@_) }
sub get    { Tatsumaki::Error::HTTP->throw(405) }
sub post   { Tatsumaki::Error::HTTP->throw(405) }
sub put    { Tatsumaki::Error::HTTP->throw(405) }
sub delete { Tatsumaki::Error::HTTP->throw(405) }

sub prepare { }

my $class_attr = {};

sub is_asynchronous {
    my $class = ref $_[0] || $_[0];
    return $class_attr->{$class}{is_asynchronous};
}

sub asynchronous {
    my $class = shift;
    $class_attr->{$class}{is_asynchronous} = shift;
}

sub nonblocking { shift->asynchronous(@_) } # alias

sub multipart_xhr_push {
    my $self = shift;
    if ($_[0]) {
        Carp::croak("asynchronous should be set to do multipart XHR push")
            unless $self->is_asynchronous;
        $self->response->content_type('multipart/mixed; boundary="' . $self->mxhr_boundary . '"');

        # HACK: Always write a boundary for the next event, so client JS can fire the event immediately
        # Maybe DUI.Stream should respect the Content-Length header to look at the endFlag
        $self->stream_write("--" . $self->mxhr_boundary. "\n");

        return $self->mxhr(1);
    } else {
        return $self->mxhr;
    }
}

sub _build_mxhr_boundary {
    my $size = 2;
    my $b = MIME::Base64::encode(join("", map chr(rand(256)), 1..$size*3), "");
    $b =~ s/[\W]/X/g;  # ensure alnum only
    $b;
}

sub _build_response {
    my $self = shift;
    $self->request->new_response(200, [ 'Content-Type' => 'text/html; charset=utf-8' ]);
}

my $supported;

sub supported_method {
    my($self, $method) = @_;
    $supported ||= +{ map { $_ => 1 } qw( head get post put delete ) };
    return $supported->{$method};
}

sub async_cb {
    my $self = shift;
    my $cb = shift;
    return sub {
        my @args = @_;
        try { $cb->(@args) }
        catch { $self->condvar->croak($_) };
    };
}

sub run {
    my $self = shift;

    my $method = lc $self->request->method;
    unless ($self->supported_method($method)) {
        Tatsumaki::Error::HTTP->throw(400);
    }

    my $catch = sub {
        if ($_->isa('Tatsumaki::Error::HTTP')) {
            return [ $_->code, [ 'Content-Type' => $_->content_type ], [ $_->message ] ];
        } else {
            $self->log($_);
            return [ 500, [ 'Content-Type' => 'text/plain' ], [ "Internal Server Error" ] ];
        }
    };

    if ($self->is_asynchronous) {
        $self->condvar(my $cv = AE::cv);
        return sub {
            my $start_response = shift;
            $cv->cb(sub {
                my $cv = shift;
                try {
                    my $res = $cv->recv;
                    my $w = $start_response->($res);
                    if (!$res->[2] && $w) {
                        $self->writer($w);
                        $self->condvar(my $cv2 = AE::cv);
                    }
                } catch {
                    $start_response->($catch->());
                };
            });

            try {
                $self->prepare;
                $self->$method(@{$self->args});
            } catch {
                $cv->croak($_);
            };

            unless ($self->request->env->{'psgi.nonblocking'}) {
                $self->log("Running an async handler in a blocking server. MQ based app should cause a deadlock.\n");
                $self->condvar->recv for 1..2; # response and writer
            }
        };
    } else {
        my $res = try {
            $self->prepare;
            $self->$method(@{$self->args});
            $self->flush;
            return $self->response->finalize;
        } catch {
            return $catch->();
        };

        return $res;
    }
}

sub log {
    my($self, @stuff) = @_;
    $self->request->env->{'psgi.errors'}->print(join '', @stuff);
}

sub get_writer {
    my $self = shift;
    $self->flush unless $self->writer;
    return $self->writer;
}

sub get_chunk {
    my $self = shift;
    if (ref $_[0]) {
        if ($self->mxhr) {
            my $json = JSON::encode_json($_[0]);
            return "Content-Type: application/json\n\n$json\n--" . $self->mxhr_boundary. "\n";
        } else {
            $self->response->content_type('application/json');
            return JSON::encode_json($_[0]);
        }
    } else {
        join '', map Encode::encode_utf8($_), @_;
    }
}

sub _write {
    my $self = shift;
    my @buf  = @_;
    try {
        $self->get_writer->write(@buf);
    } catch {
        /Broken pipe/ and Tatsumaki::Error::ClientDisconnect->throw;
        die $_;
    }
}

sub stream_write {
    my $self = shift;
    $self->_write($self->get_chunk(@_));
}

sub write {
    my $self = shift;
    push @{$self->_write_buffer}, $self->get_chunk(@_);
}

sub flush {
    my $self = shift;
    my($is_final) = @_;

    if ($self->writer) {
        $self->_write(join '', @{$self->_write_buffer}) if @{$self->_write_buffer};
        $self->_write_buffer([]);
    } elsif (!$self->is_asynchronous || $is_final) {
        my $body = $self->response->body || [];
        push @$body, @{$self->_write_buffer};
        $self->_write_buffer([]);
        $self->response->body($body);
    } else {
        my $res = $self->response->finalize;
        delete $res->[2]; # gimme a writer
        $self->condvar->send($res);
        $self->writer or Carp::croak("Can't get a writer object back: you need servers with psgi.streaming");
        $self->flush();
    }
}

sub finish {
    my($self, $chunk) = @_;
    $self->write($chunk) if defined $chunk;
    $self->flush(1);
    if ($self->writer) {
        $self->writer->close;
        $self->condvar->send;
    } elsif ($self->condvar) {
        $self->condvar->send($self->response->finalize);
    }
}

sub render {
    my($self, $file, $args) = @_;
    $args ||= {};
    $self->finish($self->application->render_file($file, { %$args, handler => $self })->as_string);
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__
