use strict;
use warnings;
use Test::More;
use AnyEvent;
use Tatsumaki::MessageQueue;

my $tests = 3;

my $sequence = 0;
sub do_test {
	my ( $channel, $client ) = @_;
	my $seq = ++$sequence;
	my @send_events = ( { data1 => $seq }, { data2 => $seq }, );

	my $cv = AE::cv;
	my $t  = AE::timer 1, 0, sub { $cv->croak( "timeout" ); };

	# Publish events before the client has connected.
	my $pub = Tatsumaki::MessageQueue->instance( $channel );
	$pub->publish( @send_events );

	# Should be able to get published events.
	my $sub = Tatsumaki::MessageQueue->instance( $channel );
	$sub->poll_once($client, sub {
		my @events = @_;
		is_deeply \@events, \@send_events, "got events";
		$cv->send;
	});

	$cv->recv;
}

plan tests => $tests;
do_test( 'comet', 'client_id' ) for 1 .. $tests;
