use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#
# $Id: Makefile.PL,v 4.0 2004/11/16 20:57:30 matt Exp $
#

$|++;

my $htdocs = SetHtdocs();

sub MY::postamble { 

'HTMLDIR	=	' . $htdocs . '
TNPITOASTER	=	/Users/matt/Sites/www.tnpi.biz/internet/mail/toaster
TNPIMAILLOG =   /Users/matt/Sites/www.tnpi.biz/internet/mail/maillogs
MAILLOG		=	/var/log/mail
MODULES		=	doc/html/modules
MT		=	Mail::Toaster

docs:
	pod2text toaster_setup.pl      > README
	pod2text toaster_setup.pl      > doc/README
	pod2text doc/pod/FAQ.pod       > doc/FAQ
	pod2text doc/pod/LIFE.pod       > doc/LifeWithMailToaster
	pod2text doc/pod/Changes.pod   > doc/Changes
	pod2text doc/pod/INSTALL.pod   > doc/INSTALL
	pod2text doc/pod/INSTALL-Darwin.pod   > doc/INSTALL-Darwin
	pod2text doc/pod/UPGRADE.pod   > doc/UPGRADE
	pod2text doc/pod/Patches.pod   > doc/Patches
	pod2text doc/pod/QUOTES.pod    > doc/QUOTES

	pod2text maillogs                     > doc/README-MailLogs
	pod2text doc/pod/FAQ-MailLogs.pod     > doc/FAQ-MailLogs
	pod2text doc/pod/Changes-MailLogs.pod > doc/Changes-MailLogs

	pod2text qqtool.pl                    > doc/README-qqtool
	pod2text doc/pod/Changes-qqtool.pod   > doc/Changes-qqtool

	pod2text index.cgi                > doc/README-CGI
	pod2text doc/pod/FAQ-CGI.pod      > doc/FAQ-CGI
	pod2text doc/pod/Changes-CGI.pod  > doc/Changes-CGI
	pod2text doc/pod/INSTALL-CGI.pod  > doc/INSTALL-CGI

	pod2text toaster-watcher.pl             > doc/README-Watcher
	pod2text doc/pod/FAQ-Watcher.pod        > doc/FAQ-Watcher
	pod2text doc/pod/Changes-Watcher.pod    > doc/Changes-Watcher
	pod2text doc/pod/Credits-Watcher.pod    > doc/Credits-Watcher
	pod2text doc/pod/INSTALL-Watcher.pod    > doc/INSTALL-Watcher

	pod2text lib/toaster.conf.pod           > doc/toaster.conf
	pod2text lib/toaster-watcher.conf.pod   > doc/toaster-watcher.conf

	pod2text mailadmin                    > doc/README-mailadmin
	pod2text doc/pod/Changes-Admin.pod    > doc/Changes-mailadmin

	pod2html --title="$(MT)::Setup README"  toaster_setup.pl     > doc/html/README.html
	pod2html --title="$(MT) FAQ"            doc/pod/FAQ.pod      > doc/html/FAQ.html
	pod2html --title="$(MT) Life With Mail::Toaster" doc/pod/LIFE.pod > doc/html/LIFE.html
	pod2html --title="$(MT) Changes"        doc/pod/Changes.pod  > doc/html/Changes.html
	pod2html --title="$(MT) Install"        doc/pod/INSTALL.pod  > doc/html/INSTALL.html
	pod2html --title="$(MT) Install Darwin" doc/pod/INSTALL-Darwin.pod  > doc/html/INSTALL-Darwin.html
	pod2html --title="$(MT) UPGRADE"        doc/pod/UPGRADE.pod  > doc/html/UPGRADE.html
	pod2html --title="$(MT) Patches"        doc/pod/Patches.pod  > doc/html/Patches.html
	pod2html --title="$(MT) Quotes"         doc/pod/QUOTES.pod   > doc/html/QUOTES.html
	pod2html --title="$(MT) BUILD"          doc/pod/BUILD.pod    > doc/html/BUILD.html

	pod2html --title="$(MT)::Logs README"  maillogs                     > doc/html/README-MailLogs.html
	pod2html --title="$(MT)::Logs FAQ"     doc/pod/FAQ-MailLogs.pod     > doc/html/FAQ-MailLogs.html
	pod2html --title="$(MT)::Logs Changes" doc/pod/Changes-MailLogs.pod > doc/html/Changes-MailLogs.html

	pod2html --title="Qmail Queue (qqtool)"        qqtool.pl                    > doc/html/qqtool.html
	pod2html --title="Qmail Queue(qqtool) Changes" doc/pod/Changes-qqtool.pod   > doc/html/Changes-qqtool.html

	pod2html --title="$(MT)::CGI README"  index.cgi                     > doc/html/README-CGI.html
	pod2html --title="$(MT)::CGI FAQ"     doc/pod/FAQ-CGI.pod           > doc/html/FAQ-CGI.html
	pod2html --title="$(MT)::CGI Install" doc/pod/INSTALL-CGI.pod       > doc/html/INSTALL-CGI.html
	pod2html --title="$(MT)::CGI Changes" doc/pod/Changes-CGI.pod       > doc/html/Changes-CGI.html

	pod2html --title="$(MT)::Watcher README"  toaster-watcher.pl           > doc/html/README-Watcher.html
	pod2html --title="$(MT)::Watcher FAQ"     doc/pod/FAQ-Watcher.pod      > doc/html/FAQ-Watcher.html
	pod2html --title="$(MT)::Watcher Changes" doc/pod/Changes-Watcher.pod  > doc/html/Changes-Watcher.html
	pod2html --title="$(MT)::Watcher Credits" doc/pod/Credits-Watcher.pod  > doc/html/Credits-Watcher.html
	pod2html --title="$(MT)::Watcher INSTALL" doc/pod/INSTALL-Watcher.pod  > doc/html/INSTALL-Watcher.html

	pod2html --title="toaster.conf docs"              lib/toaster.conf.pod         > doc/html/toaster.conf.html
	pod2html --title="toaster-watcher.conf docs"      lib/toaster-watcher.conf.pod > doc/html/toaster-watcher.conf

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

	pod2html --title="mailadmin"      mailadmin                     > doc/html/README-Admin.html
	pod2html --title="mailadmin Changes" doc/pod/Changes-Admin.pod  > doc/html/Changes-Admin.html

	rm pod2htm*

conf:
	install -d /usr/local
	install -d /usr/local/etc
	install -m 0644 toaster.conf-dist /usr/local/etc
	install -m 0640 toaster-watcher.conf-dist /usr/local/etc
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2

newconf:
	install -d /usr/local/etc
	install -d /usr/local/etc/apache2
	install -m 0644 toaster.conf-dist /usr/local/etc
	install -m 0640 toaster-watcher.conf-dist /usr/local/etc
	install -b -m 0644 toaster.conf-dist /usr/local/etc/toaster.conf
	install -b -m 0640 toaster-watcher.conf-dist /usr/local/etc/toaster-watcher.conf
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2
	install -b -m 0640 contrib/pkgtools.conf /usr/local/etc/pkgtools.conf

cgi:
	install -d $(HTMLDIR)
	install -b index.cgi  $(HTMLDIR)/index.cgi
	install -b admin.cgi  $(HTMLDIR)/admin.cgi
	install -b -m 0644 index.tmpl $(HTMLDIR)/index.tmpl
	install -b -m 0644 admin.tmpl $(HTMLDIR)/admin.tmpl
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2
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
	install -b -m 0755 index.cgi  $(HTMLDIR)/index.cgi
	install -b -m 0644 index.tmpl $(HTMLDIR)/index.tmpl
	install -b -m 4755 -o 89 contrib/ezmlm.cgi $(HTMLDIR)/ezmlm.cgi
	install -b -m 0644 contrib/ezmlm.tmpl $(HTMLDIR)/ezmlm.tmpl
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2
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
	install -m 0644 doc/html/README.html   $(TNPITOASTER)/README.html
	install -m 0644 doc/html/FAQ.html      $(TNPITOASTER)/FAQ.html
	install -m 0644 doc/html/LIFE.html     $(TNPITOASTER)/docs/LIFE.html
	install -m 0644 doc/html/Changes.html  $(TNPITOASTER)/Changes.html
	install -m 0644 doc/html/INSTALL.html  $(TNPITOASTER)/INSTALL.html
	install -m 0644 doc/html/INSTALL-Darwin.html  $(TNPITOASTER)/docs/INSTALL-Darwin.html
	install -m 0644 doc/html/UPGRADE.html  $(TNPITOASTER)/UPGRADE.html
	install -m 0644 doc/html/Patches.html  $(TNPITOASTER)/patches/PATCHES.html
	install -m 0644 doc/html/QUOTES.html   $(TNPITOASTER)/QUOTES.html
	install -m 0644 doc/html/BUILD.html    $(TNPITOASTER)/docs/BUILD.html

	install -m 0644 doc/html/README-MailLogs.html  $(TNPIMAILLOG)/README.html
	install -m 0644 doc/html/FAQ-MailLogs.html     $(TNPIMAILLOG)/FAQ.html
	install -m 0644 doc/html/Changes-MailLogs.html $(TNPIMAILLOG)/Changes.html

	install -m 0644 doc/html/qqtool.html          $(TNPITOASTER)/docs/QQTOOL-FAQ.html
	install -m 0644 doc/html/Changes-qqtool.html  $(TNPITOASTER)/docs/QQTOOL-Changes.html

	install -m 0644 doc/html/FAQ-CGI.html         $(TNPITOASTER)/docs/CGI-FAQ.html
	install -m 0644 doc/html/Changes-CGI.html     $(TNPITOASTER)/docs/CGI-Changes.html
	install -m 0644 doc/html/README-CGI.html      $(TNPITOASTER)/docs/CGI-README.html
	install -m 0644 doc/html/INSTALL-CGI.html     $(TNPITOASTER)/docs/CGI-INSTALL.html

	install -m 0644 doc/html/FAQ-Watcher.html     $(TNPITOASTER)/watcher/FAQ.html
	install -m 0644 doc/html/Changes-Watcher.html $(TNPITOASTER)/watcher/Changes.html
	install -m 0644 doc/html/README-Watcher.html  $(TNPITOASTER)/watcher/README.html
	install -m 0644 doc/html/Credits-Watcher.html $(TNPITOASTER)/watcher/Credits.html
	install -m 0644 doc/html/INSTALL-Watcher.html $(TNPITOASTER)/watcher/INSTALL.html

	install -m 0644 doc/html/toaster.conf.html    $(TNPITOASTER)/docs/TCONF.html
	install -m 0644 doc/html/toaster-watcher.conf $(TNPITOASTER)/docs/WATCHER.html

	install -m 0644 doc/html/Changes-Admin.html   $(TNPITOASTER)/maildomain/Changes.html
	install -m 0644 doc/html/README-Admin.html    $(TNPITOASTER)/maildomain/README.html

	install -m 0644 $(MODULES)/Toaster.html    $(TNPITOASTER)/modules/
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

	install toaster_setup.pl           $(TNPITOASTER)/
	install index.cgi                  $(TNPITOASTER)/index.cgi.txt
	install mailadmin                  $(TNPITOASTER)/maildomain/mailadmin
	install toaster-watcher.pl         $(TNPITOASTER)/watcher/
	install toaster-watcher.conf-dist  $(TNPITOASTER)/watcher/toaster-watcher.conf
	install toaster-watcher.conf-dist  $(TNPITOASTER)/etc/toaster-watcher.conf

	install -m 0644 Mail-Toaster-$(VERSION).tar.gz $(TNPITOASTER)/Mail-Toaster.tar.gz
	mv Mail-Toaster-$(VERSION).tar.gz              $(TNPITOASTER)/src/
';

}

WriteMakefile(
	'NAME'           => 'Mail::Toaster',
	'VERSION_FROM'   => 'lib/Mail/Toaster.pm', # finds $VERSION
	'EXE_FILES'      => [ 'index.cgi', 'toaster_setup.pl', 'toaster-watcher.pl',
					 'mailadmin', 'maillogs', 'qqtool.pl' ],
#	'MAN1PODS'       => [],
	'INSTALLSCRIPT'  => '/usr/local/sbin',
	'PREREQ_PM'      => { 'Net::DNS' => 0.20, DBI => 1, 'Date::Parse' => 1 },
	'AUTHOR'         => 'Matt Simerson <matt@tnpi.biz>',
	'ABSTRACT'       => 'Mail::Toaster perl programs and modules',

#	($] >= 5.005 ?     ## Add these new keywords supported since 5.005
#	  ( ABSTRACT_FROM  => 'maillogs',   # retrieve abstract from module
);

sub SetHtdocs
{
	my $dir = "/usr/local/www/data";
	if    ( -d "/usr/local/www/data/mail" ) { $dir = "/usr/local/www/data/mail" }
	elsif ( -d "/usr/local/www/mail"      ) { $dir = "/usr/local/www/mail"      }
	elsif ( -d "/Library/Webserver/Documents" ) { $dir = "/Library/Webserver/Documents" };
	return $dir;
};


# Copyright (c) 2004, The Network People, Inc.
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

