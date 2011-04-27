use 5.010001;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'InternetBanking-HSBC-UK-Personal',
    VERSION_FROM      => 'lib/InternetBanking/HSBC/UK/Personal.pm',
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT       => 'Module for interacting with HSBC UK personal internet banking',
       AUTHOR         => 'James Telford <james@tefd.co.uk>') : ()),
    EXE_FILES         => [ 'scripts/hsbc-ib.pl' ],
);
