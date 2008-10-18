#!perl
use strict;
#use warnings;

use lib "lib";

use Config;
use English qw( -no_match_vars );
use Test::More 'no_plan';

require_ok( 'Mail::Toaster::Utility' );

# basic OO mechanism
my $util = Mail::Toaster::Utility->new;
ok ( defined $util, 'get Mail::Toaster::Utility object' );
ok ( $util->isa('Mail::Toaster::Utility'), 'check object class' );

my $conf = $util->parse_config( file => "toaster-watcher.conf", debug => 0 );

my $qqtool_location = "bin/qqtool.pl";

ok( -e $qqtool_location, 'found qqtool.pl');
ok( -x $qqtool_location, 'is executable');

my $queue = $conf->{'qmail_dir'} . "/queue";

### $queue
### require: -d $queue
### require: -r $queue

my $this_perl = $EXECUTABLE_NAME;
if ($OSNAME ne 'VMS')
    {$this_perl .= $Config{_exe}
        unless $this_perl =~ m/$Config{_exe}$/i;}

ok( $util->syscmd(
        command => "$this_perl $qqtool_location -a list -s matt -h From ",
        fatal   => 0,
        debug   => 0,
    ), 'qqtool.pl' );
