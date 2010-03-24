package Tatsumaki::Template::Micro;
use Any::Moose;
extends 'Tatsumaki::Template';

use Text::MicroTemplate::File;
has mt => (is => 'rw', isa => 'Text::MicroTemplate::File', handles => [ 'render_file' ]);

sub BUILD {
    my $self = shift;

    my $mt = Text::MicroTemplate::File->new(
        include_path => [ 'templates' ],
        use_cache => 0,
        tag_start => '<%',
        tag_end   => '%>',
        line_start => '%',
    );

    $self->mt($mt);
};

sub include_path {
    my $self = shift;
    $self->mt->{include_path} = shift if @_;
    $self->mt->{include_path};
}

1;

