#!perl

use strict;
#use warnings;

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "lib";

BEGIN { use_ok( 'Mail::Toaster::Perl' ); }
require_ok( 'Mail::Toaster::Perl' );

# let the testing begin

# basic OO mechanism
my $perl = Mail::Toaster::Perl->new;                       # create an object
ok ( defined $perl, 'get Mail::Toaster::Perl object' );    # check it
ok ( $perl->isa('Mail::Toaster::Perl'), 'check object class' ); # is it the right class


ok( $perl->check(debug=>0), 'version check');

ok( $perl->module_load( 
		module     => "CGI",
		port_name  => "p5-CGI",
		port_group => "www",
		timer      => 10,
        fatal      => 0,
	), 'module_load');

ok( $perl->check(debug=>0), 'version check');

#ok( $perl->perl_install(version=>'perl-5.8', debug=>1), 'install');
