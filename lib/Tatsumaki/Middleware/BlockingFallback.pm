package Tatsumaki::Middleware::BlockingFallback;
use strict;
use base qw(Plack::Middleware);
use Carp ();
use Plack::Util;
use Scalar::Util ();

# Run asnynchronous PSGI app in a blocking mode. See also Middleware::Writer
sub call {
    my($self, $env) = @_;

    my $caller_supports_streaming = $env->{'psgi.streaming'};
    $env->{'psgi.streaming'} = Plack::Util::TRUE;

    my $res = $self->app->($env);
    return $res if $caller_supports_streaming;

    if (ref $res eq 'CODE') {
        $env->{'psgi.errors'}->print("psgi.streaming is off: running $env->{PATH_INFO} in a blocking mode\n");
        my $use_writer;
        $res->(sub {
            $res = shift;
            unless (defined $res->[2]) {
                $env->{'psgi.errors'}->print("Buffering the output of $env->{PATH_INFO}: This might cause a deadlock\n");
                $use_writer = 1;
                my($closed, @body);
                $res->[2] = \@body;
                my $writer;
                my $ref_up = $writer = Plack::Util::inline_object
                    poll_cb => sub { $_[0]->($writer) until $closed },
                    write   => sub { push @body, $_[0] },
                    close   => sub { $closed => 1 };

                Scalar::Util::weaken($writer);
                return $writer;
            }
        });

        $env->{'psgix.block.response'}->() if $env->{'psgix.block.response'};
        if ($use_writer) {
            $env->{'psgix.block.body'}->() if $env->{'psgix.block.body'};
        }
    }

    return $res;
}

1;
