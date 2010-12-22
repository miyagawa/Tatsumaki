use Test::More;
use Test::Requires qw/
Test::TCP
Proc::Guard
Unix::Lsof
FindBin
Plack::Runner
/;
use Test::TCP qw/empty_port wait_port/;
use strict;
use warnings;

use AnyEvent;
use AnyEvent::HTTP;

my ($tatsumaki,$port) = prepare();

is( count_close_wait_for_port($port), 0 );

cycle($port);
cycle($port);

sleep(2);

is( count_close_wait_for_port($port), 0 );

done_testing;

sub prepare {
    my $psgi = "$FindBin::Bin/leak.psgi";

    my $async_port = empty_port();
    my $async = proc_guard(
        sub {
            my $runner = Plack::Runner->new;
            $runner->parse_options( qw/-p/, $async_port, qw/-s Twiggy -a/, $psgi );
            $runner->run;
        }
    );
    wait_port( $async_port );

    return ($async, $async_port);
}

sub cycle {
    my $port = shift;

    my $cv = AE::cv;
    my $request = http_get "http://localhost:$port/",
        timeout => 1, # shorter than long-poll timeout
            sub {
                $cv->send;
            };
    $cv->wait;
}

# count CLOSE_WAIT file descriptors on $port
sub count_close_wait_for_port {
    my $port = shift;

    my ($output, $error) = lsof(qw/-i/, ":$port");
    my @values = values %$output;
    my @files;
    for my $value (@values) {
        push( @files, @{ $value->{ files } } );
    }

    return scalar grep { $_->{ 'tcp/tpi info' }{ 'connection state' } eq 'CLOSE_WAIT'; } @files;
}
