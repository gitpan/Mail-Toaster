#!/usr/bin/perl
use strict;

use vars qw( $VERSION );

#
# $Id: toaster_setup.pl,v 1.20 2004/02/14 21:40:46 matt Exp $
#

$VERSION = "3.33";

=head1 NAME

toaster_setup.pl - Everything you need to build a mail toaster except a computer

=head1 SYNOPSIS

To build a great mail system, install FreeBSD (latest stable), and follow
the directions on the toaster page (see URL below).

=head1 DESCRIPTION

A complete set of instructions for building a mail toaster are on the toaster install page. There is actually quite a bit of documenation available for the "Matt Style" toaster. Much of it is within the Perl code itself and is thus readable via "perldoc Mail::Toaster", and all the subsequent doc pages. Of course, don't forget to read the Install, Configure, and FAQ pages on the web site. If you still have questions, the mailing list archives are browseable and searchable for your convenience. Lastly, there is also a bit of documentation in the configuration files.

	http://www.tnpi.biz/internet/mail/toaster/

=cut

use Getopt::Long;
use MATT::Utility 1;
use MATT::FreeBSD 1;
use MATT::Perl    1;
use Mail::Toaster::Setup;
use Mail::Toaster::Qmail;

use vars qw/ $conf /;

$| = 1;
my $user = (getpwuid ($<))[0];

if ( $user ne "root") { die "Thou shalt have root to proceed!\n"; };

CheckPerl();

my %options = (
	'action=s'    => \my $action,
	'secti=s'     => \my $section,
	'debug=s'     => \my $debug
);
GetOptions (%options);

if ( !$action  ) { $action = "install"; };
if ( !$section ) { die "usage: $0 -s pre -v\n"; };

if ( -e "/usr/local/etc/toaster-watcher.conf") 
{
	# if the config file exists, then use it's values to override whatever
	# default values are set in this script. This gives the user the ability
	# to not be stuck with my defaults (or have to painfully change them)

	$conf = ParseConfigFile("toaster-watcher.conf", $debug);
} 
else 
{
	print "\n\nWARNING: You haven't installed toaster-watcher.conf!\n\n\n";
};

my $src = $conf->{'toaster_src_dir'};
unless ( $src ) { $src = "/usr/local/src"; };

if    ( $section eq "pre"         ) { InstallToasterDependencies($conf)  }
elsif ( $section eq "ports"       ) { InstallPorts($conf)                }
elsif ( $section eq "sources"     ) { InstallSources($conf)              }
elsif ( $section eq "mysql"       ) { InstallMysqld($conf);              }
elsif ( $section eq "phpmyadmin"  ) { InstallPhpMyAdminW($conf);         }
elsif ( $section eq "apache"      ) { InstallApache($conf,undef )        }
elsif ( $section eq "apache1"     ) { InstallApache($conf,1)             }
elsif ( $section eq "apache2"     ) { InstallApache($conf,2)             }
elsif ( $section eq "apachessl"   ) { InstallApache($conf,"ssl")         }
elsif ( $section eq "apacheconf"  ) { ApacheConfPatch()                  }
elsif ( $section eq "ucspi"       ) { InstallUCSPI($conf)                }
elsif ( $section eq "ezmlm"       ) { InstallEzmlm($conf)                }
elsif ( $section eq "vpopmail"    ) { InstallVpopmail($conf);            }
elsif ( $section eq "vpeconfig"   ) { ConfigVpopmailEtc($conf);          }
elsif ( $section eq "qmail"       ) { InstallQmail($conf)                } 
elsif ( $section eq "qmailadmin"  ) { InstallQmailadmin($conf);          }
elsif ( $section eq "sqwebmail"   ) { InstallSqwebmail($conf);           } 
elsif ( $section eq "courier"     ) { InstallCourier($conf)              } 
elsif ( $section eq "squirrelmail") { InstallSquirrelmail($conf);        } 
elsif ( $section eq "filter"      ) { InstallFilter($conf);              }
elsif ( $section eq "clamav"      ) { InstallClamAV($conf);              }
elsif ( $section eq "qmailscanner") { InstallQmailScanner($conf);        }
elsif ( $section eq "qss"         ) { InstallQmailScannerStats($conf);   }
elsif ( $section eq "supervise"   ) { InstallSupervise($conf);           }
elsif ( $section eq "maillogs"    ) { InstallMailLogs($conf);            }
elsif ( $section eq "rrdutil"     ) { InstallRRDutil();                  }
elsif ( $section eq "mattbundle"  ) { InstallMATTBundle();               }
elsif ( $section eq "socklog"     ) { InstallSocklog();                  };

print "\n$0 script execution complete.\n";

exit 1;
__END__


=head1 AUTHOR

	Matt Simerson <matt@tnpi.biz>

=head1 BUGS

	None known. Report any to author.


=head1 TODO

	Start up daemons after we install them.
	Check if daemons are running before installs.
	Add checks to pkg_add so that if pkg_add -r fails, install from ports
	Turn entire process into a ./install_it_all script
	Add -s dnscache section to install a DNS stub resolver


=head1 SEE ALSO

 http://matt.simerson.net/computing/mail/toaster/
 http://matt.simerson.net/computing/mail/toaster/faq.shtml
 http://matt.simerson.net/computing/mail/toaster/changelog.shtml

Mail::Toaster::CGI, Mail::Toaster::DNS, 
Mail::Toaster::Logs, Mail::Toaster::Qmail, 
Mail::Toaster::Setup


=head1 COPYRIGHT

	Copyright 2001 - 2003, Matt Simerson. All Right Reserved.

=cut
