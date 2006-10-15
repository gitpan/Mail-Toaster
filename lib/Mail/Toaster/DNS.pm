#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: DNS.pm,v 5.00 2006/03/18 20:13:21 matt Exp $
#

package Mail::Toaster::DNS;

use vars qw($VERSION);

$VERSION = '5.01';

use lib "lib";

use Carp;
use Params::Validate qw( :all );

use Mail::Toaster::Utility 5;
    my $utility = Mail::Toaster::Utility->new;
use Mail::Toaster::Perl;
    my $perl = Mail::Toaster::Perl->new;

sub new {
    my $class = shift;
    my $self = { class => $class };
    bless( $self, $class );
    return $self;
}

sub is_ip_address {

    my $self = shift;

    my %p = validate(
        @_,
        {   'ip'    => { type => SCALAR, },
            'rbl'   => { type => SCALAR, },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
        },
    );

    my ( $ip, $rbl, $fatal, $debug )
        = ( $p{'ip'}, $p{'rbl'}, $p{'fatal'}, $p{'debug'} );

    my $r = $ip =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/;

    if ( $r == 0 ) {
        print "hrmmm, $ip didn't match an IP address format\n" if $debug;
        croak                                                  if $fatal;
        return 0;
    }

    return "$4.$3.$2.$1.$rbl";
}

sub rbl_test {

    my $self = shift;

    my %p = validate(
        @_, {   
            'zone'  => SCALAR,
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'conf'  => {
                    type     => HASHREF,
                    optional => 1,
                    default  => { rbl_enable_lookup_using => 'net-dns' }
                },
        },
    );

    my ( $conf, $zone, $fatal, $debug )
        = ( $p{'conf'}, $p{'zone'}, $p{'fatal'}, $p{'debug'} );

    #	$net_dns->tcp_timeout(5);   # really shouldn't matter
    #	$net_dns->udp_timeout(5);

    # First we make sure their zone has active name servers
    return 0
        unless $self->rbl_test_ns( conf => $conf, rbl => $zone,
        debug => $debug );

    # then we test an IP that should always return an A record
    # for most RBL's this is 127.0.0.2, (2.0.0.127.bl.example.com)
    return 0
        unless $self->rbl_test_positive_ip(
        conf  => $conf,
        rbl   => $zone,
        debug => $debug
        );

    # Now we test an IP that should always yield a negative response
    return 0
        unless $self->rbl_test_negative_ip(
        conf  => $conf,
        rbl   => $zone,
        debug => $debug
        );

    return 1;
}

sub rbl_test_ns {

    my $self = shift;

    my %p = validate( @_, {   
            'rbl'   => SCALAR,
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'conf'  => { type => HASHREF, optional => 1, },
        },
    );

    my ( $conf, $rbl, $fatal, $debug )
        = ( $p{'conf'}, $p{'rbl'}, $p{'fatal'}, $p{'debug'} );

    my $testns = $rbl;

    if ( $rbl =~ /rbl\.cluecentral\.net$/ ) {
        $testns = "rbl.cluecentral.net";
    }
    elsif ( $rbl eq "spews.blackhole.us" ) {
        $testns = "ls.spews.dnsbl.sorbs.net";
    }
    elsif ( $rbl =~ /\.dnsbl\.sorbs\.net$/ ) { $testns = "dnsbl.sorbs.net" }

    my $ns = $self->resolve(record=>$testns, type=>"NS", debug=>$debug);
    if ( !$ns ) { $ns = 0; };

    print "rbl_test_ns: found $ns NS servers.\n" if $debug;
    $ns > 0 ? return 1 : return 0;
}

sub rbl_test_positive_ip {

    my $self = shift;

    my %p = validate(
        @_,
        {   'conf' => { type => HASHREF, optional => 1, },
            'rbl'  => { type => SCALAR, },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
        },
    );

    my ( $conf, $rbl, $fatal, $debug )
        = ( $p{'conf'}, $p{'rbl'}, $p{'fatal'}, $p{'debug'} );

    my $ip      = 0;
    my $test_ip = $rbl eq "korea.services.net"     ? "61.96.1.1"
                : $rbl eq "kr.rbl.cluecentral.net" ? "61.96.1.1"
                : $rbl eq "cn-kr.blackholes.us"    ? "61.96.1.1"
                : $rbl eq "cn.rbl.cluecentral.net" ? "210.52.214.8"
                : $rbl =~ /rfc-ignorant\.org$/     ? return 1    # no test ips!
                : "127.0.0.2";

    print "rbl_test_positive_ip: testing with ip $test_ip\n" if $debug;

    my $test = $self->is_ip_address( ip => $test_ip, rbl => $rbl );
    return 0 if ! $test;

    print "\tquerying $test..." if $debug;

    my @rrs = $self->resolve( record=>$test, type=>"A", debug=>$debug );

    foreach my $rr ( @rrs ) {
        next unless $rr =~ /127\.[0-1]\.0/;
        $ip++;
        print " from ", $rr if $debug;
        print " matched.\n" if $debug;
    }

    print "rbl_test_positive_ip: we have $ip addresses.\n" if $debug;
    $ip > 0 ? return $ip : return 0;
}

sub rbl_test_negative_ip {

    my $self = shift;

    my %p = validate( @_, {   
            'rbl'   => SCALAR,
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'conf'  => { type => HASHREF, optional => 1, },
        },
    );

    my ( $conf, $rbl, $fatal, $debug )
        = ( $p{'conf'}, $p{'rbl'}, $p{'fatal'}, $p{'debug'} );

    my $test_ip = $rbl eq "korea.services.net"     ? "69.39.74.33"
                : $rbl eq "kr.rbl.cluecentral.net" ? "69.39.74.33"
                : $rbl eq "cn.rbl.cluecentral.net" ? "69.39.74.33"
                : $rbl eq "us.rbl.cluecentral.net" ? "210.52.214.8"
                : "69.39.74.33";

    my $fip = 0;

    my $test = $self->is_ip_address( ip => $test_ip, rbl => $rbl );
    return 0 unless $test;

    print "querying $test..." if $debug;

    my @rrs = $self->resolve( record=>$test, type=>"A", debug=>$debug );
    return 1 if ! @rrs;

    foreach my $rr ( @rrs ) {
        next unless $rr =~ /127\.0\.0/;
        $fip++;
        print " from ", $rr if $debug;
        print " matched.\n" if $debug;
    }

    $fip > 0 ? return 0 : return 1;
}

sub resolve {

    my $self = shift;
    
    my %p = validate(@_, {
            record => SCALAR,
            type   => SCALAR,
            debug  => { type=>BOOLEAN, optional=>1, default=>1, },
            fatal  => { type=>BOOLEAN, optional=>1, default=>1, },
            conf   => { type=>HASHREF, optional=>1, },
        },
    );

    my ( $conf, $record, $type, $debug ) 
        = ( $p{'conf'}, $p{'record'}, $p{'type'}, $p{'debug'} );

    my $resolver = "net_dns";

    if ( ! $perl->has_module("Net::DNS") ) {
        $resolver = "dig";
    };

    if ( $conf && $conf->{'rbl_enable_lookup_using'}
               && $conf->{'rbl_enable_lookup_using'} eq "dig" )
    {
        $resolver = "dig";
    };

    my @records;

    if ( $resolver eq "dig" ) {
        my $dig = $utility->find_the_bin( bin => 'dig', debug=>0 );

        foreach (`$dig $type $record +short`) {
            chomp;
            push @records, $_;
            print "resolve: found $_\n" if $debug;
        }
        return @records;
    }

    require Net::DNS;
    my $net_dns = Net::DNS::Resolver->new;

    my $query = $net_dns->query( $record, $type );
    unless ($query) {
        carp "resolver query failed for $record: ", $net_dns->errorstring if $debug;
        return;
    }

    foreach my $rr (grep { $_->type eq $type } $query->answer ) {
        if ( $type eq "NS" ) {
            print "$record $type: ", $rr->nsdname, "\n" if $debug;
            push @records, $rr->nsdname;
        } 
        elsif ( $type eq "A" ) {
            push @records, $rr->address;
            print "$record $type: ", $rr->address, "\n" if $debug;
        }
        elsif ( $type eq "PTR" ) {
            push @records, $rr->rdatastr;
            print "$record $type: ", $rr->rdatastr, "\n" if $debug;
        }
    }

    return @records;
};


1;
__END__


=head1 NAME

Mail::Toaster::DNS - DNS functions, primarily to test RBLs


=head1 SYNOPSIS

A set of subroutines for testing rbls to verify that they are functioning properly. If Net::DNS is installed it will be used but we can also test using dig. 


=head1 DESCRIPTION

These functions are used by toaster-watcher to determine if RBL's are available when generating qmail's smtpd/run control file.


=head1 SUBROUTINES

=over 

=item new

Create a new DNS method:

   use Mail::Toaster::DNS;
   my $dns = Mail::Toaster::DNS->new;


=item rbl_test

After the demise of osirusoft and the DDoS attacks currently under way against RBL operators, this little subroutine becomes one of necessity for using RBL's on mail servers. It is called by the toaster-watcher.pl script to test the RBLs before including them in the SMTP invocation.

	my $r = $dns->rbl_test(conf=>$conf, zone=>"bl.example.com");
	if ($r) { print "bl tests good!" };

 arguments required:
    zone - the zone of a blacklist to test

 arguments optional:
    debug

Tests to make sure that name servers are found for the zone and then run several test queries against the zone to verify that the answers it returns are sane. We want to detect if a RBL operator does something like whitelist or blacklist the entire planet.

If the blacklist fails any test, the sub will return zero and you should not use that blacklist.


=item rbl_test_ns

	my $count = $t_dns->rbl_test_ns(
	    conf  => $conf, 
	    rbl   => $rbl, 
	    debug => $debug,
	);

 arguments required:
    rbl   - the reverse zone we use to test this rbl.

This script requires a zone name. It will then return a count of how many NS records exist for that zone. This sub is used by the rbl tests. Before we bother to look up addresses, we make sure valid nameservers are defined.


=item rbl_test_positive_ip

	$t_dns->rbl_test_positive_ip( rbl=>'sbl.spamhaus.org' );

 arguments required:
    rbl   - the reverse zone we use to test this rbl.

 arguments optional:
    conf
    debug

A positive test is a test that should always return a RBL match. If it should and does not, then we assume that RBL has been disabled by its operator.

Some RBLs have test IP(s) to verify they are working. For geographic RBLs (like korea.services.net) we can simply choose any IP within their allotted space. Most other RBLs use 127.0.0.2 as a positive test.

In the case of rfc-ignorant.org, they have no known test IPs and thus we have to skip testing them.


=item rbl_test_negative_ip

	$t_dns->rbl_test_negative_ip(conf=>$conf, rbl=>$rbl);

This test is a little more difficult as RBL operators don't typically have an IP that is whitelisted. The DNS location based lists are very easy to test negatively. For the rest I'm listing my own IP as the default unless the RBL has a specific one. At the very least, my site won't get blacklisted that way. ;) I'm open to better suggestions.



=back

=head1 AUTHOR

Matt Simerson <matt@tnpi.net>


=head1 BUGS

None known. Report any to author.


=head1 TODO

=head1 SEE ALSO

The following man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://mail-toaster.org/


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004-2006, The Network People, Inc.  All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

