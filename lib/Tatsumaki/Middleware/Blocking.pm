package Tatsumaki::Middleware::Blocking;
use strict;
use base qw(Plack::Middleware);
use Carp ();
use Plack::Util;

# Run asnynchronous Tatsumaki app in a blocking mode. See also Middleware::Writer
sub call {
    my($self, $env) = @_;

    my $caller_supports_streaming = $env->{'psgi.streaming'};
    $env->{'psgi.streaming'} = Plack::Util::TRUE;

    my $res = $self->app->($env);
    return $res if $caller_supports_streaming;

    if (ref $res eq 'CODE') {
        $env->{'psgi.errors'}->print("psgi.nonblocking is off: running $env->{PATH_INFO} in a blocking mode\n");
        $res->(sub { $res = shift });
        $env->{'tatsumaki.block'}->();
    }

    unless (defined $res->[2]) {
        Carp::croak("stream_write is not supported on this server");
    }

    return $res;
}

1;
