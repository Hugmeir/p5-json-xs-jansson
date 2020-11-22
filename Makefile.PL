use strict;
use warnings;
use 5.008_008;

use Config;
use ExtUtils::MakeMaker;
use Getopt::Long;
use Alien::libjansson;

my $lddlflags    = $Config{'lddlflags'};
WriteMakefile(
    'INC'          => Alien::libjansson->cflags,
    'LDDLFLAGS'    => $lddlflags . ' ' . Alien::libjansson->libs_static,
    'NAME'         => 'JSON::XS::Jansson',
    'VERSION_FROM' => 'lib/JSON/XS/Jansson.pm',
    'META_MERGE'   => {
        'meta-spec' => { version => 2 },
        prereqs => {
            test => {
                requires => {
                    version => '0.77',
                },
            },
            configure => {
                requires => {
                    'Alien::libjansson' => '0.02',
                },
            },
        },
        resources => {
            homepage   => "https://github.com/hugmeir/p5-json-xs-jansson",
            bugtracker => {
                web => "https://github.com/hugmeir/p5-json-xs-jansson/issues",
            },
            repository => {
                web  => "https://github.com/hugmeir/p5-json-xs-jansson",
                url  => "https://github.com/hugmeir/p5-json-xs-jansson.git",
                type => 'git',
            },
        },
    },
);

