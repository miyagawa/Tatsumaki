package Tatsumaki::Handler::XMPP;
use Moose;
extends 'Tatsumaki::Handler';

use Tatsumaki::Service::XMPP::Message;

sub xmpp_message {
    my $self = shift;

    my $params = $self->request->parameters;
    my $env    = $self->request->env->{'tatsumaki.xmpp'};

    Tatsumaki::Service::XMPP::Message->new(
        from => $params->{from},
        to   => $params->{to},
        body => $params->{body},
        xmpp_message => $env->{message},
    );
}

sub prepare {
    my $self = shift;

    unless (exists $self->request->env->{'tatsumaki.xmpp'}) {
        Tatsumaki::Error::HTTP->throw(400);
    }
}

sub post {
    my $self = shift;

    my $msg = $self->xmpp_message;
    if ($msg->body =~ s!^/(\w+)\s+!!) {
        my $cmd = $1;
        my $arg = $msg->body;

        my $handler = $cmd . "_command";
        if (my $method = $self->can($handler)) {
            $msg->command($1);
            $msg->arg($msg->body);
            $self->$method($msg);
        } else {
            $self->unhandled_command($msg, $cmd);
        }
    } else {
        # what to do?
    }
}

sub unhandled_command {
    my($self, $msg, $cmd) = @_;
    $msg->reply("Command /$cmd not found");
}

1;
