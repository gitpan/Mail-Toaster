#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: CGI.pm,v 4.9 2005/06/10 22:54:12 matt Exp $
#

package Mail::Toaster::CGI;

use Carp;
use vars qw($VERSION);
$VERSION = '5.01';

use lib "lib";


sub new {

    my $class = shift;
    my $self = { class => $class };
    bless( $self, $class );
    return $self;
}

sub only {
    $_ = shift;
    /([A-Za-z0-9-_]+)/;
    return $1;
}

sub instructions {

    my ( $self, $conf ) = @_;

    my $inst = $conf->{'web_instructions'};
    $inst ||=
      "To check your mail, fill in the account info and select a destination.";
    return $inst;
}

sub logo {



    my ( $self, $conf ) = @_;

    my $logo = $conf->{'web_logo_url'};
    $logo ||= "/images/logo.jpg";
    my $text = $conf->{'web_logo_alt_text'};
    $text ||= "example.com logo";

    return "<img src=\"$logo\" alt=\"$text\">";
}

sub heading {


    my ( $self, $conf ) = @_;

    my $descr = $conf->{'web_heading_text'};
    $descr ||= "Mail Center";
    return $descr;
}

sub imp_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path    = $conf->{'web_imp_url'};
    my $impssl  = $conf->{'web_imp_require_ssl'};
    my $imphost = $conf->{'web_imp_host'};
    my $name    = $conf->{'web_imp_name'};
    my $descrip = $conf->{'web_imp_description'};

    if ($impssl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $imphost ||= $host;
    $path    ||= "/horde/imp/redirect.php";

    return '
		<tr>
			<td width="20" valign="middle" align="center"> </td>
			<td width="25">
			  <form method="post" name="implogin" action="' . $http . '://' . $imphost
      . $path . '">
				<input type="hidden" name="imapuser" value="">
				<input type="hidden" name="pass" value="">
				<input type="hidden" name="actionID" value="105" />
				<input type="hidden" name="url" value="" />
				<input type="hidden" name="mailbox" value="INBOX" />
                <input type="hidden" name="server" value="locahost" />
                <input type="hidden" name="port" value="143" />
                <input type="hidden" name="namespace" value="" />
                <input type="hidden" name="maildomain" value="mail.tnpi.biz" />
                <input type="hidden" name="protocol" value="imap" />
                <input type="hidden" name="realm" value="" />
                 <input type="hidden" name="folders" value="Mail/" />
                 <input type="hidden" name="new_lang" value="en_US/" />
                            <input type="submit" value="'
      . only($name)
      . '" onclick="copydata(\'imp\')">
			  </form>
                        </td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
		</tr>
		<tr>
			<td colspan="3" height="3" width="3"></td> 
        </tr>';
}

sub vwebmail_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path     = $conf->{'web_v-webmail_url'};
    my $vwebssl  = $conf->{'web_v-webmail_require_ssl'};
    my $vwebhost = $conf->{'web_v-webmail_host'};
    my $name     = $conf->{'web_v-webmail_name'};
    my $descrip  = $conf->{'web_v-webmail_description'};

    if ($vwebssl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $vwebhost ||= $host;
    $path     ||= "/v-webmail/login.php?vwebmailsession=";

    return '
		<tr>
			<td width="20" valign="middle" align="center"> </td>
			<td width="25">
 			   <form method="post" name="vweb" action="' . $http . '://'
      . $vwebhost
      . $path . '">
				<input type="hidden" name="username" value="">
				<input type="hidden" name="password" value="">
				<input type="hidden" name="mail_server" value="localhost">
				<input type="hidden" name="mail_server_type" value="imap/notls">
				<input type="hidden" name="mail_server_port" value="143">
				<input type="hidden" name="mail_server_fold" value="INBOX.">
				<input type="hidden" name="language" value="en">
				<input type="hidden" name="template" value="v-webmail">
				<input type="submit" class="submit" name="submit" value="'
      . only($name)
      . '" onclick="copydata(\'vweb\')">
			   </form>
                        </td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
		</tr> ';

}

sub qss_stats_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path    = $conf->{'web_qs_stat_url'};
    my $qs_ssl  = $conf->{'web_qs_stat_require_ssl'};
    my $qshost  = $conf->{'web_qs_stat_host'};
    my $name    = $conf->{'web_qs_stat_name'};
    my $descrip = $conf->{'web_qs_stat_description'};

    if ($qs_ssl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $qshost ||= $host;
    $path   ||= "/qss/index.php";

    return '
		<tr>
			<td width="20" height="3"></td>
			<td width="25">
			   <form method="post" name="qss" action="' . $http . '://' . $qshost . $path
      . '">
                              <input type="submit" value="' . only($name) . '">
		           </form>
                        </td>
			<td>
                              <strong>' . $name . '</strong> ' . $descrip . '
                       </td>
		</tr>';
}

sub isoqlog_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path    = $conf->{'web_isoqlog_url'};
    my $isossl  = $conf->{'web_isoqlog_require_ssl'};
    my $isohost = $conf->{'web_isoqlog_host'};
    my $name    = $conf->{'web_isoqlog_name'};
    my $descrip = $conf->{'web_isoqlog_description'};

    if ($isossl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $isohost ||= $host;
    $path    ||= "/isoqlog/";

    return '
		<tr>
			<td width="20" height="3"></td>
			<td width="25">
			<form name="isoqlog" action="' . $http . '://' . $isohost . $path . '">
                             <input type="submit" value="' . only($name) . '">
			</form>
                        </td>
			<td>
                           <strong>' . $name . '</strong> ' . $descrip . '
                        </td>
		</tr>';
}

sub rrdutil_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path = $conf->{'web_rrdutil_url'};
    $path ||= "/cgi-bin/rrdutil.cgi";
    my $rrdssl  = $conf->{'web_rrdutil_require_ssl'};
    my $rrdhost = $conf->{'web_rrdutil_host'};
    $rrdhost ||= $host;
    my $name    = $conf->{'web_rrdutil_name'};
    my $descrip = $conf->{'web_rrdutil_description'};

    if ($rrdssl) { $http = "https" }
    else {
        $ssl ? $http = "https" : $http = "http";
    }

    return '
	<tr>
		<td width="20" height="3"></td>
		<td width="25">
		<form method="post" name="rrdutil" action="' . $http . '://' . $rrdhost
      . $path . '">
			<input type="hidden" name="mail" value="on">
			<input type="hidden" name="days" value="1">
			<input type="hidden" name="hostname" value="localhost">
                   <input type="submit" value="' . only($name) . '"></td>
		</form>
		<td>
                    <strong>' . $name . '</strong> ' . $descrip . '
                </td>
	</tr>';
}

sub cookies_expire {

    my ( $self, $cgi, $email, $ssl, $host ) = @_;
    my @cookies;

    my $cookie1 = $cgi->cookie(
        -name    => 'email',
        -value   => $email,
        -expires => '-1d',
        -domain  => $host,
        -secure  => $ssl
    );

    my $cookie3 = $cgi->cookie(
        -name    => 'ssl',
        -value   => $ssl,
        -expires => '-1d',
        -domain  => $host,
        -secure  => $ssl
    );

    push @cookies, $cookie1;
    push @cookies, $cookie3;

    return \@cookies;
}

sub qmailadmin_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path    = $conf->{'web_qmailadmin_url'};
    my $qmassl  = $conf->{'web_qmailadmin_require_ssl'};
    my $qmahost = $conf->{'web_qmailadmin_host'};
    my $name    = $conf->{'web_qmailadmin_name'};
    my $descrip = $conf->{'web_qmailadmin_description'};

    if ($qmassl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $qmahost ||= $host;
    $path    ||= "/cgi-bin/qmailadmin";

    my $line = '
		<tr>
			<td width="20" valign="middle" align="center"></td>
			<td width="25">
			<form method="post" name="admin" action="' . $http . '://' . $qmahost . $path
      . '">
				<input type="hidden" name="username" value="">
				<input type="hidden" name="domain" value="">
				<input type="hidden" name="password" value="">
				<input type="submit" value="'
      . only($name)
      . '" onclick="copydata(\'admin\')">
			</form>
			</td>
			<td><p><strong>' . $name;
    if ( $conf->{'web_qmailadmin_help_url'} ) {
        $line .=
          ' [ <a href="' . $conf->{'web_qmailadmin_help_url'} . '">?</a> ] ';
    }
    $line .= '</strong> ' . $descrip . '</p></td>
		</tr> ';

    return $line;
}

sub sqwebmail_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my ($http);

    my $path    = $conf->{'web_sqwebmail_url'};
    my $sqwssl  = $conf->{'web_sqwebmail_require_ssl'};
    my $sqwhost = $conf->{'web_sqwebmail_host'};
    my $name    = $conf->{'web_sqwebmail_name'};
    my $descrip = $conf->{'web_sqwebmail_description'};

    if ($sqwssl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $sqwhost ||= $host;
    $path    ||= "/cgi-bin/sqwebmail";

    return '
		<tr>
			<td width="20" valign="middle" align="center"> </td>
			<td width="25">
			<form method="post" name="sqweb" action="' . $http . '://' . $sqwhost . $path
      . '">
				<input type="hidden" name="username" value="">
				<input type="hidden" name="password" value="">
				<input type="hidden" name="sameip" value="1">
				<input type="submit" value="'
      . only($name)
      . '" onclick="copydata(\'sqweb\')">
			</form>
                        </td>
			<td><p><strong>' . $name . '</strong> ' . $descrip . '</p></td>
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

}

sub squirrelmail_submit {

    my ( $self, $conf, $ssl, $host ) = @_;
    my $http;

    my $path    = $conf->{'web_squirrelmail_url'};
    my $squssl  = $conf->{'web_squirrelmail_require_ssl'};
    my $squhost = $conf->{'web_squirrelmail_host'};
    my $name    = $conf->{'web_squirrelmail_name'};
    my $descrip = $conf->{'web_squirrelmail_description'};

    if ($squssl) { $http = "https" }
    else {
        if ($ssl) { $http = "https" }
        else { $http = "http" }
    }

    $squhost ||= $host;
    $path    ||= "/squirrelmail/src/redirect.php";

    return '
		<tr>
			<td width="20" valign="middle" align="center">
				<p class="hilite16"> 3 </p></td>
			<td width="25">
			<form method="post" name="squirrel" action="' . $http . '://' . $squhost
      . $path . '">
				<input type="hidden" name="login_username" value="">
				<input type="hidden" name="secretkey" value="">
                           <input type="submit" value="'
      . only($name)
      . '" onclick="copydata(\'squirrel\')">
			</form>
                        </td>
			<td>
                              <strong>' . $name . '</strong> ' . $descrip . '
                        </td>
		</tr>
		<tr>
			<td colspan="3" height="3" width="3"></td>
		</tr>';
}

sub cookies_set {

    my ( $self, $cgi, $email, $ssl, $host ) = @_;
    my @cookies;

    my $cookie1 = $cgi->cookie(
        -name    => 'email',
        -value   => $email,
        -expires => '+1y',

        #		-path=>'/check.cgi',
        -domain => $host,
        -secure => $ssl
    );

    my $cookie3 = $cgi->cookie(
        -name    => 'ssl',
        -value   => $ssl,
        -expires => '+1y',

        #		-path=>'/check.cgi',
        -domain => $host,
        -secure => $ssl
    );

    push @cookies, $cookie1;
    push @cookies, $cookie3;

    return \@cookies;
}

sub ssl_line {

    my ( $self, $ssl, $editable ) = @_;

    if ($editable) {
        if ($ssl) {
            return
              '<input type="checkbox" name="ssl" checked onClick="submit()">';
        }
        else {
            return '<input type="checkbox" name="ssl" / onClick="submit()">';
        }
    }
    else {
        if ($ssl) {
            return '<input type="hidden" name="ssl" value="1"> selected';
        }
        else {
            return '<input type="hidden" name="ssl" value="0"> disabled';
        }
    }
}

sub cookie_line {

    my ( $self, $save ) = @_;

    if ($save) {
        return
'<input type="checkbox" name="save" onClick="submit()"> Save My Settings <input type="submit" value="Yes">';
    }
    else {
        return '<a href="index.cgi?logout=1">change my settings </a>';
    }
}

sub email_line {

    my ( $self, $address, $editable ) = @_;

    unless ($address) { $address = "email address"; }

    if ($editable) {
        return '<input name="email" type="text" id="email" size="20" value="'
          . $address
          . '" onFocus="if(this.value==\'email address\')this.value=\'\';">';
    }
    else {
        return '<input name="email" type="hidden" id="email" value="' . $address
          . '">'
          . $address;
    }
}

sub process_shell {

    print "exiting normally\n";
    exit 1;
}

1;
__END__


=head1 NAME

Mail::Toaster::CGI - a CGI application for logging into the various web components of a Mail Toaster.

=head1 SYNOPSIS

A cgi application and HTML template for a standard mail page.

This module contains the subroutines that are used by index.cgi. They're named well so you should have no problems reading through index.cgi and understanding exactly what it's doing.

=head1 DESCRIPTION

see index.cgi for a more complete description. The web pages are fully customizable as the index.tmpl is an HTML::Template file, which is almost pure HTML.

=head1 SUBROUTINES

=over 8

=item new

	use Mail::Toaster::CGI;
	my $toaster_cgi = Mail::Toaster::CGI->new();

Once you have a Mail::Toaster::CGI object, you can call any of the following methods.


=item instructions

Displays the end user instructions displayed on the web page. Uses values from toaster.conf.

    $toaster_cgi->instructions($conf);


=item logo

Displays the logo using the URL and alt data from toaster.conf.

    $toaster_cgi->logo($conf);


=item heading

Displays the HTML heading using the data from toaster.conf.

    $toaster_cgi->heading($conf);


=item imp_submit

	$toaster_cgi->imp_submit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.


=item SetVWebSubmit

	$toaster_cgi->vwebmail_submit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.


=item qss_stats_submit

    $toaster_cgi->qss_stats_submit($conf, $ssl, $host);

Generate the HTML code that renders the Qmail Scanner Statistics table and form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection, $host is the hostname to submit the form to, and $path is the path to isoqlog on the remote server. A typical invocation might look like this:

    $toaster_cgi->qss_stats_submit($conf, 1, "matt.cadillac.net" );


=item isoqlog_submit

	use Mail::Toaster::CGI;
	isoqlog_submit($conf, $ssl, $host);

Generate the HTML code that renders the Isoqlog table and form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection, $host is the hostname to submit the form to. A typical invocation might look like this:

	isoqlog_submit($conf, 1, "matt.cadillac.net");


=item rrdutil_submit

	$toaster_cgi->rrdutil_submit($conf, $ssl, $host);

Generate the HTML code that renders the table and embedded form that you see in index.cgi.

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection. $host is the hostname to submit the form to.


=item cookies_expire

Very simple use of CGI's cookie method. To expire the cookie we just set it's expiration to a negative value.


=item qmailadmin_submit

	$toaster_cgi->qmailadmin_submit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.


=item sqwebmail_submit

	$toaster_cgi->sqwebmail_submit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.



=item squirrelmail_submit

	$toaster_cgi->squirrelmail_submit($conf, $ssl, $host);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $host is the hostname to submit the form to.  $path is the installed URL path on the server.


=item cookies_set

Very simple use of CGI's cookie method. We save a cookie with the users email address and another one for for whether they selected Use SSL.



=item ssl_line

	$toaster_cgi->ssl_line($ssl, $editable);

$ssl is a binary value, representing whether the form URL should be http or https, based on the users selection.  $editable is a binary value, determining if the SSL preference is available or not.  


=item cookie_line

	$toaster_cgi->cookie_line($save);

$save is a binary value, are the users settings saved or not?


=item email_line

	$toaster_cgi->email_line($address, $editable);

$address is the email address to display in the form.

$editable is whether or not the address field is editable.



=item process_shell

Since we're a CGI app, we don't expect to be run from the command line except to test. This little sub just lets you know everything that was supposed to load did and that the CGI should work right.


=back

=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>

=head1 BUGS

None known. Report any to author.

=head1 TODO

TODO is caught up. Yay!

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004-2006, The Network People, Inc.  All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
