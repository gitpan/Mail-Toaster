#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Provision.pm,v 4.7 2005/05/10 02:28:43 matt Exp $
#

package Mail::Toaster::Provision;

use vars qw($VERSION); $VERSION = '5.00';

use Carp;
use Getopt::Long;
use Params::Validate qw( :all );

use lib "lib";

use Mail::Toaster::Passwd  5; my $password = Mail::Toaster::Passwd->new;
use Mail::Toaster::Utility 5; my $utility = Mail::Toaster::Utility->new;


sub new {
	my ($class, $action) = @_;

	my $self = { action => $action };
	bless ($self, $class);
	return $self;
};

sub import {
	my ($self, @params) = @_;
#	print "Look, " . caller() . " is trying to import me!\n";
};

sub dns {

	my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'vals'    => { type=>HASHREF,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $vals, $fatal, $debug)
        = ( $p{'conf'}, $p{'vals'}, $p{'fatal'}, $p{'debug'} );

	print "dns.. begining.\n";

	print "dns....end.\n";
};

sub dns_usage {
	
	
};

sub mail {
    my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'vals'    => { type=>HASHREF,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $vals, $fatal, $debug)
        = ( $p{'conf'}, $p{'vals'}, $p{'fatal'}, $p{'debug'} );


};
sub mail_usage { };

sub quota_set {


	# Quota::setqlim($dev, $uid, $bs, $bh, $is, $ih, $tlo, $isgrp);
	# $dev     - filesystem mount or device
	# $bs, $is - soft limits for blocks and inodes
	# $bh, $ih - hard limits for blocks and inodes
	# $tlo     - time limits (0 = first user write, 1 = 7 days)
    # $isgrp   - 1 means that uid = gid, group limits set


	my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'   => { type=>HASHREF, optional=>1, },
            'user'   => { type=>SCALAR,  optional=>0, },
            'quota'  => { type=>SCALAR,  optional=>1, default=>100},
            'fatal'  => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'  => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $user, $quota, $fatal, $debug)
        = ( $p{'conf'}, $p{'user'}, $p{'quota'}, $p{'fatal'}, $p{'debug'} );

	require Quota;

	my $dev   = $conf->{'quota_filesystem'} || "/home";
	my $uid   = getpwnam($user);

	# set the soft limit a few megs higher than the hard limit
	my $quotabump = $quota + 5;

	print "quota_set: setting $quota MB quota for $user ($uid) on $dev\n" if $debug;

	# convert from megs to 1K blocks
	my $bh = $quota     * 1024;
	my $bs = $quotabump * 1024;

	my $is = $conf->{'quota_inodes_soft'} || 0;
	my $ih = $conf->{'quota_inodes_hard'} || 0;

	Quota::setqlim($dev, $uid, $bs, $bh, $is, $ih, 1, 0);

	print "user: end.\n" if $debug;

	# we should test the quota here and then return an appropriate result code
	return 1;
};

sub user {


	my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'vals'    => { type=>HASHREF,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $vals, $fatal, $debug)
        = ( $p{'conf'}, $p{'vals'}, $p{'fatal'}, $p{'debug'} );

	print "user: begin...\n" if $debug;

	my $r;

	# what are we going to do?

	my $user   = $vals->{'user'};
	my $action = $vals->{'action'};
	
	unless ($user) {
		$self->user_usage( { action=>$action, user=>$user } );
		$utility->graceful_exit(400, "No username passed!");
	};

	print "user: user is set.\n" if $debug;

	if ( $action eq "create" || $action eq "disable" || $action eq "enable" )
	{
		$utility->file_archive( file=>"/etc/master.passwd" );
#		$password->BackupMasterPasswd();
	};

	if    ( $action eq "create"  ) { 
		my $vals = $self->user_options( vals=>$vals, conf=>$conf );
		$r = $password->user_add($vals)
	}
	elsif ( $action eq "destroy" ) {
		$password->user_archive($user, $debug) if ( $conf->{'delete_user_archive'} );
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
			$self->quota_set(user=>$vals->{'user'}, quota=>$vals->{'quota'}, conf=>$conf) if $conf->{'quota_enable'};
		} 
		elsif ( $action eq "destroy" ) {
			$password->VerifyMasterPasswd("/etc/master.passwd", "shrink", $vals->{'debug'} );
		};
		return $r;
	}
	else
	{
		#$self->user_usage($vals);
		use Data::Dumper; print Dumper($r) if $vals->{'debug'};
		return $r;
	};

	print "user: end.\n" if $vals->{'debug'};
};

sub user_usage {


	my ($self, $vals) = @_;

	print <<EOUSER;

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

sub user_options {


	my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'vals'    => { type=>HASHREF,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $vals, $fatal, $debug)
        = ( $p{'conf'}, $p{'vals'}, $p{'fatal'}, $p{'debug'} );

	print "user_options: begin...\n" if $debug;

	if ( $ENV{'GATEWAY_INTERFACE'} ) 
	{
		# get CGI form values
		return 1;
	}

	my $user = $vals->{'user'};
	
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

	$user ||= $vals->{'user'} || $utility->answer(q=>'user');
	print "user: $vals->{'user'}\n";
	
	if ( $vals->{'action'} eq "create" ) {

		$vals->{'domain'}  ||= $utility->answer(q=>'domain');

		my $homedir = $vals->{'domain'}    || $vals->{'user'};
		my $home    = $conf->{'admin_home'}  || '/home';
		   $homedir = "$home/$homedir";
		my $shell   = $conf->{'shell_default'} || "/sbin/nologin";
		my $quota   = $conf->{'quota_default'} || '250';

		$vals->{'homedir'} ||= $utility->answer(q=>'homedir', default=>$homedir);
		$vals->{'shell'}   ||= $utility->answer(q=>'shell',   default=>$shell  );
		$vals->{'quota'}   ||= $utility->answer(q=>'quota',   default=>$quota  );
	}
	
	print "user_options: end.\n" if $debug;
	return $vals;
};

sub usage {


	print <<EOCHECK;

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

sub usage_action {


	print <<EOACTION;

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

sub web {


    my $self = shift;

	# parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'vals'    => { type=>HASHREF,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($conf, $vals, $fatal, $debug)
        = ( $p{'conf'}, $p{'vals'}, $p{'fatal'}, $p{'debug'} );


	print "web: begin..." if $vals->{'debug'};

	if ( $debug ) {
#		use Data::Dumper;
#		print Dumper($self);
	};

	my $r;
	
	require Mail::Toaster::Apache;
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

sub web_check_setup {


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

sub web_usage {


	print <<EOWEBUSE;

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

sub web_get_options {


	my ($self, $vals, $conf) = @_;
	print "\nweb_get_options: begin..." if $vals->{'debug'};

	if ( $ENV{'GATEWAY_INTERFACE'} ) 
	{
		# get CGI form values
		return;
	}

	my $vhost = $vals->{'vhost'};
	
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

	$vhost ||= $vals->{'vhost'} || $utility->answer(q=>'vhost');
	$vals->{'vhost'} = $vhost; print "vhost: $vhost\n";
	
	if ( $vals->{'action'} eq "create" ) {

		$vals->{'ip'}  ||= $utility->answer(q=>'ip', default=>'*' );
		$vals->{'serveralias'} ||= $utility->answer(q=>'serveralias', default=>"www.$vhost");
		
		my $htdocs = $conf->{'admin_home'} || "/home";
		my $docroot = "$htdocs/$vhost";
		$vals->{'documentroot'} ||= $utility->answer(q=>'documentroot', default=>$docroot);

		$vals->{'ssl'} ||= $utility->answer(q=>'ssl');
		if ( $vals->{'ssl'}) {
			my $certs = $conf->{'apache_dir_sslcerts'} || "/usr/local/etc/apache2/certs";
			
			$vals->{'sslcert'} ||= $utility->answer(q=>'sslcert', default=>"$certs/$vhost.crt" );
			$vals->{'sslkey'}  ||= $utility->answer(q=>'sslkey', default=>"$certs/$vhost.key" );
		}

		my $homedir = $vals->{'domain'}    || $vals->{'user'};
		my $home    = $conf->{'admin_home'}  || '/home';
		
		while (my ($key, $val) = each %$vals ) {
			next if $key eq "debug";
			next if $key eq "phpmyadmin";
			next if $key =~ /ssl/;
			next if $key =~ /custom/;
			next if $key eq "options";
			next if $key eq "verbose";
			next if $key eq "redirect";
			
			if ( ! defined $val ) {
				$utility->answer(q=>$key);
			}
		}
	};

	print "end.\n" if $vals->{'debug'};
	return $vals;
};

sub what_am_i_check {


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

sub what_am_i {


	my ($self, $debug) = @_;

	print "what_am_i: $0 \n" if $debug;
	$0 =~ /([a-zA-Z0-9]*)$/;
	print "what_am_i: returning $1\n" if $debug;
	return $1;
};


1;
__END__


=head1 NAME

Mail::Toaster::Provision


=head1 SYNOPSIS

Account provisioning methods.


=head1 DESCRIPTION

A suite of methods for provisioning various account types on unix like systems (Mac OS X, *BSD, Linux). Builds system accounts (/etc/passwd), web hosting accounts, mail hosting accounts, and DNS hosting accounts.


=head1 DEPENDENCIES

 Quota         (/usr/ports/sysutils/p5-Quota)


=head1 METHODS

=over 

=item new

To use the following methods, you must first create a provision object. Then invoke any of the methods that follow using your provision object.

  use Mail::Toaster::Provision;
  my $prov = Mail::Toaster::Provision->new();

  use Mail::Toaster::Utility;
  my $utility = Mail::Toaster::Utility->new();

  my $conf = $utility->parse_config( file=>"sysadmin.conf" );
  $prov->example_method( val=>$vals, conf=>$conf );

 arguments required:
    conf - a hashref of values pulled from sysadmin.conf. 


=item dns

dns will provision a DNS account using the programming API of a NicTool DNS server. 

it is not completed.


=item quota_set

Sets a user file system quota.

   $prov->quota_set( conf=>$conf, user=>"bob", quota=>200 );

quota is set in megabytes. A hard limit will be set 5 megs larger than the soft limit.

 Dependencies:
   Quota (the perl module)

 arguments required:
    user -  the system username to modify

 arguments optional:
    quota - (int) - the quota value in megabytes (100)



=item user

  $prov->user( action=>'add', conf=>$conf )

	'action'  => $ARGV[0],
	'debug'   => $opt_v,

user will call several private methods, beginning with user_get_options which collects the details for the new account from the command line (via GetOpts) or via a HTTP form method. Once the options are gathered, it will perform the requested action (create, destroy, disable, enable, show, repair, or test) on the account.

Due to ancient bugs corrupting FreeBSD's passwd files, user is very fault tolerant. It makes backup copies of the master.passwd files before altering them and tests to make sure the alterations it made are sane. If something is screwy, it saves a date stamped backup of the file. 

It also sets user quotas if quota is passed.

 arguments required:
    user -

 arguments optional:
    conf -

 result:


=item user_usage

returns the following message if improper or missing arguments are passed:

	useradmin action username

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



=item user_options

Collects the options required for setting up a user account from the command line (GetOpts) or from a HTTP form submission.

=cut


=item usage_action

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


=item web

	$prov->web (vals=>$vals, conf=>$conf)

$vals is a hashref of values

	my $vals = { 
		'action'  => $ARGV[0],
		'debug'   => $opt_v,
	};

web will call several private methods, beginning with web_get_options which collects the details for the new account from the command line (via GetOpts) or via a HTTP form method. Once the options are gathered, it will perform the requested action (create, destroy, disable, enable, show, repair, or test) on the account.


=item web_check_setup

Performs various tests on the apache config settings:

 make sure apache conf dir exists
 make sure vhost config is set up 


=item web_usage

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



=item web_get_options

Collects web account settings from the command line arguments or a HTML form.

=cut


=item what_am_i

	$prov->what_am_i($debug)

Determine what the filename of this program is.



=item what_am_i_check

To simplify usage and increase the ability to secure access to various features, the program determines how it's being called. Currently, there are 4 options: 

  dnsadmin
  mailadmin
  useradmin
  webadmin

This simply checks to make sure a valid one has been invoked.


=back


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

 http://mail-toaster.org/


=head1 COPYRIGHT

Copyright (c) 2004-2006, The Network People, Inc.  All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

