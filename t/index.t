#!/usr/bin/perl
#
# $Id: CGI.t,v 4.20 2004/11/16 20:57:31 matt Exp $
#

use strict;
use warnings;
use Test::More;

use lib "lib";

eval "use HTML::Template";
if ($@) {
    plan skip_all => "HTML::Template required for index.cgi usage";
}
else {
    plan 'no_plan';
};

BEGIN { use_ok( 'Mail::Toaster::CGI') };
require_ok ( 'Mail::Toaster::CGI' );


# basic OO mechanism
    my $cgi = Mail::Toaster::CGI->new;                       # create an object
    ok ( defined $cgi, 'new (get a Mail::Toaster::CGI object)' );    # check it
    ok ( $cgi->isa('Mail::Toaster::CGI'), 'CGI object class' );   # is it the right class


ok( system "./cgi_files/index.cgi", 'index.cgi');
