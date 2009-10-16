package Tatsumaki::Application;
use AnyEvent;
use Moose;
use Plack::Request;
use Plack::Response;
use Tatsumaki::Handler;
use Try::Tiny;

use overload q(&{}) => sub { shift->psgi_app }, fallback => 1;

has _rules => (is => 'rw', isa => 'ArrayRef');

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    if (ref $_[0] eq 'ARRAY') {
        my @rules;
        while (my($path, $handler) = splice @{$_[0]}, 0, 2) {
            $path = qr/^$path/ unless ref $path eq 'RegExp';
            push @rules, { path => $path, handler => $handler };
        }
        $class->$orig(_rules => \@rules);
    } else {
        $class->$orig(@_);
    }
};

sub dispatch {
    my($self, $path) = @_;

    for my $rule (@{$self->_rules}) {
        if ($path =~ $rule->{path}) {
            my $args = [ $1, $2, $3, $4, $5, $6, $7, $8, $9 ];
            return sub { $rule->{handler}->new(@_, args => $args) };
        }
    }

    return;
}

sub psgi_app {
    my $self = shift;
    return sub {
        my $env = shift;
        my $req = Plack::Request->new($env);

        my $handler = $self->dispatch($req->path)
            or return [ 404, [ 'Content-Type' => 'text/html' ], [ "404 Not Found" ] ];

        # TODO: if you throw exception from nonblocking callback, there seems no way to catch it
        my $context = $handler->(
            application => $self,
            handler => $handler,
            request => $req,
        );
        $context->run;
    };
}

1;


