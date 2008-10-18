#!perl
use strict;
#use warnings;

use Cwd;
use Test::More 'no_plan';

use lib "lib";

BEGIN {
    use_ok('Mail::Toaster::Utility');
    use_ok('Mail::Toaster::Setup');
}
require_ok('Mail::Toaster::Utility');
require_ok('Mail::Toaster::Setup');

my $util = Mail::Toaster::Utility->new;
# read in the .conf file
my $conf = $util->parse_config( file => "toaster-watcher.conf", debug => 0 );

# basic OO mechanism
my $setup = Mail::Toaster::Setup->new(conf=>$conf);     # create an object
ok( defined $setup, 'new Mail::Toaster::Setup object)' );    # check it
ok( $setup->isa('Mail::Toaster::Setup'), 'setup object class' );



my $initial_working_directory = cwd;

my @subs_to_test = qw/ apache autorespond clamav courier_imap cronolog
  daemontools djbdns expat ezmlm mysql openssl_conf
  qmail_scanner razor simscan spamassassin vpopmail vqadmin /;

my $debug = 0;

foreach my $sub (@subs_to_test) {

    my $install_sub = "install_$sub";
    my $before      = $conf->{$install_sub};    # preserve initial settings

    $conf->{$install_sub} = 1;                  # enable install in $conf

    # test to insure params and initial tests are passed
    ok(  $setup->$sub( test_ok => 1, debug => $debug ), $sub );
    ok( !$setup->$sub( test_ok => 0, debug => $debug ), $sub );

    $conf->{$install_sub} = 0;                  # disable install

    # and then make sure it fails to install
    ok( !$setup->$sub( debug => $debug ), $sub );

    # set $conf->install_sub back to its initial state
    $conf->{$install_sub} = $before;
}

# config
ok( $setup->config( test_ok => 1, debug => 0, fatal => 0 ),
    'config' );
ok( !$setup->config( test_ok => 0, debug => 0, fatal => 0 ),
    'config' );

# dependencies
ok( $setup->dependencies( test_ok => 1 ), 'dependencies' );
ok( !$setup->dependencies( test_ok => 0, debug => 1 ),
    'dependencies' );

#ok ( $setup->dependencies( debug=>1 ), 'dependencies' );

# filtering
ok( $setup->filtering( test_ok => 1 ), 'filtering' );
ok( !$setup->filtering( test_ok => 0, debug => 1 ),
    'filtering' );

# is_newer
    ok ($setup->is_newer( min=>"5.3.30", cur=>"5.3.31", debug=>0), 'is_newer third');
    ok ($setup->is_newer( min=>"5.3.30", cur=>"5.4.30", debug=>0), 'is_newer second');
    ok ($setup->is_newer( min=>"5.3.30", cur=>"6.3.30", debug=>0), 'is_newer first');
    ok (! $setup->is_newer( min=>"5.3.30", cur=>"5.3.29", debug=>0), 'is_newer third neg');
    ok (! $setup->is_newer( min=>"5.3.30", cur=>"5.2.30", debug=>0), 'is_newer second neg');
    ok (! $setup->is_newer( min=>"5.3.30", cur=>"4.3.30", debug=>0), 'is_newer first neg');

# nictool
ok( $setup->nictool( test_ok => 1 ), 'nictool' );
ok( !$setup->nictool( test_ok => 0, debug => 1 ), 'nictool' );

# set this back to where we started so subsequent testing scripts work
chdir($initial_working_directory);



1;
