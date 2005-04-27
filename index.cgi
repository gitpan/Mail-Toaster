#!/usr/bin/perl
use strict;

#
# $Id: index.cgi,v 4.2 2005/03/21 16:20:52 matt Exp $
#

use vars qw/ $VERSION /;

$VERSION = "4.00";

use CGI qw(:standard);
use CGI::Carp qw( fatalsToBrowser );

use Mail::Toaster::Perl;      my $perl    = Mail::Toaster::Perl->new();
use Mail::Toaster::CGI;       my $mt_cgi  = Mail::Toaster::CGI->new();
use Mail::Toaster::Utility 1; my $utility = Mail::Toaster::Utility->new();

$perl->module_load( {module=>"HTML::Template", ports_name=>"p5-HTML-Template", ports_group=>"www"} );

$mt_cgi->process_shell() unless $ENV{'GATEWAY_INTERFACE'};

my $cgi      = new CGI;
my $template = HTML::Template->new(filename => 'index.tmpl');
my $editable = 1;
my $email    = $cgi->param('email'); 
my $c_email  = $cgi->cookie('email');
my $save     = $cgi->param('save');
my $logout   = $cgi->param('logout');
my $ssl      = $cgi->param('ssl');
my ($host, $debug);
my $stats    = 0;

my $conf     = $utility->parse_config({file=>"toaster.conf",debug=>$debug});
die "FAILURE: Could not find toaster.conf!\n" unless $conf;

if    ( $save )                 { $editable = 0; }
elsif ( $c_email && ! $logout ) { $editable = 0; };

unless ( $email && $email ne "email address" ) { 
	$email = $c_email if ( $c_email); 
};

unless ( $ssl ) { 
	if ( $cgi->cookie('ssl') ) { $ssl = 1; } else { $ssl = 0; };
};

if ( ! $host || $host eq "me" ) 
{
	my $hosturl = $cgi->url(-base=>1);
	($host) = $hosturl =~ /http[s]?:\/\/(.*):?[0-9]?$/;
};

if ( $save ) 
{ 
	print $cgi->header(-cookie => $mt_cgi->cookies_set($cgi, $email, $ssl, $host) );
} 
elsif ( $logout ) {
	print $cgi->header(-cookie => $mt_cgi->cookies_expire($cgi, $email, $ssl, $host) );
}
else { print $cgi->header('text/html'); };

if ( $conf->{'web_squirrelmail'} ) {
	$template->param(squirrelmail => $mt_cgi->squirrelmail_submit($conf, $ssl, $host) );
}
else { $template->param(squirrelmail => "" ); };

if ( $conf->{'web_sqwebmail'} ) {
	$template->param(sqwebmail => $mt_cgi->sqwebmail_submit($conf, $ssl, $host) );
}
else { $template->param(sqwebmail => ""); };

if ( $conf->{'web_v-webmail'} ) {
	$template->param(vwebmail => $mt_cgi->vwebmail_submit($conf, $ssl, $host) );
}
else { $template->param(vwebmail => ""); };

if ( $conf->{'web_imp'} ) {
	$template->param(imp => $mt_cgi->imp_submit($conf, $ssl, $host) );
}
else { $template->param(imp => ""); };

if ( $conf->{'web_qmailadmin'} ) {
	$template->param(qmailadmin => $mt_cgi->qmailadmin_submit($conf, $ssl, $host) );
}
else { $template->param(qmailadmin => ""); };

if ( $conf->{'web_rrdutil'} ) { $stats++;
	$template->param(rrdutil => $mt_cgi->rrdutil_submit($conf, $ssl, $host) );
} 
else { $template->param(rrdutil => ""); };

if ( $conf->{'web_isoqlog'} ) { $stats++;
	$template->param(isoqlog => $mt_cgi->isoqlog_submit($conf, $ssl, $host) );
}
else { $template->param(isoqlog => ""); };

if ( $conf->{'web_qs_stat'} ) { $stats++;
	$template->param(qs_stat => $mt_cgi->qss_stats_submit($conf, $ssl, $host) );
}
else { $template->param(qs_stat => ""); };

$template->param(head     => $mt_cgi->heading      ($conf            ) );
$template->param(instruct => $mt_cgi->instructions ($conf            ) );
$template->param(logo     => $mt_cgi->logo         ($conf            ) );
$template->param(email    => $mt_cgi->email_line   ($email, $editable) );
$template->param(save     => $mt_cgi->cookie_line  ($editable        ) );
$template->param(ssl      => $mt_cgi->ssl_line     ($ssl, $editable  ) );
$template->param(host     => $host);
$template->param(version  => $VERSION);
$template->param(stats    => $stats);

print $template->output;

exit 1;
__END__


=head1 LICENSE

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

