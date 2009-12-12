package Tatsumaki::Request;
use Encode;
use parent qw(Plack::Request);

use Tatsumaki::Response;

sub _build_parameters {
    my $self = shift;

    my $params = $self->SUPER::_build_parameters();

    my $decoded_params = {};
    while (my($k, $v) = each %$params) {
        $decoded_params->{decode_utf8($k)} = ref $v eq 'ARRAY'
            ? [ map decode_utf8($_), @$v ] : decode_utf8($v);
    }

    return $decoded_params;
}

sub new_response {
    my $self = shift;
    Tatsumaki::Response->new(@_);
}

1;

