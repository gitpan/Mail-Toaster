#!/usr/bin/perl
#
# $Id: CGI.t,v 4.20 2004/11/16 20:57:31 matt Exp $
#

use strict;
use warnings;
use Test::More;

use lib "inc";
use lib "lib";

eval "use HTML::Template";
if ($@) {
    plan skip_all => "HTML::Template required for index.cgi usage";
}
else {
    plan 'no_plan';
};

require_ok ( 'Mail::Toaster::CGI' );


# basic OO mechanism
my $cgi = Mail::Toaster::CGI->new;
ok ( defined $cgi, 'new (get a Mail::Toaster::CGI object)' );
ok ( $cgi->isa('Mail::Toaster::CGI'), 'CGI object class' );


ok( system "./cgi_files/index.cgi", 'index.cgi');
