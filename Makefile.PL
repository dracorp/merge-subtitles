use ExtUtils::MakeMaker 6.48;

eval "use Test::Manifest 1.21";

my $script_name = "join-subs.pl";

WriteMakefile(
		'NAME'      => $script_name,
		'VERSION'   => '0.10',

		'EXE_FILES' =>  [ $script_name ],

		'PREREQ_PM' => {
 			},


		MIN_PERL_VERSION => 5,

		clean => { FILES => "*.bak $script_name-*" },
		);

1;
