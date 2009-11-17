package Tatsumaki::Template::Micro;
use Moose;
extends 'Tatsumaki::Template';

use Text::MicroTemplate::Extended;
has mt => (is => 'rw', isa => 'Text::MicroTemplate::Extended', handles => [ 'render_file' ]);

sub BUILD {
    my $self = shift;

    my $mt = Text::MicroTemplate::Extended->new(
        include_path => [ 'templates' ],
        use_cache => 0,
        tag_start => '<%',
        tag_end   => '%>',
        line_start => '%',
        extension => '',
    );

    $self->mt($mt);
};

sub include_path {
    my $self = shift;
    $self->mt->{include_path} = shift if @_;
    $self->mt->{include_path};
}

1;

