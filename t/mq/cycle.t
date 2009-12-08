use Test::More;
use Test::Requires qw(Test::Memory::Cycle);
use Tatsumaki::MessageQueue;

my $channel  = 'test1';

my $client_id = rand(1);

my $sub = Tatsumaki::MessageQueue->instance( $channel );
$sub->poll_once($client_id, sub { ok(1, 'got message') });

memory_cycle_ok( $sub, 'no leaks' );

my $pub = Tatsumaki::MessageQueue->instance( $channel );
$pub->publish({ data => 'hello' });

memory_cycle_ok( $sub, 'no leaks in subscriber' );
memory_cycle_ok( $pub, 'no leaks in publisher' );

# We''re actually relying on the poll_once test, hacky but not sure how to
# verify

done_testing;
