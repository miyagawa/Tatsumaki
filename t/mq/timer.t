use Test::More;
use Tatsumaki::MessageQueue;

my $channel  = 'test1';
my $client_id = rand(1);

my $cv = AE::cv;
my $t  = AE::timer 3, 0, sub { $cv->croak( "timeout" ); };

my $sub = Tatsumaki::MessageQueue->instance( $channel );
$sub->poll_once($client_id, sub { ok(1, 'long poll timeout'),
                                  $cv->send }, 1);


$cv->recv;

done_testing;
