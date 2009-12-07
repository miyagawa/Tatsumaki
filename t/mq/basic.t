use Test::More;

use_ok('Tatsumaki::MessageQueue');

srand(time ** $$);

my $channel  = 'test1';

my $clients = 5;
my $inc     = 0;

for my $client ( 1 .. $clients ) {
    my $sub = Tatsumaki::MessageQueue->instance( $channel );
    $sub->poll_once($client, sub { $inc++ });
}

my $pub = Tatsumaki::MessageQueue->instance( $channel );
$pub->publish({ data => 'hello' });

is( $inc, $clients, 'messagequeue publish' );

done_testing;
