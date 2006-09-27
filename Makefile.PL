#/usr/bin/perl
use 5.008;
use English qw( -no_match_vars );

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
use ExtUtils::MakeMaker;

#
# $Id: Makefile.PL,v 5.00 2006/06/09 19:26:17 matt Exp $
#

$AUTOFLUSH++;

use lib "lib";

BEGIN {
    if ( ! eval "require Params::Validate" ) {
        print "\n\tParams::Validate is not installed!\n\n";
        print "Install it as follows:\n";

        if ( $OSNAME eq "freebsd" ) {
            print "
   cd /usr/ports/devel/p5-Params-Validate
   make install clean\n";
        }
        else {
            print "
   perl -MCPAN -e shell
   > install Params::Validate
   > quit\n";
        };

        print "then return this this directory and continue installing
Mail::Toaster as follows:

   cd -
   perl Makefile.PL\n\n";
        exit 0;
    }
}

use Mail::Toaster          5; my $toaster = Mail::Toaster->new;
use Mail::Toaster::Utility 5; my $utility = Mail::Toaster::Utility->new;

my $conf    = $utility->parse_config( file => "toaster-watcher.conf", debug => 0 );
my $logdir  = $toaster->get_toaster_logs(conf=>$conf);
my $confdir = set_conf_dir();

sub MY::postamble { 

'TNPITOASTER	=	/Users/Shared/Sites/www.tnpi.biz/internet/mail/toaster
TNPIMAILLOG =   /Users/Shared/Sites/www.tnpi.biz/internet/mail/maillogs
CONFDIR    =   ' . $confdir . '
MAILLOG		=	' . $logdir . '
MODULES		=	doc/modules
MT		=	Mail::Toaster

conf:
	install -m 0644 toaster.conf-dist $(CONFDIR)
	install -m 0640 toaster-watcher.conf-dist $(CONFDIR)
	echo make newconf is deprecated! Use: toaster_setup.pl -s config

newconf:
	install -m 0644 toaster.conf-dist $(CONFDIR)
	install -m 0640 toaster-watcher.conf-dist $(CONFDIR)
	echo make newconf is deprecated! Use: toaster_setup.pl -s config

cgi:
	echo make cgi is deprecated! Use toaster_setup.pl -s webmail instead.


web:
	install bin/toaster_setup.pl       $(TNPITOASTER)/
	install cgi_files/index.cgi        $(TNPITOASTER)/index.cgi.txt
	install bin/mailadmin              $(TNPITOASTER)/maildomain/mailadmin
	install bin/toaster-watcher.pl     $(TNPITOASTER)/watcher/
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
	'EXE_FILES'      => [ 'cgi_files/index.cgi', 
                          'bin/toaster_setup.pl', 
                          'bin/toaster-watcher.pl',
					      'bin/mailadmin', 
                          'bin/maillogs', 
                          'bin/qqtool.pl',
                        ],
	'INSTALLSCRIPT'  => '/usr/local/sbin',
	'PREREQ_PM'      => { 
			'DBI'           => 1, 
			'Date::Parse'   => 1, 
			'Test::Simple'  => 0,
#			'Net::DNS'      => 0.20, 
#			'Quota'         => 0,
#			'vpopmail'      => 0, 
#			'Email::Valid'  => 0, 
#			'Mail::Ezmlm'   => 0,
#			'HTML::Template' => 1,
		},
	AUTHOR            => 'Matt Simerson (matt@tnpi.net)',
	ABSTRACT          => 'Mail::Toaster perl programs and modules',
    PL_FILES          => {},
#	MAN1PODS          => [],
#    dist              => { COMPRESS => 'gzip -9f', },
    clean             => {FILES => "t/trash"}
);

sub set_conf_dir {   
    my $dir = "/usr/local/etc";
    if  ( $^O eq "darwin") { $dir = "/opt/local/etc" };  # Mac OS X
    return $dir;     
}

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2004-2006, The Network People, Inc. All rights reserved.

 
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 
Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 
Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
