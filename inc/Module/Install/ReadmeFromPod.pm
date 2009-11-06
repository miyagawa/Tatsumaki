#line 1
package Module::Install::ReadmeFromPod;

use strict;
use warnings;
use base qw(Module::Install::Base);
use vars qw($VERSION);

$VERSION = '0.06';

sub readme_from {
  my $self = shift;
  return unless $Module::Install::AUTHOR;
  my $file = shift || return;
  my $clean = shift;
  require Pod::Text;
  my $parser = Pod::Text->new();
  open README, '> README' or die "$!\n";
  $parser->output_fh( *README );
  $parser->parse_file( $file );
  return 1 unless $clean;
  $self->postamble(<<"END");
distclean :: license_clean

license_clean:
\t\$(RM_F) README
END
  return 1;
}

'Readme!';

__END__

#line 89

