use strict;
use warnings;

package EchoHandler;
use parent qw(Tatsumaki::Handler::WebSocket);
__PACKAGE__->asynchronous(1);

sub open {
    my $self = shift;
    $self->write("Congrats!");
}

sub on_receive_message {
    my($self, $msg) = @_;
    $self->write("You said: " . $msg);
}

package StartHandler;
use parent qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    my $host = $self->request->uri->host_port;
    $self->write(<<CONTENT);
<html>
<body>
<script>
var ws = new WebSocket("ws://$host/ws/echo");
ws.onopen = function() {
  ws.send("Hello, world");
};
ws.onmessage = function (evt) {
  alert(evt.data);
};
</script>
</body>
</html>
CONTENT
}

package main;
use Tatsumaki::Application;

my $app = Tatsumaki::Application->new([
    '/ws/echo'  => 'EchoHandler',
    '/ws/start' => 'StartHandler',
]);

$app->psgi_app;

