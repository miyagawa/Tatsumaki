#!/usr/bin/perl
use strict;
use warnings;
use Scalar::Util;
use Tatsumaki::Application;

package MainHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);
use Tatsumaki::MessageQueue;

sub get {
    my $self = shift;

    my $mq = Tatsumaki::MessageQueue->instance( '1' );
    $mq->poll_once(
        'me',
        sub {
            $self->write(\@_);
            $self->finish;
        },
        2 # poll for [sec]
    );
    Scalar::Util::weaken( $self );
}

package main;

my $app = Tatsumaki::Application->new([
    '/' => 'MainHandler',
]);

return $app;

