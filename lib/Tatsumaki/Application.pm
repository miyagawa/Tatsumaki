package Tatsumaki::Application;
use AnyEvent;
use Any::Moose;
use Tatsumaki::Handler;
use Tatsumaki::Request;
use 5.6.0;  # for @-

use Plack::Middleware::Static;

use overload q(&{}) => sub { shift->psgi_app }, fallback => 1;

has _rules   => (is => 'rw', isa => 'ArrayRef');
has template => (is => 'rw', isa => 'Tatsumaki::Template', lazy_build => 1, handles => [ 'render_file' ]);

has static_path => (is => 'rw', isa => 'Str', default => 'static');
has _services   => (is => 'rw', isa => 'HashRef', default => sub { +{} });

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    if (ref $_[0] eq 'ARRAY') {
        my $handlers = shift @_;
        my @rules;
        while (my($path, $handler) = splice @$handlers, 0, 2) {
            $path = qr@^/$@    if $path eq '/';
            $path = qr/^$path/ unless ref $path eq 'RegExp';
            push @rules, { path => $path, handler => $handler };
        }
        $class->$orig(_rules => \@rules, @_);
    } else {
        $class->$orig(@_);
    }
};

sub add_handlers {
    my $self = shift;
    while (my($path, $handler) = splice @_, 0, 2) {
        $self->route($path, $handler);
    }
}

sub route {
    my($self, $path, $handler) = @_;
    $path = qr/^$path/ unless ref $path eq 'RegExp';
    push @{$self->_rules}, { path => $path, handler => $handler };
}

sub dispatch {
    my $self = shift;
    my $req  = shift;

    my $path = $req->path_info;
    for my $rule (@{$self->_rules}) {
        if (my @args = ($path =~ $rule->{path})) {
            shift @args if @- == 1 && @args == 1 && defined($args[0]) && $args[0] eq '1';
            return $rule->{handler}->new(@_, application => $self, request => $req, args => \@args);
        }
    }

    return;
}

sub psgi_app {
    my $self = shift;
    return $self->{psgi_app} ||= $self->compile_psgi_app;
}

sub compile_psgi_app {
    my $self = shift;

    my $app = sub {
        my $env = shift;
        my $req = Tatsumaki::Request->new($env);

        my $handler = $self->dispatch($req)
            or return [ 404, [ 'Content-Type' => 'text/html' ], [ "404 Not Found" ] ];

        my $res = $handler->run;
    };

    if ($self->static_path) {
        $app = Plack::Middleware::Static->wrap($app, path => sub { s/^\/(?:(favicon\.ico)|static\/)/$1||''/e }, root => $self->static_path);
    }

    $app;
}

sub _build_template {
    my $self = shift;
    require Tatsumaki::Template::Micro;
    Tatsumaki::Template::Micro->new;
}

sub template_path {
    my $self = shift;
    if (@_) {
        my $path = ref $_[0] eq 'ARRAY' ? $_[0] : [ $_[0] ];
        $self->template->include_path($path);
    }
    $self->template->include_path;
}

sub add_service {
    my $self = shift;

    my($name, $service);
    if (@_ == 2) {
        ($name, $service) = @_;
    } else {
        $service = shift;
        $name = $self->_service_name_for($service);
    }

    $service->application($self);
    $service->start;
    $self->_services->{$name} = $service;
}

sub service {
    my($self, $name) = @_;
    $self->_services->{$name};
}

sub services {
    my $self = shift;
    values %{$self->_services};
}

sub _service_name_for {
    my($self, $service) = @_;

    my $ref = ref $service;
    $ref =~ s/^Tatsumaki::Service:://;

    my $name = $ref;

    my $i = 0;
    while (exists $self->_services->{$name}) {
        $name = $ref . $i++;
    }

    return $name;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;


