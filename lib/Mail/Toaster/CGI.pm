#!/usr/bin/perl
use strict;

#
# $Id: CGI.pm,v 1.15 2004/02/16 17:00:43 matt Exp $
#

package Mail::Toaster::CGI;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION  = '1.10';

@ISA = qw(Exporter);
@EXPORT = qw( 
	SetQSStatsSubmit
	SetIsoqlogSubmit
	SetRRDutilSubmit
	ExpireCookies
	SetQmailadminSubmit
	SetSqwebmailSubmit
	SetSquirrelmailSubmit
	SetCookies
	SetSSLLine
	SetCookieLine
	SetEmailLine
	ProcessShell
);
@EXPORT_OK = qw();

=head1 NAME

Mail::Toaster::CGI


=head1 SYNOPSIS

index.cgi - A pretty web interface that showcases the abundant features of a mail toaster.

This module contains the subroutines that are used by index.cgi. They're named well so you should have no problems reading through index.cgi and understanding exactly what it's doing.


=head1 DESCRIPTION

A cgi application and HTML template for a standard mail page.

=cut


sub SetQSStatsSubmit($$$)
{

=head2 SetQSStatsSubmit

	use Mail::Toaster::CGI;
	SetQSStatsSubmit($conf, $ssl, $host);

Generate the HTML code that renders the Qmail Scanner Statistics table and form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection, $host is the hostname to submit the form to, and $path is the path to isoqlog on the remote server. A typical invocation might look like this:

	SetIsoqlogSubmit($conf, 1, "matt.cadillac.net" );

=cut

	my ($conf, $ssl, $host) = @_;
	my ($http);

	my $path    = $conf->{'web_qs_stat_url'};
	my $qs_ssl  = $conf->{'web_qs_stat_require_ssl'};
	my $qshost  = $conf->{'web_qs_stat_host'};
	my $name    = $conf->{'web_qs_stat_name'};
	my $descrip = $conf->{'web_qs_stat_description'};

    if ( $qs_ssl ) { $http = "https" }
    else {
        if ( $ssl) { $http = "https" }
        else       { $http = "http" };
    };

	unless ( $qshost ) { $qshost = $host; };
	unless ( $path   ) { $path = "/qss/index.php"; };

	return '
		<tr>
			<form method="post" name="qss" action="' .  $http .'://'. $qshost . $path .'">
			<td width="20" height="3"></td>
			<td width="25"><input type="submit" value="Go"></td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
			</form>
		</tr>';
};


sub SetIsoqlogSubmit($$$)
{

=head2 SetIsoqlogSubmit

	use Mail::Toaster::CGI;
	SetIsoqlogSubmit($conf, $ssl, $host);

Generate the HTML code that renders the Isoqlog table and form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection, $host is the hostname to submit the form to. A typical invocation might look like this:

	SetIsoqlogSubmit($conf, 1, "matt.cadillac.net");

=cut


	my ($conf, $ssl, $host) = @_;
	my ($http);

	my $path    = $conf->{'web_isoqlog_url'};
	my $isossl  = $conf->{'web_isoqlog_require_ssl'};
	my $isohost = $conf->{'web_isoqlog_host'};
	my $name    = $conf->{'web_isoqlog_name'};
	my $descrip = $conf->{'web_isoqlog_description'};

    if ( $isossl ) { $http = "https" }
    else {
        if ( $ssl) { $http = "https" }
        else       { $http = "http" };
    };

    unless ( $isohost ) { $isohost = $host; };
	unless ( $path    ) { $path = "/isoqlog/"; };

	return '
		<tr>
			<form method="post" name="isoqlog" action="' .  $http .'://'. $isohost . $path .'">
			<td width="20" height="3"></td>
			<td width="25"><input type="submit" value="Go"></td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
			</form>
		</tr>';
};

sub SetRRDutilSubmit($$$)
{

=head2 SetRRDutilSubmit

	use Mail::Toaster::CGI;
	SetRRDutilSubmit($conf, $ssl, $host);

Generate the HTML code that renders the table and embedded form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection. $host is the hostname to submit the form to.

=cut


	my ($conf, $ssl, $host) = @_;
	my ($http);

	my $path    = $conf->{'web_rrdutil_url'};
	my $rrdssl  = $conf->{'web_rrdutil_require_ssl'};
	my $rrdhost = $conf->{'web_rrdutil_host'};
	my $name    = $conf->{'web_rrdutil_name'};
	my $descrip = $conf->{'web_rrdutil_description'};

	unless ( $rrdhost) { $rrdhost = $host; };
	unless ( $path   ) { $path = "/cgi-bin/rrdutil.cgi"; };

	if ( $rrdssl ) { $http = "https" } 
	else { 
		if ( $ssl) { $http = "https" }
		else       { $http = "http" };
	};

	return '
	<tr>
		<form method="post" name="rrdutil" action="'.$http.'://'. $rrdhost . $path.'">
			<input type="hidden" name="mail" value="on">
			<input type="hidden" name="days" value="1">
			<input type="hidden" name="hostname" value="localhost">
		<td width="20" height="3"></td>
		<td width="25"><input type="submit" value="Go"></td>
		<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
		</form>
	</tr>';
};

sub ExpireCookies($$$$)
{

=head2 ExpireCookies

Very simple use of CGI's cookie method. To expire the cookie we just set it's expiration to a negative value.

=cut

	my ($cgi, $email, $ssl, $host) = @_;
	my @cookies;

	my $cookie1 = $cgi->cookie(
		-name=>'email',
		-value=> $email,
		-expires=>'-1d',
		-domain=>$host,
		-secure=>$ssl
	);

	my $cookie3 = $cgi->cookie(
		-name=>'ssl',
		-value=> $ssl,
		-expires=>'-1d',
		-domain=>$host,
		-secure=>$ssl
	);

	push @cookies, $cookie1;
	push @cookies, $cookie3;

	return \@cookies;
};

sub SetQmailadminSubmit($$$)
{

=head2 SetQmailadminSubmit

	use Mail::Toaster::CGI;
	SetQmailadminSubmit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.

=cut

	my ($conf, $ssl, $host) = @_;
	my ($http);

	my $path    = $conf->{'web_qmailadmin_url'};
	my $qmassl  = $conf->{'web_qmailadmin_require_ssl'};
	my $qmahost = $conf->{'web_qmailadmin_host'};
	my $name    = $conf->{'web_qmailadmin_name'};
	my $descrip = $conf->{'web_qmailadmin_description'};

	if ( $qmassl ) { $http = "https" } 
	else { 
		if ( $ssl) { $http = "https" }
		else       { $http = "http" };
	};

	unless ( $qmahost ) { $qmahost = $host; };
	unless ( $path    ) { $path = "/cgi-bin/qmailadmin"; };

	my $line = '
		<tr>
			<form method="post" name="admin" action="' .  $http .'://'. $qmahost . $path .'">
				<input type="hidden" name="username" value="">
				<input type="hidden" name="domain" value="">
				<input type="hidden" name="password" value="">
			<td width="20" valign="middle" align="center"></td>
			<td width="25">
				<input type="submit" value="Go" onclick="copydata(\'admin\')">
			</td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
			</form>
		</tr> ';

	return $line;
};

sub SetSqwebmailSubmit($$$)
{

=head2 SetSqwebmailSubmit

	use Mail::Toaster::CGI;
	SetSqwebmailSubmit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.

=cut

	my ($conf, $ssl, $host) = @_;
	my ($http);

	my $path    = $conf->{'web_sqwebmail_url'};
	my $sqwssl  = $conf->{'web_sqwebmail_require_ssl'};
	my $sqwhost = $conf->{'web_sqwebmail_host'};
	my $name    = $conf->{'web_sqwebmail_name'};
	my $descrip = $conf->{'web_sqwebmail_description'};

	if ( $sqwssl ) { $http = "https" }
	else {
		if ( $ssl) { $http = "https" }
		else       { $http = "http" };
	};
    
	unless ( $sqwhost ) { $sqwhost = $host; };
	unless ( $path    ) { $path = "/cgi-bin/sqwebmail"; };

	return '
		<tr>
			<form method="post" name="sqweb" action="' .  $http .'://'. $sqwhost . $path .'">
				<input type="hidden" name="username" value="">
				<input type="hidden" name="password" value="">
				<input type="hidden" name="sameip" value="1">
			<td width="20" valign="middle" align="center"> </td>
			<td width="25"><p>
				<input type="submit" value="Go" onclick="copydata(\'sqweb\')"></p></td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
			</form>
		</tr>   
		<!--<tr>
				<td width="20" valign="middle" align="center">
				<td colspan="2" align="right" valign="middle"><font size="-1">Time Zone: 
					<select name="timezonelist">
						<option value="">
						<option value="EST5EDT">US Eastern
						<option value="EST">US Eastern/Indiana
						<option value="CST6/CDT">US Central
						<option value="MST7MDT">US Mountain
						<option value="MST">US Mountain/Arizona
						<option value="PST8PDT">US Pacific
					</select>
				</td>
			</tr>-->';

};

sub SetSquirrelmailSubmit($$$)
{

=head2 SetSquirrelmailSubmit

	use Mail::Toaster::CGI;
	SetSquirrelmailSubmit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.  $path is the installed URL path on the server.


=cut


	my ($conf, $ssl, $host) = @_;
	my $http;

	my $path    = $conf->{'web_squirrelmail_url'};
	my $squssl  = $conf->{'web_squirrelmail_require_ssl'};
	my $squhost = $conf->{'web_squirrelmail_host'};
	my $name    = $conf->{'web_squirrelmail_name'};
	my $descrip = $conf->{'web_squirrelmail_description'};

	if ( $squssl ) { $http = "https" }
	else {
		if ( $ssl) { $http = "https" }
		else       { $http = "http" };
	};

	unless ( $squhost ) { $squhost = $host; };
	unless ( $path    ) { $path = "/squirrelmail/src/redirect.php"; };

	return '
		<tr>
			<form method="post" name="squirrel" action="' .  $http .'://'. $squhost . $path .'">
				<input type="hidden" name="login_username" value="">
				<input type="hidden" name="secretkey" value="">
			<td width="20" valign="middle" align="center">
				<p><font size="+1" color="green"> 3 </font></p></td>
			<td width="25"><input type="submit" value="Go" onclick="copydata(\'squirrel\')"></td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
			</form>
		</tr>
		<tr>
			<td colspan="3" height="3" width="3"></td>
		</tr>';
};

sub SetCookies($$$$)
{

=head2 SetCookies

Very simple use of CGI's cookie method. We save a cookie with the users email address and another one for for whether they selected Use SSL.

=cut

	my ($cgi, $email, $ssl, $host) = @_;
	my @cookies;
	
	my $cookie1 = $cgi->cookie (
		-name=>'email',
		-value=> $email,
		-expires=>'+1y',
#		-path=>'/check.cgi',
		-domain=>$host,
		-secure=>$ssl
	);

	my $cookie3 = $cgi->cookie (
		-name=>'ssl',
		-value=> $ssl,
		-expires=>'+1y',
#		-path=>'/check.cgi',
		-domain=>$host,
		-secure=>$ssl
	);

	push @cookies, $cookie1;
	push @cookies, $cookie3;

	return \@cookies;
};

sub SetSSLLine($$)
{

=head2 SetSSLLine

	use Mail::Toaster::CGI;
	SetSSLLine($ssl, $editable);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $editable is a binary value, determining if the SSL preference is available or not.  

=cut

	my ($ssl, $editable) = @_;

	if ( $editable )
	{
		if ( $ssl ) {
			return '<input type="checkbox" name="ssl" checked onClick="submit()">';
		} else {
			return '<input type="checkbox" name="ssl" / onClick="submit()">';
		};
	} 
	else
	{
		if ( $ssl ) {
			return '<input type="hidden" name="ssl" value="1"> <font color="green">selected</font>';
		} else {
			return '<input type="hidden" name="ssl" value="0"> <font color="green">disabled</font>';
		};
	};
};

sub SetCookieLine($)
{

=head2 SetCookieLine

	use Mail::Toaster::CGI;
	SetCookieLine($save);

$save is a binary value, are the users settings saved or not?

=cut

	my ($save) = @_;

	if ( $save )
	{
		return '<input type="checkbox" name="save" onClick="submit()"> Save My Settings <input type="submit" value="Yes">';
	} 
	else 
	{
		return '<a href="index.cgi?logout=1">change my settings </a>';
	};
};

sub SetEmailLine($$)
{

=head2 SetEmailLine

	use Mail::Toaster::CGI;
	SetEmailLine($address, $editable);

$address is the email address to display in the form.

$editable is whether or not the address field is editable.

=cut

	my ($address, $editable) = @_;

	unless ( $address ) { $address = "email address"; };

	if ( ! $editable)
	{
		return '<input name="email" type="hidden" id="email" value="' . $address . '"><font color="green">' .$address.'</font>';
	}
	else 
	{
		return '<input name="email" type="text" id="email" size="20" value="'.$address.'" onFocus="if(this.value==\'email address\')this.value=\'\';">';
	};
};

sub ProcessShell()
{

=head2 ProcessShell

Since we're a CGI app, we don't expect to be run from the command line except to test. This little sub just lets you know everything that was supposed to load did and that the CGI should work right.

=cut

	print "exiting normally\n";
	exit 1;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

Wow, TODO is caught up. Yay!


=head1 SEE ALSO

Mail::Toaster::CGI, Mail::Toaster::DNS, Mail::Toaster::Logs,
Mail::Toaster::Qmail, Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc. All Rights Reserved.

=cut
