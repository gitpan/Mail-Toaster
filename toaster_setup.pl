#!/usr/bin/perl
use strict;

use vars qw( $VERSION );

#
# $Id: toaster_setup.pl,v 4.1 2004/11/16 21:20:01 matt Exp $
#

$VERSION = "4.00";

=head1 NAME

toaster_setup.pl - Everything you need to build a mail toaster except a computer

=head1 SYNOPSIS

To build a great mail system, install FreeBSD (latest stable), and follow
the directions on the toaster page (see URL below).

=head1 DESCRIPTION

A complete set of instructions for building a mail toaster are on the toaster install page. There is actually quite a bit of documenation available for the "Matt Style" toaster. Much of it is readable via "perldoc Mail::Toaster", and all the subsequent pages. Don't forget to read the Install, Configure, and FAQ pages on the web site. If you still have questions, the mailing list archives are browseable and searchable for your convenience. 

	http://www.tnpi.biz/internet/mail/toaster/

=cut

use Getopt::Long;
use Mail::Toaster::FreeBSD 4; my $freebsd = new Mail::Toaster::FreeBSD;
use Mail::Toaster::Perl    4; my $perl    = new Mail::Toaster::Perl;
use Mail::Toaster::Qmail   4; my $qmail   = new Mail::Toaster::Qmail;
use Mail::Toaster::Setup   4; my $setup   = new Mail::Toaster::Setup;
use Mail::Toaster::Utility 4; my $utility = new Mail::Toaster::Utility;
use Mail::Toaster::Apache  4; my $apache  = new Mail::Toaster::Apache;

use vars qw/ $conf /;

$| = 1;
my $user = (getpwuid ($<))[0];

if ( $user ne "root") { die "Thou shalt have root to proceed!\n"; };

my %options = (
	'action=s'    => \my $action,
	'secti=s'     => \my $section,
	'debug=s'     => \my $debug
);
GetOptions (%options);

=head2 command line flags

toaster_setup.pl can be passed several flags. 
  -s [ section ] - run without a parameter to see the available options
  -d [ debug   ] - enabled (very) verbose debugging output
  -a [ action  ] - default action is "install". 

An -a upgrade option is planned.

=cut

$action ||= "install";
unless ( $section ) { usage(); die "You must choose a section!\n"; };

unless ( -e "/usr/local/etc/toaster-watcher.conf") 
{
	print "\n\nWARNING: You haven't installed toaster-watcher.conf!\n\n\n";
};

# use the config file values to override whatever
# default values are set in this script. This gives the user the ability
# to not be stuck with my defaults (or have to painfully change them)

$conf = $utility->parse_config( { file=>"toaster-watcher.conf", debug=>$debug} );

$conf->{'debug'} = 1 if $debug;

my $src = $conf->{'toaster_src_dir'};
unless ( $src ) { $src = "/usr/local/src"; };

unless ( $section eq "ports" or $section eq "sources" ) {
	$perl->check();
};

if    ( $section eq "pre"         ) { $setup->dependencies($conf)          }
elsif ( $section eq "perl"        ) { $perl->check($conf, $debug)          }
elsif ( $section eq "ports"       ) { $setup->ports($conf)                 }
elsif ( $section eq "sources"     ) { $freebsd->source_update($conf)       }
elsif ( $section eq "mysql"       ) { $setup->mysqld($conf)                }
elsif ( $section eq "phpmyadmin"  ) { $setup->phpmyadmin($conf)            }
elsif ( $section eq "apache"      ) { $setup->apache($conf,undef)          }
elsif ( $section eq "apache1"     ) { $setup->apache($conf,1)              }
elsif ( $section eq "apache2"     ) { $setup->apache($conf,2)              }
elsif ( $section eq "apachessl"   ) { $setup->apache($conf,"ssl")          }
elsif ( $section eq "apacheconf"  ) { $apache->conf_patch($conf)           }
elsif ( $section eq "ucspi"       ) { $setup->ucspi($conf)                 }
elsif ( $section eq "ezmlm"       ) { $setup->ezmlm($conf)                 }
elsif ( $section eq "vpopmail"    ) { $setup->vpopmail($conf)              }
elsif ( $section eq "vpeconfig"   ) { $setup->config_vpopmail_etc($conf)   }
elsif ( $section eq "vpopmysql"   ) { $setup->vpopmail_mysql_privs($conf)  }
elsif ( $section eq "vqadmin"     ) { $setup->vqadmin($conf)               }
elsif ( $section eq "qmail"       ) { $qmail->install_qmail($conf)         } 
elsif ( $section eq "qmailconf"   ) { $qmail->config($conf)                } 
elsif ( $section eq "netqmail"    ) { $qmail->netqmail($conf)              } 
elsif ( $section eq "netqmailmac" ) { $qmail->netqmail_virgin($conf)       } 
elsif ( $section eq "qmailadmin"  ) { $setup->qmailadmin($conf)            }
elsif ( $section eq "sqwebmail"   ) { $setup->sqwebmail($conf)             } 
elsif ( $section eq "courier"     ) { $setup->courier($conf)               } 
elsif ( $section eq "courierconf" ) { $setup->config_courier($conf)        } 
elsif ( $section eq "squirrelmail") { $setup->squirrelmail($conf)          } 
elsif ( $section eq "filter"      ) { $setup->filtering($conf)             }
elsif ( $section eq "maildrop"    ) { $setup->maildrop($conf)              }
elsif ( $section eq "clamav"      ) { $setup->clamav($conf)                }
elsif ( $section eq "qmailscanner") { $setup->qmail_scanner($conf)         }
elsif ( $section eq "simscan"     ) { $setup->simscan($conf)               }
elsif ( $section eq "qss"         ) { $setup->qs_stats($conf)              }
elsif ( $section eq "supervise"   ) { $setup->supervise($conf)             }
elsif ( $section eq "maillogs"    ) { $setup->maillogs($conf)              }
elsif ( $section eq "rrdutil"     ) { $setup->rrdutil($conf)               }
elsif ( $section eq "mattbundle"  ) { $setup->mattbundle($conf)            }
elsif ( $section eq "socklog"     ) { $setup->socklog($conf)               }
elsif ( $section eq "toaster"     ) { $utility->mailtoaster($debug)        }
elsif ( $section eq "jailadd"     ) { $freebsd->jail_create()              }
elsif ( $section eq "jailstart"   ) { $freebsd->jail_start()               }
elsif ( $section eq "jaildelete"  ) { $freebsd->jail_delete()              }
elsif ( $section eq "test"        ) { $setup->test($conf)                  }
elsif ( $section eq "all"         ) 
{
	$setup->dependencies($conf);
	$setup->ports($conf);
	$setup->mysqld($conf); 
	$setup->apache($conf,2);
	$setup->phpmyadmin($conf);
	$setup->ucspi($conf);
	$setup->ezmlm($conf);
	$setup->vpopmail($conf);
	$setup->maildrop($conf);
	$setup->vqadmin($conf);
	$setup->qmailadmin($conf);
	$qmail->netqmail($conf);
	$setup->courier($conf);
	$setup->sqwebmail($conf);
	$setup->squirrelmail($conf);
	$setup->filtering($conf);
	$setup->maillogs($conf);
	$setup->supervise($conf);
	$setup->rrdutil($conf);
	$setup->test($conf);
}
else  { usage(); };

print "\n$0 script execution complete.\n";

exit 1;

sub usage 
{
	print <<EOUSAGE

  usage $0 -s [ section ] [-debug]

           pre - installs a list of programs and libraries other toaster components need
          perl - installs or upgrades perl
         ports - updates your ports tree, installs the pkg_* tools
       sources - update your FreeBSD sources (/usr/src)
         mysql - installs MySQL
    phpmyadmin - installs phpMyAdmin
        apache - installs Apache 
     apachessl - installs self signed SSL certs for Apache
    apacheconf - patches httpd.conf for use with Mail::Toaster
         ucspi - install ucspi w/MySQL patch
         ezmlm - install EzMLM idx
      vpopmail - installs vpopmail
     vpeconfig - configure ~vpopmail/etc/tcp.smtp
     vpopmysql - run the vpopmail MySQL grant and db create commands
       vqadmin - install vqadmin
         qmail - installs qmail with toaster patches
     qmailconf - configure various qmail control files
      netqmail - installs netqmail 
   netqmailmac - installs netqmail with no patches
    qmailadmin - installs qmailadmin
     sqwebmail - installs sqwebmail (webmail app)
       courier - installs courier imap & pop3 daemons
  squirrelmail - installs squirrelmail (webmail app)
        filter - installs SpamAssassin, ClamAV, DCC, razor, and more
      maildrop - installs maildrop and mailfilter
        clamav - installs just ClamAV
  qmailscanner - installs Qmail-Scanner & qmailscanner stats
       simscan - install simscan
           qss - installs qmailscanner stats
     supervise - creates the directories to be used by svscan
      maillogs - creates the mail logging directories
       rrdutil - installs rrdutil
    mattbundle - install MATT::Bundle
       toaster - install Mail::Toaster
       socklog - installs socklog
       jailadd - creates a new jail
     jailstart - starts up an existing jail
    jaildelete - deletes an existing jail
           all - installs everything shown on the toaster INSTALL page

EOUSAGE

};

__END__

=head1 USAGE

  toaster_setup.pl -s [ section ] [-debug]

           pre - installs a list of programs and libraries other toaster components need
         ports - updates your ports tree, installs the pkg_* tools
       sources - update your FreeBSD sources (/usr/src)
         mysql - installs MySQL
    phpmyadmin - installs phpMyAdmin
        apache - installs Apache 
     apachessl - installs self signed SSL certs for Apache
    apacheconf - patches httpd.conf for use with Mail::Toaster
         ucspi - install ucspi w/MySQL patch
         ezmlm - install EzMLM idx
      vpopmail - installs vpopmail
     vpeconfig - configure ~vpopmail/etc/tcp.smtp
     vpopmysql - run the vpopmail MySQL grant and db create commands
         qmail - installs qmail with toaster patches
     qmailconf - configure various /var/qmail/control/* files
      netqmail - installs netqmail 
    qmailadmin - installs qmailadmin
     sqwebmail - installs sqwebmail (webmail app)
       courier - installs courier imap & pop3 daemons
  squirrelmail - installs squirrelmail (webmail app)
        filter - installs SpamAssassin, ClamAV, DCC, razor, and more
        clamav - installs just ClamAV
  qmailscanner - installs Qmail-Scanner & qmailscanner stats
           qss - installs qmailscanner stats
     supervise - creates the directories to be used by svscan
      maillogs - creates the mail logging directories
       rrdutil - installs rrdutil
    mattbundle - install MATT::Bundle
       toaster - install Mail::Toaster
       socklog - installs socklog
           all - installs everything shown on the toaster INSTALL page


=head1 AUTHOR

	Matt Simerson <matt@tnpi.biz>

=head1 BUGS

	None known. Report any to author.


=head1 TODO

	Check if daemons are running before installs.
	Turn entire process into a ./install_it_all script
	Add -s dnscache section to install a DNS stub resolver


=head1 SEE ALSO

Mail::Toaster::CGI, Mail::Toaster::DNS, 
Mail::Toaster::Logs, Mail::Toaster::Qmail, toaster.conf
Mail::Toaster::Setup, Mail::Toaster::Conf, toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/
 http://matt.simerson.net/computing/mail/toaster/faq.shtml
 http://matt.simerson.net/computing/mail/toaster/changelog.shtml


=head1 COPYRIGHT

Copyright (c) 2004, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
