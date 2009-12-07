use Test::More;

use AE;
use Test::Memory::Cycle;

use Tatsumaki::MessageQueue;

srand(time ** $$);

my $channel  = 'test1';

my $client_id = rand(1);

my $instance = Tatsumaki::MessageQueue->instance( $channel );
$instance->poll_once($client_id, sub { });

memory_cycle_ok( $instance );

done_testing;
