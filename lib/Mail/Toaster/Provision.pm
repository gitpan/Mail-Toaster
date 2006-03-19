#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Provision.pm,v 4.7 2005/05/10 02:28:43 matt Exp $
#

package Mail::Toaster::Provision;

use Carp;
use Getopt::Long;

use lib "lib";
use lib "../../";

use Mail::Toaster::Passwd 1.17; my $password = Mail::Toaster::Passwd->new();
use Mail::Toaster::Utility;     my $utility = Mail::Toaster::Utility->new();

my $VERSION = '4.3';


=head1 NAME

Mail::Toaster::Provision

=head1 SYNOPSIS

Account provisioning methods.

=head1 DESCRIPTION

A suite of methods for provisioning various account types on unix like systems (Mac OS X, *BSD, Linux). Builds system accounts (/etc/passwd), web hosting accounts, mail hosting accounts, and DNS hosting accounts.

=head1 DEPENDENCIES

 Quota         (/usr/ports/sysutils/p5-Quota)

=head1 METHODS

=head2 new

To use the following methods, you must first create a provision object. Then invoke any of the methods that follow using your provision object.

  use Mail::Toaster::Provision;
  my $prov = Mail::Toaster::Provision->new();

  $vals = { action => $ARGV[0], debug => 1 };

  $prov->example_method($vals, $conf);

All the public methods will expect to be passed $conf. $conf is a hashref of values pulled from sysadmin.conf. You can get it by calling $utility->parse_config as follows: 

   $conf = $utility->parse_config({file=>"sysadmin.conf"});

$utility is a Mail::Toaster::Utility object.

=cut

sub new
{
	my ($class, $action) = @_;

	my $self = { action => $action };
	bless ($self, $class);
	return $self;
};


sub dns
{

=head2 dns

dns will provision a DNS account using the programming API of a NicTool DNS server. 

=cut

	my (%vals) = @_;

	print "dns.. begining.\n";

	$vals{''} = $ARGV[1];
	$vals{''} = $ARGV[2];
	$vals{''} = $ARGV[3];
	$vals{''} = $ARGV[4];
	$vals{''} = $ARGV[5];

	print "dns....end.\n";
};

sub dns_usage
{
};


sub import {
	my ($self, @params) = @_;
#	print "Look, " . caller() . " is trying to import me!\n";
};

sub mail { };
sub mail_usage { };


=head2 quota_set

Sets a user file system quota.

   my $vals = {
      user             => "bob",
      quota            => 1000,
   };

   $prov->quota_set($vals, $conf);

quota is set in megabytes. A hard limit will be set 5 megs larger than the soft limit.

This method depends on the perl module Quota.

=cut

sub quota_set($$)
{
	# Quota::setqlim($dev, $uid, $bs, $bh, $is, $ih, $tlo, $isgrp);
	# $dev     - filesystem mount or device
	# $bs, $is - soft limits for blocks and inodes
	# $bh, $ih - hard limits for blocks and inodes
	# $tlo     - time limits (0 = first user write, 1 = 7 days)
    # $isgrp   - 1 means that uid = gid, group limits set

	my ($self, $vals, $conf) = @_;

	require Quota;

	my $dev   = $conf->{'quota_filesystem'}; $dev ||= "/home";
	my $uid   = $vals->{'uid'};    $uid ||= getpwnam($vals->{'user'});
	my $quota = $vals->{'quota'};  $quota ||= "100";

	# set the soft limit a few megs higher than the hard limit
	my $quotabump = $quota + 5;

	# convert from megs to 1K blocks
	my $bh = $quota     * 1024;
	my $bs = $quotabump * 1024;

	my $is = $conf->{'quota_inodes_soft'};
	my $ih = $conf->{'quota_inodes_hard'};

	Quota::setqlim($dev, $uid, $bs, $bh, $is, $ih, 1, 0);

	print "user: end.\n" if $vals->{'debug'};

	# we should test the quota here and then return an appropriate result code
};

=head2 user

	$prov->user($vals, $conf)

$vals is a hashref of values

	my $vals = { 
		'action'  => $ARGV[0],
		'debug'   => $opt_v,
	};

user will call several private methods, beginning with user_get_options which collects the details for the new account from the command line (via GetOpts) or via a HTTP form method. Once the options are gathered, it will perform the requested action (create, destroy, disable, enable, show, repair, or test) on the account.

user is very fault tolerant. It makes backup copies of the master.passwd files before altering them and tests to make sure the alterations it made are sane. If something is screwy, it saves a date stamped backup of the file. 

It also sets user quotas.

=cut

sub user($$)
{
	my ($self, $vals, $conf) = @_;
	print "user: begin...\n" if $vals->{'debug'};

	my $r;

	$vals = $self->user_options($vals, $conf);

	$vals->{'user'} ||= $ARGV[1];   # set to cmd line value if it's unset
	unless ($vals->{'user'}) {
		$self->user_usage($vals);
		$utility->graceful_exit(400, "No username passed!");
	};

	print "user: user is set.\n" if $vals->{'debug'};

	my $action = $vals->{'action'};

	if ( $action eq "create" || $action eq "disable" || $action eq "enable" )
	{
		$password->BackupMasterPasswd();
	};

	if    ( $action eq "create"  ) { $r = $password->user_add($vals) }
	elsif ( $action eq "destroy" ) {
		$password->user_archive($vals->{'user'}, $vals->{'debug'}) if ( $conf->{'delete_user_archive'} );
		$password->BackupMasterPasswd();
		$r = $password->delete($vals);
	}
	elsif ( $action eq "disable" ) { $r = $password->disable($vals) }
	elsif ( $action eq "enable"  ) { $r = $password->enable ($vals) }
	elsif ( $action eq "show"    ) { $r = $password->show   ($vals) }
	elsif ( $action eq "repair"  ) { print "none yet\n"; exit 0  }
	elsif ( $action eq "test"    ) { print "none yet\n"; exit 0  }
	else { 
		$self->usage_action();
		$utility->graceful_exit(400, "Invalid Action!");
	}

	if ( $r->{'error_code'} == 200 || $r->{'error_code'} == 100 ) 
	{
		# success
		if ( $action eq "create" ) {
			$password->VerifyMasterPasswd("/etc/master.passwd", "grow", $vals->{'debug'} );
			# set up their file system quotas
			$self->quota_set($vals, $conf) if $conf->{'quota_enable'};
		} 
		elsif ( $action eq "destroy" ) {
			$password->VerifyMasterPasswd("/etc/master.passwd", "shrink", $vals->{'debug'} );
		};
		return $r;
	}
	else
	{
		$self->user_usage($vals);
		use Data::Dumper; print Dumper($r) if $vals->{'debug'};
		return $r;
	};

	print "user: end.\n" if $vals->{'debug'};
};

=head2 user_usage

returns the following message if improper or missing arguments are passed:

	useradmin [action] [username]

    required values:

       -username      

    optional values:

       -password
       -shell
       -homedir
       -comment
       -quota
       -uid
       -gid
       -expire date
       -domain

If domain is set, then tit's assumed that you're setting up a web hosted account and you want the home directory to be /home/domain.com instead of /home/user. This integrates quite nicely with Apache's mass virtual hosting.

=cut

sub user_usage()
{
	my ($self, $vals) = @_;

	print <<EOUSER

	$0 $vals->{'action'} username

    required values:

       -username      

    optional values:

       -password
       -shell
       -homedir
       -comment
       -quota
       -uid
       -gid
       -expire date
       -domain

EOUSER
;
};

sub user_options
{

=head2 user_options

Collects the options required for setting up a user account from the command line (GetOpts) or from a HTTP form submission.

=cut

	my ($self, $vals, $conf) = @_;
	print "user_options: begin..." if $vals->{'debug'};

	if ( $ENV{'GATEWAY_INTERFACE'} ) 
	{
		# get CGI form values
	}
	else 
	{
		# get command line options
		GetOptions (
			"password=s" => \$vals->{'pass'},
			"username=s" => \$vals->{'user'}, 
			"homedir=s"  => \$vals->{'homedir'},
			"shell=s"    => \$vals->{'shell'},
			"comment=s"  => \$vals->{'gecos'},
			"quota=s"    => \$vals->{'quota'},
			"uid=s"      => \$vals->{'uid'},
			"gid=s"      => \$vals->{'gid'},
			"domain=s"   => \$vals->{'domain'},
			"expire=s"   => \$vals->{'expire'},
			"verbose"    => \$vals->{'debug'}
		);

		unless ( $vals->{'shell'} ) {
			if ( $conf->{'use_shell_default'} ) {
				$vals->{'shell'} = $conf->{'use_shell_default'};
			} 
			else { $vals->{'shell'} = "/sbin/nologin" };
		}
	};

	print "end.\n" if $vals->{'debug'};
	return $vals;
};


sub usage
{
		print <<EOCHECK

NOTICE: To access functions other than this menu, make links to this script, naming them the function you want to use. If you want DNS management functions, then you'd create a link like this:

   ln -s sysadmin dnsadmin

and then execute the dnsadmin link.


  usage $0 

    sysadmin   - this menu

    dnsadmin   - options for working with DNS
    webadmin   - options for working with Apache
    useradmin  - options for working with System Users
    mailadmin  - options for working with mail accounts

EOCHECK
;

};

=head2 usage_action

return the following message:

  usage $0 action [params]

	action is one of:

       create  - adding users, domains, etc
       destroy - permanently removing objects

       disable - temporarily disable
       enable  - restore disabled objects

       show    - show current objects and settings

       repair  - misc repair options
       test    - test settings

=cut

sub usage_action()
{
	print <<EOACTION

  usage $0 action [params]

	action is one of:

       create  - adding users, domains, etc
       destroy - permanently removing objects

       disable - temporarily disable
       enable  - restore disabled objects

       show    - show current objects and settings

       repair  - misc repair options
       test    - test settings

EOACTION
;
};




=head2 web

	$prov->web ($vals, $conf)

$vals is a hashref of values

	my $vals = { 
		'action'  => $ARGV[0],
		'debug'   => $opt_v,
	};

web will call several private methods, beginning with web_get_options which collects the details for the new account from the command line (via GetOpts) or via a HTTP form method. Once the options are gathered, it will perform the requested action (create, destroy, disable, enable, show, repair, or test) on the account.

=cut

sub web
{ 
	my ($self, $vals, $conf) = @_;
	print "web: begin..." if $vals->{'debug'};

	if ( $vals->{'debug'} ) {
		use Data::Dumper;
		print Dumper($self);
	};

	my $r;
	
	use Mail::Toaster::Apache 1.21;
	my $apache = Mail::Toaster::Apache->new();

	$vals = $self->web_get_options($vals, $conf);

	$vals->{'vhost'} ||=  $ARGV[1];  # set to command line if unset
	unless ($vals->{'vhost'}) {
		$self->web_usage();
		$utility->graceful_exit(400, "No web virtual host passed!");
	};

	$r = $self->web_check_setup($conf);
	unless ( $r->{'error_code'} == 200 ) { $utility->graceful_exit($r->{'error_code'}, $r->{'error_desc'}) };

	my $action = $vals->{'action'};

	if    ( $action eq "create"  ) { $r = $apache->vhost_create ($vals, $conf) }
	elsif ( $action eq "destroy" ) { $r = $apache->vhost_delete ($vals, $conf) }
	elsif ( $action eq "disable" ) { $r = $apache->vhost_disable($vals, $conf) }
	elsif ( $action eq "enable"  ) { $r = $apache->vhost_enable ($vals, $conf) }
	elsif ( $action eq "show"    ) { $r = $apache->vhost_show   ($vals, $conf) }
	elsif ( $action eq "repair"  ) { $utility->graceful_exit(400, "none yet\n")}
	elsif ( $action eq "test"    ) { $utility->graceful_exit(400, "none yet\n")}
	else {
		$self->web_usage();
		$utility->graceful_exit(400, "Invalid Action!");
	}

	print "web: end.\n" if $vals->{'debug'};
	$utility->graceful_exit($r->{'error_code'}, $r->{'error_desc'});
};


=head2 web_check_setup

Performs various tests on the apache config settings:

 make sure apache conf dir exists
 make sure vhost config is set up 

=cut

sub web_check_setup
{
	my ($self, $conf) = @_;

	my %r;

	# make sure apache etc dir exists
	my $dir = $conf->{'apache_dir_etc'};
	unless ( $dir && -d $dir ) {
		return { 'error_code' => 401,
			'error_desc' => 'web_check_setup: cannot find Apache\'s conf dir! Please set apache_dir_etc in sysadmin.conf.\n' };
	};

	# make sure apache vhost setting exists
	$dir = $conf->{'apache_dir_vhosts'};
	#unless ( $dir && (-d $dir || -f $dir) ) {  # can also be a fnmatch pattern!
	unless ( $dir ) {
		return { 'error_code' => 401,
			'error_desc' => 'web_check_setup: cannot find Apache\'s vhost file/dir! Please set apache_dir_vhosts in sysadmin.conf.\n' };
	};

	# all is well
	return { 'error_code' => 200,
		'error_desc' => 'web_check_setup: all tests pass!\n' };
};

=head2 web_usage

returns the following message if improper or missing arguments are passed:

	webadmin action -vhost [vhost name]

    required values:

       -vhost         

    optional values:

       -ip             - IP address to listen on (default *)
       -serveralias    - comma separated list of aliases
       -serveradmin    - email of server admin
       -documentroot   - path to html files
       -redirect       - url to redirect site to
       -options        - server options ex. FollowSymLinks MultiViews Indexes ExecCGI Includes
       -ssl            - ssl enabled ? 
       -sslcert        - path to ssl certificate
       -sslkey         - path to ssl key
       -cgi            - basic | advanced | custom
       -customlog      - custom logging directive
       -customerror    - custom error logging directive

       -awstats        - include alias for awstats
       -phpmyadmin     - include alias for php

=cut

sub web_usage()
{
	print <<EOWEBUSE

	$0 action -vhost [vhost name]

    required values:

       -vhost         

    optional values:

       -ip             - IP address to listen on (default *)
       -serveralias    - comma separated list of aliases
       -serveradmin    - email of server admin
       -documentroot   - path to html files
       -redirect       - url to redirect site to
       -options        - server options ex. FollowSymLinks MultiViews Indexes ExecCGI Includes
       -ssl            - ssl enabled ? 
       -sslcert        - path to ssl certificate
       -sslkey         - path to ssl key
       -cgi            - basic | advanced | custom
       -customlog      - custom logging directive
       -customerror    - custom error logging directive

       -awstats        - include alias for awstats
       -phpmyadmin     - include alias for phpMyAdmin
       

EOWEBUSE
;
};

=head2 web_get_options

Collects web account settings from the command line arguments or a HTML form.

=cut

sub web_get_options(;$$)
{
	my ($self, $vals, $conf) = @_;
	print "\nweb_get_options: begin..." if $vals->{'debug'};

	if ( $ENV{'GATEWAY_INTERFACE'} ) 
	{
		# get CGI form values
	}
	else 
	{
		# get command line options
		GetOptions (
			"vhost=s"       => \$vals->{'vhost'}, 
			"verbose"       => \$vals->{'debug'},
			"ip=s"          => \$vals->{'ip'},
			"serveralias=s" => \$vals->{'serveralias'},
			"serveradmin=s" => \$vals->{'serveradmin'},
			"documentroot=s"=> \$vals->{'documentroot'},
			"redirect=s"    => \$vals->{'redirect'},
			"options=s"     => \$vals->{'options'},
			"ssl"           => \$vals->{'ssl'},
			"sslcert=s"     => \$vals->{'sslcert'},
			"sslkey=s"      => \$vals->{'sslkey'},
			"cgi=s"         => \$vals->{'cgi'},
			"customlog=s"   => \$vals->{'customlog'},
			"customerror=s" => \$vals->{'customerror'},
			"awstats"       => \$vals->{'awstats'},
			"phpmyadmin"    => \$vals->{'phpmyadmin'},
		);
	};

	print "end.\n" if $vals->{'debug'};
	return $vals;
};


=head2 what_am_i_check

To simplify usage and increase the ability to secure access to various features, the program determines how it's being called. Currently, there are 4 options: 

  dnsadmin
  mailadmin
  useradmin
  webadmin

This simply checks to make sure a valid one has been invoked.

=cut

sub what_am_i_check
{
	my ($self, $iam) = @_;

    if    ( $iam eq "dnsadmin"  ) {  }
    elsif ( $iam eq "mailadmin" ) {  }
    elsif ( $iam eq "useradmin" ) {  }
    elsif ( $iam eq "webadmin"  ) {  }
    else {
		usage();
		return 0;
	};
	return 1;
};

sub what_am_i(;$)
{

=head2 what_am_i

	$prov->what_am_i($debug)

Determine what the filename of this program is.

=cut

	my ($self, $debug) = @_;

	print "what_am_i: $0 \n" if $debug;
	$0 =~ /([a-zA-Z0-9]*)$/;
	print "what_am_i: returning $1\n" if $debug;
	return $1;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@tnpi.biz>


=head1 BUGS

None known. Report any to author.


=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/


=head1 COPYRIGHT

Copyright (c) 2004-2005, The Network People, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

