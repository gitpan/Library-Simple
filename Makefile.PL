use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Library::Simple',
    'VERSION_FROM'	=> 'Simple.pm', # finds $VERSION
    'PREREQ_PM'		=> {
		Library::Thesaurus => 0.12,
		Library::MLang => 0.04,
			    }, # e.g., Module::Name => 1.1
);
