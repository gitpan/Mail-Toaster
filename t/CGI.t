#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: CGI.t,v 4.0 2004/11/16 20:57:31 matt Exp $
#

use lib "inc";
use lib "lib";
use Test::More 'no_plan';


BEGIN {
    use_ok('Mail::Toaster::CGI');
}
require_ok('Mail::Toaster::CGI');

ok( Mail::Toaster::CGI->new(), 'new' );

