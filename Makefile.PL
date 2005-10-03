# $Id$

use ExtUtils::MakeMaker;

# Touch auto-generated files so we don't see warnings.
open(CHANGES, ">>CHANGES") and close CHANGES;
open(README, ">>README")   and close README;

WriteMakefile(
  NAME         => 'POE::Stage',
  AUTHOR       => 'Rocco Caputo <rcaputo@cpan.org>',
  ABSTRACT     => 'a prototype of a successor to POE::Component',
  VERSION_FROM => 'lib/POE/Stage.pm',
  PREREQ_PM    => {
    POE        => 0.31,
    Test::More => 0,
  },
  dist         => {
    COMPRESS   => 'gzip -9f',
    SUFFIX     => 'gz',
    PREOP      => (
      'svn-log.perl | tee ./$(DISTNAME)-$(VERSION)/CHANGES > ./CHANGES;' .
			'perldoc lib/POE/Stage.pm > README'
    ),
  },
);
