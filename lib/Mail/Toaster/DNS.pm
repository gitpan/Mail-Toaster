#!/usr/bin/perl
use strict;

#
# $Id: DNS.pm,v 1.4 2003/12/17 14:45:36 matt Exp $
#

package Mail::Toaster::DNS;

use Carp;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

$VERSION = '1.3';

@ISA       = qw( Exporter );
@EXPORT    = qw( 
	RblTest
);
@EXPORT_OK = qw();

use lib ".";
use lib "lib";
use MATT::Perl;


=head1 NAME

Mail::Toaster::DNS - Common DNS functions


=head1 SYNOPSIS

Mail::Toaster::DNS is a grouping of DNS functions I've written.


=head1 DESCRIPTION

These functions are used by toaster-watcher to determine if RBL's are available when generating qmail's smtpd/run control file.

=cut

sub RblTest
{
	my ($zone, $debug) = @_;
	
=head2 RblTest

	use Mail::Toaster::DNS;
	my $r = RblTest("bl.example.com");
	if ($r) { print "bl tests good!" };

After the demise of osirusoft and the DDoS attacks currently under way against RBL operators, this little subroutine becomes one of necessity. 

The routine expects to receive the zone of a blacklist to test as it's first argument and a possible debug value (set to a non-zero value) as it's second. 

It will then test to make sure that name servers are found for the zone and then run several test queries against the zone to verify that the answers it returns are sane. We want to detect if a RBL operator does something like whitelist or blacklist the entire planet.

If the blacklist fails any test, the sub willl return zero and you should not use that blacklist.

=cut

	LoadModule("Net::DNS", "p5-Net-DNS", "dns");

	my $r  = Net::DNS::Resolver->new;

	$r->tcp_timeout(5);   # really shouldn't matter
	$r->udp_timeout(5);

	# First we make sure their zone has active name servers

	my $ns      = 0;
	my $query   = $r->query( GetRblTestNS($zone), "NS");

	if ( $query )
	{
		foreach my $rr ( $query->answer ) 
		{
			next unless ($rr->type eq "NS");
			$ns++;
#			print "$zone ns: ", $rr->nsdname, "\n" if $debug;
		};
	} 
	else 
	{ 
		carp "ns query failed for $zone: ", $r->errorstring if $debug;
		return 0; 
	};

	return 0 unless ($ns > 0);
	print "good, we have $ns NS servers, we can go on.\n" if $debug;

	# then we test an IP that should always return an A record
	# for most RBL's this is 127.0.0.2, (2.0.0.127.bl.example.com)

	my $ip      = 0;
	my $test_ip = GetRblTestPositiveIP($zone);

	if ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		my $test = "$4.$3.$2.$1.$zone";

		print "querying $test..." if $debug;

		my $query = $r->query($test, "A" );
		if ( $query )
		{
			foreach my $rr ( $query->answer )
			{
				print "found: ", $rr->type, " = ", $rr->address if $debug;
				next unless $rr->type eq "A";
				next unless $rr->address =~ /127\.0\.0/;
				$ip++;
				# print " from ", $query->answerfrom if $debug;
				print " matched.\n" if $debug;
			};
		} 
		else 
		{ 
			carp "query failed for $zone: ", $r->errorstring if $debug;
			return 0;
		};
	} 
	else 
	{ 
		print "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	return 0 unless ($ip > 0);
	print "good, we have $ip addresses, we can go on.\n" if $debug;


	# Now we test an IP that should always yield a negative response

	my $fip    = 0;
	$test_ip   = GetRblTestNegativeIP($zone);

	if ( $test_ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
	{
		my $test = "$4.$3.$2.$1.$zone";

		print "querying $test..." if $debug;

		my $query = $r->query($test, "A" );
		if ( $query )
		{
			foreach my $rr ( $query->answer )
			{
				print "found: ", $rr->type, " = ", $rr->address if $debug;
				next unless $rr->type eq "A";
				next unless $rr->address =~ /127\.0\.0/;
				$ip++;
				# print " from ", $query->answerfrom if $debug;
				print " matched.\n" if $debug;
			};
		} 
		else { return 1 };  # it's all good if this fails
	} 
	else 
	{ 
		carp "hrmmm, $test_ip didn't match an IP address format" if $debug;
		return 0;
	};

	if ( $fip > 0 ) { return 0 } else { return 1 };
};

sub GetRblTestNS
{

=head2 GetRblTestNS

	use Mail::Toaster::DNS;
	GetRblTestNS($rbl);

$rbl is the reverse zone we use to test this rbl.

=cut

	my ($rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "69.$rbl" } 
	elsif ( $rbl =~ /rbl\.cluecentral\.net$/ ) { return "rbl.cluecentral.net" } 
	else                                       { return $rbl };
};

sub GetRblTestPositiveIP
{

=head2 GetRblTestPositiveIP

	use Mail::Toaster::DNS;
	GetRblTestPositiveIP($rbl);

$rbl is the reverse zone we use to test this rbl. Positive test is a test that should always return a RBL match. If it should and doesn't, then we assume that RBL has been disabled by it's operator.

=cut

	my ($rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "61.96.1.1"    } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { return "61.96.1.1"    }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { return "210.52.214.8" }
	else                                       { return "127.0.0.2"    };
};

sub GetRblTestNegativeIP
{

=head2 GetRblTestNegativeIP

	use Mail::Toaster::DNS;
	GetRblTestNegativeIP($rbl);

This test is difficult as RBL operators don't typically have an IP that's whitelisted. The DNS location based lists are very easy to test negatively. For the rest I'm listing my own IP as the default unless the RBL has a specific one. At the very least, my site won't get blacklisted that way. ;) I'm open to better suggestions.

=cut

	my ($rbl) = @_;

	if    ( $rbl eq "korea.services.net"     ) { return "207.89.154.94"  } 
	elsif ( $rbl eq "kr.rbl.cluecentral.net" ) { return "207.89.154.94"  }
	elsif ( $rbl eq "cn.rbl.cluecentral.net" ) { return "207.89.154.94"  }
	elsif ( $rbl eq "us.rbl.cluecentral.net" ) { return "210.52.214.8"   }
	else                                       { return "207.89.154.94"  };
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

=head1 SEE ALSO

http://www.tnpi.biz/computing/
http://www.tnpi.biz/computing/perl/MATT-Bundle/

Mail::Toaster::CGI, Mail::Toaster::DNS, 
Mail::Toaster::Logs, Mail::Toaster::Qmail, 
Mail::Toaster::Setup


=head1 COPYRIGHT

Copyright 2003, The Network People, Inc. All Rights Reserved.

=cut

