package Tatsumaki;

use strict;
use 5.008_001;
our $VERSION = '0.01';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Tatsumaki - Non-blocking Web server and framework based on AnyEvent

=head1 SYNOPSIS

  use Tatsumaki;
  use Tatsumaki::Error;
  use Tatsumaki::Application;
  use Tatsumaki::HTTPClient;
  use Tatsumaki::Server;
  use JSON;

  package MainHandler;
  use base qw(Tatsumaki::Handler);

  sub get {
      my $self = shift;
      $self->write("Hello World");
  }

  package SearchHandler;
  use base qw(Tatsumaki::Handler);

  __PACKAGE__->nonblocking(1);

  sub get {
      my($self, $query) = @_;
      my $client = Tatsumaki::HTTPClient->new;
      $client->get("http://friendfeed-api.com/v2/feed/$query", sub { $self->on_response(@_) });
  }

  sub on_response {
      my($self, $res) = @_;
      if ($res->is_error) {
          Tatsumaki::Error::HTTP->throw(500);
      }
      my $json = JSON::decode_json($res->content);
      $self->write("Fetched " . scalar(@{$json->{entries}}) . " entries from API");
      $self->finish;
  }

  package main;

  my $app = Tatsumaki::Application->new([
      '/feed/(\w+)' => 'SearchHandler',
      '/' => 'MainHandler',
  ]);

  if (__FILE__ eq $0) {
      Tatsumaki::Server->new(port => 9999)->run($app);
  } else {
      return $app->psgi_app;
  }

=head1 DESCRIPTION

Tatsumaki is a toy port of Tornado for Perl using PSGI (with
non-blocking extensions) and AnyEvent. Note that this is not a serious
port but an experiment to see how non-blocking apps can be implemented
in PSGI compatible web servers and frameworks.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<AnyEvent> L<Plack> L<PSGI> L<http://www.tornadoweb.org/>

=cut
