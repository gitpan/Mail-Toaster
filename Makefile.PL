use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#
# $Id: Makefile.PL,v 1.20 2004/02/12 23:56:17 matt Exp $
#

$|++;

sub MY::postamble { 
q|

docs:
	pod2text toaster_setup.pl      > doc/README
	pod2text doc/pod/FAQ.pod       > doc/FAQ
	pod2text doc/pod/Changes.pod   > doc/Changes
	pod2text doc/pod/INSTALL.pod   > doc/INSTALL
	pod2text doc/pod/UPGRADE.pod   > doc/UPGRADE
	pod2text doc/pod/Patches.pod   > doc/Patches

	pod2text maillogs                     > doc/html/README-MailLogs.html
	pod2text doc/pod/FAQ-MailLogs.pod     > doc/FAQ-MailLogs
	pod2text doc/pod/Changes-MailLogs.pod > doc/Changes-MailLogs

	pod2text index.cgi                > doc/README-CGI
	pod2text doc/pod/FAQ-CGI.pod      > doc/FAQ-CGI
	pod2text doc/pod/Changes-CGI.pod  > doc/Changes-CGI
	pod2text doc/pod/INSTALL-CGI.pod  > doc/INSTALL-CGI

	pod2text toaster-watcher.pl             > doc/README-Watcher
	pod2text doc/pod/FAQ-Watcher.pod        > doc/FAQ-Watcher
	pod2text doc/pod/Changes-Watcher.pod    > doc/Changes-Watcher
	pod2text doc/pod/Credits-Watcher.pod    > doc/Credits-Watcher
	pod2text doc/pod/INSTALL-Watcher.pod    > doc/INSTALL-Watcher

	pod2html --title="Mail::Toaster::Setup README" toaster_setup.pl     > doc/html/README.html
	pod2html --title="Mail::Toaster FAQ"           doc/pod/FAQ.pod      > doc/html/FAQ.html
	pod2html --title="Mail::Toaster Changes"       doc/pod/Changes.pod  > doc/html/Changes.html
	pod2html --title="Mail::Toaster Install"       doc/pod/INSTALL.pod  > doc/html/INSTALL.html
	pod2html --title="Mail::Toaster UPGRADE"       doc/pod/UPGRADE.pod  > doc/html/UPGRADE.html
	pod2html --title="Qmail Toaster Patches"       doc/pod/Patches.pod  > doc/html/Patches.html

	pod2html --title="Mail::Toaster::Logs README"  maillogs                     > doc/html/README-MailLogs.html
	pod2html --title="Mail::Toaster::Logs FAQ"     doc/pod/FAQ-MailLogs.pod     > doc/html/FAQ-MailLogs.html
	pod2html --title="Mail::Toaster::Logs Changes" doc/pod/Changes-MailLogs.pod > doc/html/Changes-MailLogs.html

	pod2html --title="Mail::Toaster::CGI FAQ"     doc/pod/FAQ-CGI.pod        > doc/html/FAQ-CGI.html
	pod2html --title="Mail::Toaster::CGI Install" doc/pod/INSTALL-CGI.pod    > doc/html/INSTALL-CGI.html

	pod2html --title="Mail::Toaster::Watcher README"  toaster-watcher.pl           > doc/html/README-Watcher.html
	pod2html --title="Mail::Toaster::Watcher FAQ"     doc/pod/FAQ-Watcher.pod      > doc/html/FAQ-Watcher.html
	pod2html --title="Mail::Toaster::Watcher Changes" doc/pod/Changes-Watcher.pod  > doc/html/Changes-Watcher.html
	pod2html --title="Mail::Toaster::Watcher Credits" doc/pod/Credits-Watcher.pod  > doc/html/Credits-Watcher.html
	pod2html --title="Mail::Toaster::Watcher INSTALL" doc/pod/INSTALL-Watcher.pod  > doc/html/INSTALL-Watcher.html

	pod2html --title="Mail::Toaster::CGI"   lib/Mail/Toaster/CGI.pm   > doc/html/modules/CGI.html
	pod2html --title="Mail::Toaster::DNS"   lib/Mail/Toaster/DNS.pm   > doc/html/modules/DNS.html
	pod2html --title="Mail::Toaster::Logs"  lib/Mail/Toaster/Logs.pm  > doc/html/modules/Logs.html
	pod2html --title="Mail::Toaster::Qmail" lib/Mail/Toaster/Qmail.pm > doc/html/modules/Qmail.html
	pod2html --title="Mail::Toaster::Setup" lib/Mail/Toaster/Setup.pm > doc/html/modules/Setup.html

	rm pod2htm*

conf:
	install -d /usr/local/etc
	install toaster.conf-dist /usr/local/etc
	install toaster-watcher.conf-dist /usr/local/etc
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2

newconf:
	install toaster.conf-dist /usr/local/etc
	install toaster-watcher.conf-dist /usr/local/etc
	install -d /usr/local/etc
	install -b -m 0644 toaster.conf-dist /usr/local/etc/toaster.conf
	install -b -m 0640 toaster-watcher.conf-dist /usr/local/etc/toaster-watcher.conf
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2

cgi:
	install -d /usr/local/www/data
	install -b index.cgi  /usr/local/www/data/index.cgi
	install -b -m 0644 index.tmpl /usr/local/www/data/index.tmpl
	install -d /usr/local/etc/apache2
	install -b -m 0640 contrib/httpd.conf-2.0.patch /usr/local/etc/apache2
	install -d /usr/local/www/data/support
	install -d /usr/local/www/data/support/mac
	install -d /usr/local/www/data/support/unix
	install -d /usr/local/www/data/support/win
	install -b support/filtering.html  /usr/local/www/data/support/filtering.html  
	install -b support/ssl.html        /usr/local/www/data/support/ssl.html
	install -b support/webmail.html    /usr/local/www/data/support/webmail.html
	install -b support/antivirus.html  /usr/local/www/data/support/antivirus.html
	install -b support/imap.html       /usr/local/www/data/support/imap.html
	install -b support/pop3.html       /usr/local/www/data/support/pop3.html

cgi-mail:
	install -d /usr/local/www/data/mail
	install -b index.cgi  /usr/local/www/data/mail/index.cgi
	install -b -m 0644 index.tmpl /usr/local/www/data/mail/index.tmpl
	install -d /usr/local/www/data/mail/support
	install -d /usr/local/www/data/mail/support/mac
	install -d /usr/local/www/data/mail/support/unix
	install -d /usr/local/www/data/mail/support/win
	install -b support/filtering.html  /usr/local/www/data/mail/support/filtering.html  
	install -b support/ssl.html        /usr/local/www/data/mail/support/ssl.html
	install -b support/webmail.html    /usr/local/www/data/mail/support/webmail.html
	install -b support/antivirus.html  /usr/local/www/data/mail/support/antivirus.html
	install -b support/imap.html       /usr/local/www/data/mail/support/imap.html
	install -b support/pop3.html       /usr/local/www/data/mail/support/pop3.html

logs:
	install -b -m 0755 maillogs /var/log/mail/send/sendlog
	install -b -m 0755 maillogs /var/log/mail/smtp/smtplog
	install -b -m 0755 maillogs /var/log/mail/pop3/pop3log

web:
	install -m 0644 doc/html/FAQ.html     /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/FAQ.html
	install -m 0644 doc/html/Changes.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/Changes.html
	install -m 0644 doc/html/README.html  /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/README.html
	install -m 0644 doc/html/INSTALL.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/INSTALL.html
	install -m 0644 doc/html/UPGRADE.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/UPGRADE.html
	install -m 0644 doc/html/Patches.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/patches/PATCHES.html

	install -m 0644 doc/html/FAQ-CGI.html     /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/CGI-FAQ.html
	install -m 0644 doc/html/Changes-CGI.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/CGI-Changes.html
	install -m 0644 doc/html/README-CGI.html  /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/CGI-README.html
	install -m 0644 doc/html/INSTALL-CGI.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/CGI-INSTALL.html

	install -m 0644 doc/html/FAQ-Watcher.html     /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/FAQ.html
	install -m 0644 doc/html/Changes-Watcher.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/Changes.html
	install -m 0644 doc/html/README-Watcher.html  /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/README.html
	install -m 0644 doc/html/Credits-Watcher.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/Credits.html
	install -m 0644 doc/html/INSTALL-Watcher.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/INSTALL.html

	install -m 0644 doc/html/modules/CGI.html   /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/modules/
	install -m 0644 doc/html/modules/DNS.html   /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/modules/
	install -m 0644 doc/html/modules/Logs.html  /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/modules/
	install -m 0644 doc/html/modules/Qmail.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/modules/
	install -m 0644 doc/html/modules/Setup.html /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/modules/

	install toaster_setup.pl         /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/
	install index.cgi                /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/index.cgi.txt
	install toaster-watcher.pl       /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/
	install toaster-watcher.conf-dist /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/watcher/toaster-watcher.conf

	install -m 0644 Mail-Toaster-$(VERSION).tar.gz /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/Mail-Toaster.tar.gz
	mv Mail-Toaster-$(VERSION).tar.gz /Users/matt/Sites/www.tnpi.biz/internet/mail/toaster/src/

|;

}

WriteMakefile(
	'NAME'           => 'Mail::Toaster',
	'VERSION_FROM'   => 'lib/Mail/Toaster.pm', # finds $VERSION
	'EXE_FILES'      => [ 'index.cgi', 'toaster_setup.pl', 'toaster-watcher.pl',
					 'mailadmin', 'maillogs' ],
	'INSTALLSCRIPT'  => '/usr/local/sbin',
	'PREREQ_PM'      => {'MATT::Utility' => 1.20, 'MATT::Perl' => 1, 'MATT::FreeBSD' => 1, 
                         'Net::DNS' => 0.20, DBI => 1, 'Date::Parse' => 1 },
	'AUTHOR'         => 'Matt Simerson <matt@tnpi.biz>',
	'ABSTRACT'       => 'Mail Toaster perl programs',

#	($] >= 5.005 ?     ## Add these new keywords supported since 5.005
#	  ( ABSTRACT_FROM  => 'maillogs',   # retrieve abstract from module
);


