package Tatsumaki::Service::XMPP::Message;
use Moose;

has from => (is => 'rw', isa => 'Str');
has to   => (is => 'rw', isa => 'Str');
has body => (is => 'rw', isa => 'Str');
has command => (is => 'rw', isa => 'Str');
has arg  => (is => 'rw', isa => 'Str');

has xmpp_message => (is => 'ro', isa => 'AnyEvent::XMPP::IM::Message');

sub reply {
    my $self = shift;
    my($body) = @_;

    my $reply = $self->xmpp_message->make_reply;
    $reply->add_body($body);
    $reply->send;
}

1;
