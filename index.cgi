#!/usr/bin/perl
use strict;

#
# $Id: index.cgi,v 1.10 2004/02/14 22:26:25 matt Exp $
#

use vars qw/ $VERSION /;

$VERSION = "1.8";

use CGI qw(:standard);
use CGI::Carp qw( fatalsToBrowser );

use MATT::Utility 1;
use MATT::Perl;
use Mail::Toaster::CGI;

LoadModule("HTML::Template", "p5-HTML-Template", "www");

ProcessShell() unless $ENV{'GATEWAY_INTERFACE'};

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

my $conf     = ParseConfigFile("toaster.conf", $debug);
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
	print $cgi->header(-cookie => SetCookies($cgi, $email, $ssl, $host) );
} 
elsif ( $logout ) {
	print $cgi->header(-cookie => ExpireCookies($cgi, $email, $ssl, $host) );
}
else { print $cgi->header('text/html'); };

if ( $conf->{'web_squirrelmail'} ) {
	$template->param(squirrelmail => SetSquirrelmailSubmit($conf, $ssl, $host) );
}
else { $template->param(squirrelmail => "" ); };

if ( $conf->{'web_sqwebmail'} ) {
	$template->param(sqwebmail => SetSqwebmailSubmit ($conf, $ssl, $host) );
}
else { $template->param(sqwebmail => ""); };

if ( $conf->{'web_qmailadmin'} ) {
	$template->param(qmailadmin => SetQmailadminSubmit($conf, $ssl, $host) );
}
else { $template->param(qmailadmin => ""); };

if ( $conf->{'web_rrdutil'} ) { $stats++;
	$template->param(rrdutil => SetRRDutilSubmit($conf, $ssl, $host) );
} 
else { $template->param(rrdutil => ""); };

if ( $conf->{'web_isoqlog'} ) { $stats++;
	$template->param(isoqlog => SetIsoqlogSubmit($conf, $ssl, $host) );
}
else { $template->param(isoqlog => ""); };

if ( $conf->{'web_qs_stat'} ) { $stats++;
	$template->param(qs_stat => SetQSStatsSubmit($conf, $ssl, $host) );
}
else { $template->param(qs_stat => ""); };

$template->param(head     => SetHeading     ($conf            ) );
$template->param(instruct => SetInstruct    ($conf            ) );
$template->param(logo     => SetLogo        ($conf            ) );
$template->param(email    => SetEmailLine   ($email, $editable) );
$template->param(save     => SetCookieLine          ($editable) );
$template->param(ssl      => SetSSLLine       ($ssl, $editable) );
$template->param(host     => $host);
$template->param(version  => $VERSION);
$template->param(stats    => $stats);

print $template->output;

exit 1;

##
# Subs
##

sub SetInstruct
{
	my ($conf) = @_;

	my $inst = $conf->{'web_instructions'};
	unless ($inst) { $inst = "To check your mail, fill in the account info and select a destination."; };
	return $inst;
};

sub SetHeading
{
	my ($conf) = @_;

	my $descr = $conf->{'web_heading_text'};
	unless ($descr) { $descr = "Mail Center"; };
	return $descr;
};

sub SetLogo
{
	my ($conf) = @_;

	my $logo = $conf->{'web_logo_url'};
	my $text = $conf->{'web_logo_alt_text'};

	unless ($logo) { $logo = "/images/logo.jpg"; };
	unless ($text) { $text = "example.com logo"; };

	return "<img src=\"$logo\" alt=\"$text\">";
};


