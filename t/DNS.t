#!/usr/bin/perl
#
# $Id: DNS.t,v 4.20 2004/11/16 20:57:31 matt Exp $
#

use strict;
use warnings;
use Test::More 'no_plan';
use English qw( -no_match_vars );

use lib "inc";
use lib "lib";

BEGIN { use_ok( 'Mail::Toaster::DNS') };
require_ok ( 'Mail::Toaster::DNS' );

# basic OO mechanism
    my $dns = Mail::Toaster::DNS->new;                       # create an object
    ok ( defined $dns, 'new (get a Mail::Toaster::DNS object)' );    # check it
    ok ( $dns->isa('Mail::Toaster::DNS'), 'dns object class' );   # is it the right class


# rbl_test_ns
	ok( $dns->rbl_test_ns(rbl=>"sbl.spamhaus.org",debug=>0), 'rbl_test_ns');

	# a query that should fail
	ok( ! $dns->rbl_test_ns(rbl=>"sbl.spamhorse.org",debug=>0), 'rbl_test_ns');


# rbl_test_positive_ip
	ok( $dns->rbl_test_positive_ip(rbl=>"sbl.spamhaus.org",debug=>0), 'rbl_test_positive_ip');

	# a query that should fail
	ok( ! $dns->rbl_test_positive_ip(rbl=>"sbl.spamhorse.org",debug=>0), 'rbl_test_positive_ip');


# rbl_test_negative_ip
	ok( $dns->rbl_test_negative_ip(rbl=>"sbl.spamhaus.org",debug=>0), 'rbl_test_negative_ip');

	# a query that should fail
	ok( $dns->rbl_test_negative_ip(rbl=>"sbl.spamhorse.org",debug=>0), 'rbl_test_negative_ip');


# rbl_test
	ok( $dns->rbl_test(zone=>"sbl.spamhaus.org", debug=>0), 'rbl_test');

	# a query that should fail
	ok( ! $dns->rbl_test(zone=>"sbl.spamhorse.org", debug=>0), 'rbl_test');


# resolve
    my $ip;
    ok( ($ip) = $dns->resolve( record=>"www.freebsd.org", type=>"A",debug=>0), 'resolve A');
    ok( $dns->resolve( record=>"freebsd.org", type=>"NS",debug=>0), 'resolve NS');
    #ok( $dns->resolve( record=>$ip, type=>"PTR",), 'resolve PTR');
