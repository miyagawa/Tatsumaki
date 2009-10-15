package Tatsumaki::Application;
use AnyEvent;
use Moose;
use Path::Dispatcher;
use Plack::Request;
use Plack::Response;
use Tatsumaki::Handler;
use Try::Tiny;

use overload q(&{}) => sub { shift->psgi_app }, fallback => 1;

has '_dispatcher' => (is => 'rw', isa => 'Path::Dispatcher', lazy_build => 1);

sub _build__dispatcher {
    Path::Dispatcher->new;
}

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    if (ref $_[0] eq 'ARRAY') {
        $class->$orig(_rules => $_[0]);
    } else {
        $class->$orig(@_);
    }
};

sub BUILD {
    my $self = shift;

    my %args  = %{$_[0]};
    my @rules = @{$args{_rules}};

    my $dispatcher = $self->_dispatcher;
    while (my($path, $handler) = splice @rules, 0, 2) {
        $path = qr/^$path/ unless ref $path eq 'RegExp';
        $dispatcher->add_rule(
            Path::Dispatcher::Rule::Regex->new(
                regex => $path,
                block => sub {
                    my $cb = shift;
                    $cb->($handler, $1, $2, $3, $4, $5, $6, $7, $8, $9);
                },
            ),
        );
    }

    return $self;
}

sub psgi_app {
    my $self = shift;
    return sub {
        my $env = shift;
        my $req = Plack::Request->new($env);

        my $dispatch = $self->_dispatcher->dispatch($req->path);
        unless ($dispatch->has_matches) {
            return [ 404, [ 'Content-Type' => 'text/html' ], [ "404 Not Found" ] ];
        }

        # TODO if you throw exception from nonblocking callback, there seems no way to catch it
        return $dispatch->run(sub {
            my $handler = shift;
            my $context = $handler->new(
                application => $self,
                handler => $handler,
                request => $req,
                args    => [ @_ ],
            );
            $context->run;
        });
    };
}

1;


