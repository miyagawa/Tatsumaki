package Tatsumaki::Service::Stardust;
use Any::Moose;
extends 'Tatsumaki::Service';

use Encode ();
use JSON ();
use Tatsumaki;
use Tatsumaki::MessageQueue;
use Tatsumaki::Application;

sub start {
    my $self = shift;

    $self->application->add_handlers(
        '/_services/stardust/channel/([\w\+]+)/stream/?([\w\.]*)' => 'Tatsumaki::Service::Stardust::StreamHandler',
        '/_services/stardust/channel/([\w\+]+)' => 'Tatsumaki::Service::Stardust::ChannelHandler',
        '/_services/stardust/channel' => 'Tatsumaki::Service::Stardust::ChannelListHandler',
        '/_services/stardust' => 'Tatsumaki::Service::Stardust::Info',
    );
}

package Tatsumaki::Service::Stardust::InfoHandler;
use parent qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    $self->finish({
        name => 'Tatsumaki::Service::Stardust',
        language => 'Perl',
        version => Tatsumaki->VERSION,
    });
}

package Tatsumaki::Service::Stardust::ChannelListHandler;
use parent qw(Tatsumaki::Handler);

sub get {
    my $self = shift;
    my @channels = Tatsumaki::MessageQueue->channels;
    $self->finish([ map $_->channel, @channels ]);
}

package Tatsumaki::Service::Stardust::ChannelHandler;
use parent qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

use JSON;

sub get {
    my($self, $channel) = @_;

    my $mq = Tatsumaki::MessageQueue->instance($channel);
    $self->finish({
        name => $mq->channel,
        messages => [ $mq->backlog_events ],
        subscribers => [ $mq->clients ],
    });
}

sub post {
    my($self, $channel) = @_;

    my $mq = Tatsumaki::MessageQueue->instance($channel);

    my @events = map JSON::decode_json(Encode::encode_utf8($_)), $self->request->param('m');
    for my $event (@events) {
        $mq->publish($event);
    }

    $self->response->code(204);
    $self->finish;
}

package Tatsumaki::Service::Stardust::StreamHandler;
use parent qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
    my($self, $channel, $client_id) = @_;

    my $mq = Tatsumaki::MessageQueue->instance($channel);

    if ($self->request->header('Accept') =~ m!multipart/mixed!) {
        $self->multipart_xhr_push(1);
        $mq->poll($client_id, sub {
            my @events = @_;
            for my $event (@events) {
                $self->stream_write($event);
            }
        });
    } else {
        $mq->poll_once($client_id, sub {
            my @events = @_;
            $self->write(\@events);
            $self->finish;
        });
    }
}

1;
