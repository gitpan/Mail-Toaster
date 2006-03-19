use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#
# $Id: Makefile.PL,v 4.13 2006/03/17 00:29:48 matt Exp $
#

$|++;

my $htdocs = SetHtdocs();
my $confdir = SetConfDir();

sub MY::postamble { 

'HTMLDIR	=	' . $htdocs . '
CONFDIR    =   ' . $confdir . '
TNPITOASTER	=	/Volumes/Shared/Sites/www.tnpi.biz/internet/mail/toaster
TNPIMAILLOG =   /Volumes/Shared/Sites/www.tnpi.biz/internet/mail/maillogs
MAILLOG		=	/var/log/mail
MODULES		=	doc/modules
MT		=	Mail::Toaster

docs:
	pod2text toaster_setup.pl      > README

	pod2text lib/toaster.conf.pod           > doc/toaster.conf
	pod2text lib/toaster-watcher.conf.pod   > doc/toaster-watcher.conf

	pod2html --title="$(MT) toaster.conf" lib/toaster.conf.pod           > doc/toaster.conf.html
	pod2html --title="$(MT) watcher.conf" lib/toaster-watcher.conf.pod   > doc/toaster-watcher.conf.html

	pod2html --title="$(MT)"          lib/Mail/Toaster.pm          > $(MODULES)/Toaster.html
	pod2html --title="$(MT)::Apache"  lib/Mail/Toaster/Apache.pm   > $(MODULES)/Apache.html
	pod2html --title="$(MT)::CGI"     lib/Mail/Toaster/CGI.pm      > $(MODULES)/CGI.html
	pod2html --title="$(MT)::Darwin"  lib/Mail/Toaster/Darwin.pm   > $(MODULES)/Darwin.html
	pod2html --title="$(MT)::DNS"     lib/Mail/Toaster/DNS.pm      > $(MODULES)/DNS.html
	pod2html --title="$(MT)::Ezmlm"   lib/Mail/Toaster/Ezmlm.pm    > $(MODULES)/Ezmlm.html
	pod2html --title="$(MT)::FreeBSD" lib/Mail/Toaster/FreeBSD.pm  > $(MODULES)/FreeBSD.html
	pod2html --title="$(MT)::Logs"    lib/Mail/Toaster/Logs.pm     > $(MODULES)/Logs.html
	pod2html --title="$(MT)::Mysql"   lib/Mail/Toaster/Mysql.pm    > $(MODULES)/Mysql.html
	pod2html --title="$(MT)::Passwd"  lib/Mail/Toaster/Passwd.pm   > $(MODULES)/Passwd.html
	pod2html --title="$(MT)::Perl"    lib/Mail/Toaster/Perl.pm     > $(MODULES)/Perl.html
	pod2html --title="$(MT)::Provision" lib/Mail/Toaster/Provision.pm > $(MODULES)/Provision.html
	pod2html --title="$(MT)::Qmail"   lib/Mail/Toaster/Qmail.pm    > $(MODULES)/Qmail.html
	pod2html --title="$(MT)::Setup"   lib/Mail/Toaster/Setup.pm    > $(MODULES)/Setup.html
	pod2html --title="$(MT)::Utility" lib/Mail/Toaster/Utility.pm  > $(MODULES)/Utility.html

	pod2html --title="$(MT) mailadmin"      mailadmin                     > doc/mailadmin.html
	rm pod2htm*
	
conf:
	install -d /usr/local
	install -d /opt
	install -d /opt/local
	install -d $(CONFDIR)
	install -m 0644 toaster.conf-dist $(CONFDIR)
	install -m 0640 toaster-watcher.conf-dist $(CONFDIR)
	install -d $(CONFDIR)/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch $(CONFDIR)/apache2
	install -b -m 0640 contrib/pkgtools.conf $(CONFDIR)/pkgtools.conf-dist

newconf:
	install -d $(CONFDIR)
	install -d $(CONFDIR)/apache2
	install -m 0644 toaster.conf-dist $(CONFDIR)
	install -m 0640 toaster-watcher.conf-dist $(CONFDIR)
	install -b -m 0644 toaster.conf-dist $(CONFDIR)/toaster.conf
	install -b -m 0640 toaster-watcher.conf-dist $(CONFDIR)/toaster-watcher.conf
	install -b -m 0640 contrib/httpd.conf-2.0.patch $(CONFDIR)/apache2
	install -b -m 0640 contrib/pkgtools.conf $(CONFDIR)/pkgtools.conf

cgi:
	install -d $(HTMLDIR)
	install -d $(HTMLDIR)/toaster_templates
	install -b cgi_files/index.cgi  $(HTMLDIR)/index.cgi
	install -b cgi_files/admin.cgi  $(HTMLDIR)/admin.cgi
	install -b -m 0644 cgi_files/index.tmpl $(HTMLDIR)/index.tmpl
	install -b -m 0644 cgi_files/admin.tmpl $(HTMLDIR)/admin.tmpl
	install -b -m 0644 cgi_files/user_body.tmpl   $(HTMLDIR)/toaster_templates/user_body.tmpl
	install -b -m 0644 cgi_files/user_header.tmpl $(HTMLDIR)/toaster_templates/user_header.tmpl
	install -b -m 0644 cgi_files/user_footer.tmpl $(HTMLDIR)/toaster_templates/user_footer.tmpl
	install -b -m 0644 cgi_files/user_styles.tmpl $(HTMLDIR)/toaster_templates/user_styles.tmpl
	install -b -m 0644 cgi_files/toaster_javascript.tmpl $(HTMLDIR)/toaster_templates/toaster_javascript.tmpl
	install -b -m 0644 cgi_files/toaster_login.tmpl      $(HTMLDIR)/toaster_templates/toaster_login.tmpl
	install -b -m 0644 cgi_files/toaster_stats.tmpl      $(HTMLDIR)/toaster_templates/toaster_stats.tmpl
	install -b -m 0644 cgi_files/toaster_viewers.tmpl    $(HTMLDIR)/toaster_templates/toaster_viewers.tmpl

	install -d $(CONFDIR)/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch $(CONFDIR)/apache2
	install -d $(HTMLDIR)/support
	install -d $(HTMLDIR)/support/mac
	install -d $(HTMLDIR)/support/unix
	install -d $(HTMLDIR)/support/win
	install -b support/filtering.html  $(HTMLDIR)/support/filtering.html  
	install -b support/ssl.html        $(HTMLDIR)/support/ssl.html
	install -b support/webmail.html    $(HTMLDIR)/support/webmail.html
	install -b support/antivirus.html  $(HTMLDIR)/support/antivirus.html
	install -b support/imap.html       $(HTMLDIR)/support/imap.html
	install -b support/pop3.html       $(HTMLDIR)/support/pop3.html
	install -d $(HTMLDIR)/images
	install -b support/tnpi_logo.jpg   $(HTMLDIR)/images/
	install -b -m 4755 -o 89 contrib/ezmlm.cgi $(HTMLDIR)/ezmlm.cgi
	install -b -m 0644 contrib/ezmlm.tmpl $(HTMLDIR)/ezmlm.tmpl

ezcgi:
	install -d $(HTMLDIR)
	install -b -m 4755 -o 89 contrib/ezmlm.cgi $(HTMLDIR)/ezmlm.cgi
	install -b -m 0644 contrib/ezmlm.tmpl $(HTMLDIR)/ezmlm.tmpl

cgi-mail:
	echo "deprecated! Use [make cgi] instead!"
	install -d $(HTMLDIR)
	install -d $(HTMLDIR)/toaster_templates
	install -b -m 0755 cgi_files/index.cgi  $(HTMLDIR)/index.cgi
	install -b -m 0644 cgi_files/index.tmpl $(HTMLDIR)/index.tmpl
	install -b -m 0644 cgi_files/user_body.tmpl   $(HTMLDIR)/toaster_templates/user_body.tmpl
	install -b -m 0644 cgi_files/user_header.tmpl $(HTMLDIR)/toaster_templates/user_header.tmpl
	install -b -m 0644 cgi_files/user_footer.tmpl $(HTMLDIR)/toaster_templates/user_footer.tmpl
	install -b -m 0644 cgi_files/user_styles.tmpl $(HTMLDIR)/toaster_templates/user_styles.tmpl
	install -b -m 0644 cgi_files/toaster_javascript.tmpl $(HTMLDIR)/toaster_templates/toaster_javascript.tmpl
	install -b -m 0644 cgi_files/toaster_login.tmpl      $(HTMLDIR)/toaster_templates/toaster_login.tmpl
	install -b -m 0644 cgi_files/toaster_stats.tmpl      $(HTMLDIR)/toaster_templates/toaster_stats.tmpl
	install -b -m 0644 cgi_files/toaster_viewers.tmpl    $(HTMLDIR)/toaster_templates/toaster_viewers.tmpl
	install -b -m 4755 -o 89 contrib/ezmlm.cgi $(HTMLDIR)/ezmlm.cgi
	install -b -m 0644 contrib/ezmlm.tmpl $(HTMLDIR)/ezmlm.tmpl
	install -d $(CONFDIR)/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch $(CONFDIR)/apache2
	install -d $(HTMLDIR)/support
	install -d $(HTMLDIR)/support/mac
	install -d $(HTMLDIR)/support/unix
	install -d $(HTMLDIR)/support/win
	install -b support/filtering.html  $(HTMLDIR)/support/filtering.html  
	install -b support/ssl.html        $(HTMLDIR)/support/ssl.html
	install -b support/webmail.html    $(HTMLDIR)/support/webmail.html
	install -b support/antivirus.html  $(HTMLDIR)/support/antivirus.html
	install -b support/imap.html       $(HTMLDIR)/support/imap.html
	install -b support/pop3.html       $(HTMLDIR)/support/pop3.html
	install -d $(HTMLDIR)/images
	install -b support/tnpi_logo.jpg   $(HTMLDIR)/images/

logs:
	install -b -m 0755 maillogs $(MAILLOG)/send/sendlog
	install -b -m 0755 maillogs $(MAILLOG)/smtp/smtplog
	install -b -m 0755 maillogs $(MAILLOG)/pop3/pop3log

web:
	install toaster_setup.pl           $(TNPITOASTER)/
	install cgi_files/index.cgi              $(TNPITOASTER)/index.cgi.txt
	install mailadmin                  $(TNPITOASTER)/maildomain/mailadmin
	install toaster-watcher.pl         $(TNPITOASTER)/watcher/
	install toaster-watcher.conf-dist  $(TNPITOASTER)/watcher/toaster-watcher.conf
	install toaster-watcher.conf-dist  $(TNPITOASTER)/etc/toaster-watcher.conf

	install -m 0644 doc/toaster.conf.html         $(TNPITOASTER)/config/
	install -m 0644 doc/toaster-watcher.conf.html $(TNPITOASTER)/config/

	install -m 0644 $(MODULES)/Toaster.html   $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Apache.html    $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/CGI.html       $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/DNS.html       $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Darwin.html    $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Ezmlm.html     $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/FreeBSD.html   $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Logs.html      $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Mysql.html     $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Passwd.html    $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Perl.html      $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Provision.html $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Qmail.html     $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Setup.html     $(TNPITOASTER)/modules/
	install -m 0644 $(MODULES)/Utility.html   $(TNPITOASTER)/modules/

	install -m 0644 Mail-Toaster-$(VERSION).tar.gz $(TNPITOASTER)/Mail-Toaster.tar.gz
	mv Mail-Toaster-$(VERSION).tar.gz              $(TNPITOASTER)/src/
';

}

WriteMakefile(
	'NAME'           => 'Mail::Toaster',
	'VERSION_FROM'   => 'lib/Mail/Toaster.pm', # finds $VERSION
	'EXE_FILES'      => [ 'cgi_files/index.cgi', 'toaster_setup.pl', 'toaster-watcher.pl',
					 'mailadmin', 'maillogs', 'qqtool.pl' ],
#	'MAN1PODS'       => [],
	'INSTALLSCRIPT'  => '/usr/local/sbin',
	'PREREQ_PM'      => { 
			'Net::DNS'    => 0.20, 
			'DBI'         => 1, 
			'Date::Parse' => 1, 
			'Quota'       => 0,
			'vpopmail'    => 0, 
			'Email::Valid'=> 0, 
			'Mail::Ezmlm' => 0 
		},
	'AUTHOR'         => 'Matt Simerson <matt@tnpi.biz>',
	'ABSTRACT'       => 'Mail::Toaster perl programs and modules',

#	($] >= 5.005 ?     ## Add these new keywords supported since 5.005
#	  ( ABSTRACT_FROM  => 'maillogs',   # retrieve abstract from module
);

sub SetConfDir
{
	my $dir = "/usr/local/etc";
	if    ( $^O eq "darwin"  ) { $dir = "/opt/local/etc"      };  # Mac OS X
	return $dir;
}

sub SetHtdocs
{
	my $dir = "/usr/local/www/data";
	if    ( -d "/usr/local/www/data/mail"     ) { $dir = "/usr/local/www/data/mail"     }  # FreeBSD
	elsif ( -d "/usr/local/www/mail"          ) { $dir = "/usr/local/www/mail"          }
	elsif ( -d "/Library/Webserver/Documents" ) { $dir = "/Library/Webserver/Documents" }  # Mac OS X
	elsif ( -d "/var/www/html"                ) { $dir = "/var/www/html"                }; # Linux
	return $dir;
};


# Copyright (c) 2004-2005, The Network People, Inc.
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# 
# Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
# 
# Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

