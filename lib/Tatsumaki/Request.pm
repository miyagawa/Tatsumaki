package Tatsumaki::Request;
use Encode;
use Moose;
use MooseX::NonMoose;
extends 'Plack::Request';

use Tatsumaki::Response;

override _build_parameters => sub {
    my $self = shift;

    my $params = super();

    my $decoded_params = {};
    while (my($k, $v) = each %$params) {
        $decoded_params->{decode_utf8($k)} = decode_utf8($v);
    }

    return $decoded_params;
};

sub new_response {
    my $self = shift;
    Tatsumaki::Response->new(@_);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

