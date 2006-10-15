#!/usr/bin/perl
#
# $Id: Provision.t, Exp $
#
use strict;
use warnings;
use English qw( -no_match_vars );
use Test::More 'no_plan';

use lib "inc";
use lib "lib";

BEGIN { use_ok( 'Mail::Toaster::Provision' ); }
require_ok( 'Mail::Toaster::Provision' );

# let the testing begin

# basic OO mechanism
	my $prov = Mail::Toaster::Provision->new;                       # create an object
	ok ( defined $prov, 'get Mail::Toaster::Provision object' );    # check it
	ok ( $prov->isa('Mail::Toaster::Provision'), 'check object class' );   # is it the right class


# quota_set
	my $mod = "Quota";
    if (eval "require $mod") 
    {
		ok ( $prov->quota_set( user=>'matt', debug=>0 ), 'quota_set');
	};

# user
	#ok ( $prov->user ( vals=>{action=>'create', user=>'matt2'} ), 'user');

# web
	#ok ( $prov->web ( vals=>{action=>'create', vhost=>'foo.com'} ), 'web');



# what_am_i
	ok ( $prov->what_am_i(), 'what_am_i');


