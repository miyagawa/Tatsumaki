package Tatsumaki;

use strict;
use 5.008_001;
our $VERSION = '0.1010';

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Tatsumaki - Non-blocking web framework based on Plack and AnyEvent

=head1 SYNOPSIS

  ### app.psgi
  use Tatsumaki::Error;
  use Tatsumaki::Application;
  use Tatsumaki::HTTPClient;
  use Tatsumaki::Server;

  package MainHandler;
  use parent qw(Tatsumaki::Handler);

  sub get {
      my $self = shift;
      $self->write("Hello World");
  }

  package FeedHandler;
  use parent qw(Tatsumaki::Handler);
  __PACKAGE__->asynchronous(1);

  use JSON;

  sub get {
      my($self, $query) = @_;
      my $client = Tatsumaki::HTTPClient->new;
      $client->get("http://friendfeed-api.com/v2/feed/$query", $self->async_cb(sub { $self->on_response(@_) }));
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

  package StreamWriter;
  use parent qw(Tatsumaki::Handler);
  __PACKAGE__->asynchronous(1);

  use AnyEvent;

  sub get {
      my $self = shift;
      $self->response->content_type('text/plain');

      my $try = 0;
      my $t; $t = AE::timer 0, 0.1, sub {
          $self->stream_write("Current UNIX time is " . time . "\n");
          if ($try++ >= 10) {
              undef $t;
              $self->finish;
          }
      };
  }

  package main;

  my $app = Tatsumaki::Application->new([
      '/stream' => 'StreamWriter',
      '/feed/(\w+)' => 'FeedHandler',
      '/' => 'MainHandler',
  ]);
  return $app;

And now run it with:

  plackup -s AnyEvent -a app.psgi

=head1 WARNINGS

This is considered as alpha quality software. Most of the stuff are
undocumented since it's considered unstable and will likely to
change. You should sometimes look at the source code or example apps
in I<eg> directory to see how this thing works.

Feel free to hack on it and ask me if you have questions or
suggestions at IRC: #plack on irc.perl.org.

=head1 DESCRIPTION

Tatsumaki is a toy port of Tornado for Perl using Plack (with
non-blocking extensions) and AnyEvent.

It allows you to write a web application that does a immediate
response with template rendering, IO-bound delayed response (like
fetching third party API or XML feeds), server push streaming and
long-poll Comet in a clean unified API.

=head1 PSGI COMPATIBILITY

When C<asynchronous> is declared in your application, you need a PSGI
server backend that supports C<psgi.streaming> response style. If your
application does server push with C<stream_write>, you need a server
that supports C<psgi.nonblocking> (and C<psgi.streaming>) as well.

Currently Tatsumaki asynchronous application is supposed to run on
Tatsumaki::Server, Plack::Server::AnyEvent, Plack::Server::Coro and
Plack::Server::POE.

If C<asynchronous> is not used, your application is supposed to run in
any PSGI standard environments, including blocking multiprocess
environments like mod_perl2 and prefork.

=head1 TATSUMAKI?

Tatsumaki is a Japanese for Tornado. Also, it might sound familiar
from "Tatsumaki Senpuukyaku" of Ryu from Street Fighter II if you
loved the Capcom videogame back in the day :)

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<AnyEvent> L<Plack> L<PSGI>

=cut
