#!/usr/bin/perl
use strict;
use warnings;
#use diagnostics;
#
# $Id: Qmail.pm, matt Exp $
#

package Mail::Toaster::Qmail;
use base qw(Mail::Toaster);

use Carp;
use English qw( -no_match_vars );
use Params::Validate qw( :all );

use vars qw($VERSION $err);
$VERSION = '5.02';

use lib "lib";

require Mail::Toaster;          my $toaster = Mail::Toaster->new();
require Mail::Toaster::Utility; my $utility = Mail::Toaster::Utility->new();
require Mail::Toaster::Perl;    my $perl = Mail::Toaster::Perl->new();

1;

sub new {
    my $class = shift;
    $class = ref $class if ref $class;
    my $self = bless {}, $class;
    $self;
}

sub build_pop3_run {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'file'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $file, $fatal, $debug )
        = ( $p{'conf'}, $p{'file'}, $p{'fatal'}, $p{'debug'} );

    my $vdir       = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $qctrl      = $conf->{'qmail_dir'} . "/control";
    my $qsupervise = $conf->{'qmail_supervise'};

    if (
        !$self->_supervise_dir_exist(
            dir   => $qsupervise,
            name  => "build_pop3_run",
            debug => $debug
        )
      )
    {
        $utility->_formatted(
            "build_pop3_run: qmail_supervise ($qsupervise) does not exist!");
        die if $fatal;
        return;
    }

    my @lines =
      $toaster->supervised_do_not_edit_notice( conf => $conf, vdir => 1 );

    if ( $conf->{'pop3_hostname'} eq "qmail" ) {
        push @lines,
          $self->supervised_hostname_qmail(
            conf  => $conf,
            prot  => "pop3",
            debug => $debug,
          );
    }

    #exec softlimit -m 2000000 tcpserver -v -R -H -c50 0 pop3

    my $exec = $toaster->supervised_tcpserver(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug,
    );
    return unless $exec;

#qmail-popup mail.cadillac.net /usr/local/vpopmail/bin/vchkpw qmail-pop3d Maildir 2>&1

    $exec .= "qmail-popup ";
    $exec .= $toaster->supervised_hostname(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug,
    );
    
    my $chkpass = $self->_set_checkpasswd_bin(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug,
    );
    $chkpass ? $exec .= $chkpass : return;
    $exec .= "qmail-pop3d Maildir ";
    $exec .= $toaster->supervised_log_method(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug,
    );

    push @lines, $exec;

    return 1
      if (
        $utility->file_write(
            file  => $file,
            lines => \@lines,
            debug => $debug,
        )
      );
    carp "error writing file $file\n";
    return;
}

sub build_send_run {

    my $self = shift;
    my ($mem);

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'file'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $file, $fatal, $debug )
        = ( $p{'conf'}, $p{'file'}, $p{'fatal'}, $p{'debug'} );

    my @lines = $toaster->supervised_do_not_edit_notice( conf => $conf );

    my $qsupervise = $conf->{'qmail_supervise'};
    if ( !$qsupervise ) {
        $err = "build_send_run: WARNING: qmail_supervise not set in toaster-watcher.conf!\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    if ( !-d $qsupervise ) { $utility->mkdir_system( dir => $qsupervise, debug=>$debug ); }

    my $mailbox  = $conf->{'send_mailbox_string'} || "./Maildir/";
    my $send_log = $conf->{'send_log_method'}     || "syslog";

    if ( $send_log eq "syslog" ) {

        push @lines, "# This uses splogger to send logging through syslog";
        push @lines, "# Change this in /usr/local/etc/toaster-watcher.conf";
        push @lines, "exec qmail-start $mailbox splogger qmail";
    }
    else {
        push @lines,
          "# This sends the output to multilog as directed in log/run";
        push @lines, "# make changes in /usr/local/etc/toaster-watcher.conf";
        push @lines, "exec qmail-start $mailbox 2>&1";
    }
    push @lines, "\n";

    return 1
      if (
        $utility->file_write(
            file  => $file,
            lines => \@lines,
            debug => $debug,
            fatal => $fatal,
        )
      );
    print "error writing file $file\n";
    return;
}

sub build_smtp_run {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'file'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $file, $fatal, $debug )
        = ( $p{'conf'}, $p{'file'}, $p{'fatal'}, $p{'debug'} );

    $self->_test_smtpd_config_values(
        conf  => $conf,
        debug => $debug,
        fatal => $fatal,
    );

    my $mem;

    #use Data::Dumper; print Dumper($conf);
    my @smtp_run_cmd =
      $toaster->supervised_do_not_edit_notice( conf => $conf, vdir => 1 );

    push @smtp_run_cmd, $self->smtp_set_qmailqueue( conf => $conf, debug => $debug );

    # check for our control directory existence
    my $qdir  = $conf->{'qmail_dir'};
    my $qctrl = "$qdir/control";
    unless ( -d $qctrl ) {
        carp "WARNING: build_smtp_run failed. $qctrl is not a directory";
        return;
    }

    # check for the conf->qmail_supervise svscan directory
    return unless $self->svscan_dir_exists(
        conf  => $conf,
        name  => "build_smtp_run",
        debug => $debug,
        fatal => 0,
    );

    if ( $conf->{'smtpd_hostname'} eq "qmail" ) {
        push @smtp_run_cmd,
          $self->supervised_hostname_qmail(
            conf  => $conf,
            prot  => "smtpd",
            debug => $debug,
          );
    }

    # adds sh runtime checks for smtp
    push @smtp_run_cmd, $self->_smtp_sanity_tests( conf => $conf );

    my $exec = $toaster->supervised_tcpserver(
        conf  => $conf,
        prot  => "smtpd",
        debug => $debug,
        fatal => $fatal,
    );
    return unless $exec;

    $exec .= $self->smtp_set_rbls($conf, $debug);

    $exec .= "recordio " if $conf->{'smtpd_recordio'};
    $exec .= "fixcrio "  if $conf->{'smtpd_fixcrio'};
    $exec .= "qmail-smtpd ";

    $exec .= $self->smtp_auth_enable($conf,$debug);

    $exec .= $toaster->supervised_log_method(
        conf  => $conf,
        prot  => "smtpd",
        debug => $debug
    );

    push @smtp_run_cmd, $exec;

    if ( $utility->file_write(
            file  => $file,
            lines => \@smtp_run_cmd,
            debug => $debug,
            fatal => $fatal, )
      )
    {
        return 1;
    }

    carp "build_smtp_run: error writing file $file";
    return;
}

sub build_submit_run {

    my $self = shift;
    my ($mem);

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'file'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $file, $fatal, $debug )
        = ( $p{'conf'}, $p{'file'}, $p{'fatal'}, $p{'debug'} );

    if ( ! $self->_test_smtpd_config_values( conf => $conf, debug => $debug ) ) {
        $err = "SMTPd config values failed tests!\n";
        die $err if $fatal;
        carp $err;
        return;
    }

    my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

    my @lines =
      $toaster->supervised_do_not_edit_notice( conf => $conf, vdir => 1 );

    push @lines,
      $self->smtp_set_qmailqueue(
        conf  => $conf,
        prot  => 'submit',
        debug => $debug
      );

    my $qctrl = $conf->{'qmail_dir'} . "/control";
    unless ( -d $qctrl ) {
        carp "WARNING: build_submit_run failed. $qctrl is not a directory";
        return 0;
    }

    my $qsupervise = $conf->{'qmail_supervise'};
    return 0
      unless $self->_supervise_dir_exist(
        dir   => $qsupervise,
        name  => "build_submit_run",
        debug => $debug
      );

    if ($debug) {
        my $qsuper_submit = $conf->{'qmail_supervise_submit'}
          || "$qsupervise/submit";
        $qsuper_submit = "$qsupervise/$1"
          if ( $qsuper_submit =~ /^supervise\/(.*)$/ );

        print
          "build_submit_run: qmail-submit supervise dir is $qsuper_submit\n";
    }

    if ( $conf->{'submit_hostname'} eq "qmail" ) {
        push @lines,
          $self->supervised_hostname_qmail(
            conf  => $conf,
            prot  => "submit",
            debug => $debug
          );
    }
    push @lines, $self->_smtp_sanity_tests( conf => $conf );

    my $exec = $toaster->supervised_tcpserver(
        conf  => $conf,
        prot  => "submit",
        debug => $debug,
        fatal => $fatal,
    );
    return 0 unless $exec;

    $exec .= "qmail-smtpd ";

    if ( $conf->{'submit_auth_enable'} ) {
        if ( $conf->{'submit_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} ) {
            $exec .= $toaster->supervised_hostname(
                conf  => $conf,
                prot  => "submit",
                debug => $debug
            );
        }

        my $chkpass = $self->_set_checkpasswd_bin(
            conf  => $conf,
            prot  => "submit",
            debug => $debug
        );
        $chkpass ? $exec .= $chkpass : return;

        $exec .= "/usr/bin/true ";
    }

    $exec .= $toaster->supervised_log_method(
        conf  => $conf,
        prot  => "submit",
        debug => $debug
    );

    push @lines, $exec;

    return 1
      if (
        $utility->file_write(
            file  => $file,
            lines => \@lines,
            debug => $debug,
            fatal => $fatal,
        )
      );
    print "error writing file $file\n";
    return;
}

sub check_control {

    # used in qqtool.pl

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'dir'     => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $dir, $fatal, $debug )
        = ( $p{'dir'}, $p{'fatal'}, $p{'debug'} );

    if ( -d $dir ) {
        $utility->_formatted( "check_control: checking $dir", "ok" ) if $debug;
        return 1;
    }

    my $qcontrol = $self->service_dir_get( prot => "send", debug => $debug );

    if ($debug) {

        $utility->_formatted( "check_control: checking $qcontrol/$dir",
            "FAILED" );

        print "
	HEY! The control directory for qmail-send is not
	in $dir where I expected. Please edit this script
	and set $qcontrol to the appropriate directory!\n\n";

    }

    return;
}

sub check_rcpthosts {

    my ( $self, $qmaildir ) = @_;
    $qmaildir ||= "/var/qmail";

    if ( !-d $qmaildir ) {
        $utility->_formatted(
            "check_rcpthost: oops! the qmail directory does not exist!");
        return;
    }

    my $assign = "$qmaildir/users/assign";
    my $rcpt   = "$qmaildir/control/rcpthosts";
    my $mrcpt  = "$qmaildir/control/morercpthosts";

    # make sure an assign and rcpthosts file exists.
    unless ( -s $assign && -s $rcpt ) {
        $utility->_formatted("check_rcpthost: $assign or $rcpt is missing!");
        return;
    }

    my @domains = $self->get_domains_from_assign( assign => $assign );

    print "check_rcpthosts: checking your rcpthost files.\n.";
    my ( @f2, %rcpthosts, $domains, $count );

    # read in the contents of both rcpthosts files
    my @f1 = $utility->file_read( file => $rcpt );
    @f2 = $utility->file_read( file => $mrcpt )
      if ( -e "$qmaildir/control/morercpthosts" );

    # put their contents into a hash
    foreach ( @f1, @f2 ) { chomp $_; $rcpthosts{$_} = 1; }

    # and then for each domain in assign, make sure it is in rcpthosts
    foreach (@domains) {
        my $domain = $_->{'dom'};
        unless ( $rcpthosts{$domain} ) {
            print "\t$domain\n";
            $count++;
        }
        $domains++;
    }

    if ( ! $count || $count == 0 ) {
        print "Congrats, your rcpthosts is correct!\n";
        return 1;
    }

    if ( $domains > 50 ) {
        print
"\nDomains listed above should be added to $mrcpt. Don't forget to run 'qmail cdb' afterwards.\n";
    }
    else {
        print "\nDomains listed above should be added to $rcpt. \n";
    }
}

sub config {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'       => { type=>HASHREF, },
            'first_time' => { type=>BOOLEAN, optional=>1, default=>1 },
            'fatal'      => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'      => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'    => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $qmaildir = $conf->{'qmail_dir'}       || "/var/qmail";
    my $tmp      = $conf->{'toaster_tmp_dir'} || "/tmp";
    my $control  = "$qmaildir/control";
    my $host = $conf->{'toaster_hostname'};

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( !$host or $host eq "mail.example.com" ) {
        $host = $utility->answer( q => "the hostname for this mail server" );
    }

    if ( $host eq "qmail" or $host eq "system" ) {
        $host = `hostname`; chomp $host;
    }

    my $postmaster = $conf->{'toaster_admin_email'};
    $postmaster ||=
      $utility->answer(
        q => "the email address you use for administrator mail" );

    my $dbhost = $conf->{'vpopmail_mysql_repl_slave'}
      || $utility->answer(
        q => "the hostname for your database server (localhost)" ) || "localhost";

    my $dbport = $conf->{'vpopmail_mysql_repl_slave_port'}
          || $utility->answer(
                  q => "the port for your database server (3306)" ) || "3306";

    my $dbname = $conf->{'vpopmail_mysql_database'}
          || $utility->answer(
                  q => "the name of your database (vpopmail)" ) || "vpopmail";

    my $dbuser = $conf->{'vpopmail_mysql_repl_user'}
      || $utility->answer( q => "the SQL username for user vpopmail" ) || "vpopmail";

    my $password = $conf->{'vpopmail_mysql_repl_pass'}
      || $utility->answer( q => "the SQL password for user vpopmail" );

    my @changes = (
        { file => 'control/me',                 setting => $host, },
        { file => 'control/concurrencyremote',  setting => $conf->{'qmail_concurrencyremote'},},
        { file => 'control/mfcheck',            setting => $conf->{'qmail_mfcheck_enable'},   },
        { file => 'control/tarpitcount',        setting => $conf->{'qmail_tarpit_count'},     },
        { file => 'control/tarpitdelay',        setting => $conf->{'qmail_tarpit_delay'},     },
        { file => 'control/spfbehavior',        setting => $conf->{'qmail_spf_behavior'},     },
        { file => 'alias/.qmail-postmaster',    setting => $postmaster,   },
        { file => 'alias/.qmail-root',          setting => $postmaster,   },
        { file => 'alias/.qmail-mailer-daemon', setting => $postmaster,   },
    );

    if ( $conf->{'vpopmail_mysql'} ) {
        my $qmail_mysql = "server $dbhost\n" 
                        . "port $dbport\n" 
                        . "database $dbname\n"
                        . "table relay\n"
                        . "user $dbuser\n"
                        . "pass $password\n"
                        . "time 1800\n";

        push @changes, { 
            file    => 'control/sql', 
            setting => $qmail_mysql, 
        };
    };

    foreach my $change (@changes) {
        my $file = $change->{'file'};
        my $value = $change->{'setting'};

        $utility->file_write(
            file  => "$qmaildir/$file.tmp", 
            lines => [$value], 
            debug => $debug,
        );

        my $r = $utility->install_if_changed(
            newfile  => "$qmaildir/$file.tmp",
            existing => "$qmaildir/$file",
            clean    => 1,
            notify   => 1,
            debug    => 0
        );
        if ($r) {
            if ( $r == 1 ) { $r = "ok" }
            else { $r = "ok (same)" }
        }
        else { $r = "FAILED"; }
        if ( $debug ) {
            $utility->_formatted( "config: setting $file to $value", $r )
                unless ( $value =~ /pass/ );
        };
    };

    my $uid = getpwnam("vpopmail");
    my $gid = getgrnam("vchkpw");

    chown( $uid, $gid, "$control/servercert.pem" );
    chown( $uid, $gid, "$control/sql" );
    chmod oct('0640'), "$control/servercert.pem";
    chmod oct('0640'), "$control/clientcert.pem";
    chmod oct('0640'), "$control/sql";
    chmod oct('0644'), "$control/concurrencyremote";

    unless ( -e "$control/locals" ) {
        $utility->file_write( file => "$control/locals", lines => ["\n"], debug=>$debug );
        $utility->_formatted( "config: touching $control/locals", "ok" )
          if $debug;
    }

    my $manpath = "/etc/manpath.config";
    if ( -e $manpath ) {
        unless (`grep "/var/qmail/man" $manpath | grep -v grep`) {
            $utility->file_write(
                file   => $manpath,
                lines  => ["OPTIONAL_MANPATH\t\t/var/qmail/man"],
                append => 1, 
                debug  => $debug,
            );
            $utility->_formatted( "config: appending /var/qmail/man to MANPATH",
                "ok" )
              if $debug;
        }
    }

    return 1 unless ( $OSNAME eq "freebsd" );

    # disable sendmail
    require Mail::Toaster::FreeBSD;
    my $freebsd  = Mail::Toaster::FreeBSD->new;
    my $sendmail = `grep sendmail_enable /etc/rc.conf`;

    $freebsd->rc_dot_conf_check( 
        check=>"sendmail_enable", 
        line=>'sendmail_enable="NONE"', 
        debug=>$debug,
      ) unless $sendmail;

    # if sendmail is set to anything except NONE 
    unless ( $sendmail && $sendmail =~ /NONE/ ) {
        my @lines = $utility->file_read( file => "/etc/rc.conf", debug=>$debug );
        foreach (@lines) {
            if ( $_ =~ /^sendmail_enable/ ) { $_ = 'sendmail_enable="NONE"'; }
        }
        $utility->file_write( 
            file   => "/etc/rc.conf", 
            lines  => \@lines, 
            debug  => $debug 
        );
    }

    # don't install sendmail when we rebuild the world
    if ( ! `grep NO_SENDMAIL /etc/make.conf` ) {
        $utility->file_write(
            file   => "/etc/make.conf",
            lines  => ["NO_SENDMAIL=true"],
            append => 1,
            debug  => $debug,
        );
    }

    # make sure mailer.conf is set up for qmail
    my $tmp_mailer_conf = "$tmp/mailer.conf";
    open my $MAILER_CONF, ">", $tmp_mailer_conf 
        or carp "control_write: FAILED to open $tmp_mailer_conf: $!\n";

    print $MAILER_CONF '
# \$FreeBSD: src/etc/mail/mailer.conf,v 1.3 2002/04/05 04:25:12 gshapiro Exp \$
#
sendmail        /var/qmail/bin/sendmail
send-mail       /var/qmail/bin/sendmail
mailq           /usr/local/sbin/maillogs yesterday
#mailq          /var/qmail/bin/qmail-qread
newaliases      /var/qmail/bin/newaliases
hoststat        /var/qmail/bin/qmail-tcpto
purgestat       /var/qmail/bin/qmail-tcpok
#
# Execute the "real" sendmail program, named /usr/libexec/sendmail/sendmail
#
#sendmail        /usr/libexec/sendmail/sendmail
#send-mail       /usr/libexec/sendmail/sendmail
#mailq           /usr/libexec/sendmail/sendmail
#newaliases      /usr/libexec/sendmail/sendmail
#hoststat        /usr/libexec/sendmail/sendmail
#purgestat       /usr/libexec/sendmail/sendmail

';

    $utility->install_if_changed(
        newfile  => $tmp_mailer_conf,
        existing => "/etc/mail/mailer.conf",
        notify   => 1,
        clean    => 1,
        debug    => $debug,
    );
    close $MAILER_CONF;

    # no need to run the rest of the tests every 5 minutes
    return 1 if ! $p{'first_time'};

    # install the qmail control script (qmail cdb, qmail restart, etc)
    $self->control_create(conf=>$conf, debug=>$debug);

    # create all the service and supervised dirs
    $toaster->service_dir_create( conf => $conf, debug => $debug );
    $toaster->supervise_dirs_create( conf => $conf, debug => $debug );

    # install the supervised control files
    $self->install_qmail_control_files( conf => $conf, debug => $debug );
    $self->install_qmail_control_log_files( conf => $conf, debug => $debug );
}

sub control_create {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $dl_site = $conf->{'toaster_dl_site'} || "http://www.tnpi.biz";
    my $dl_url  = $conf->{'toaster_dl_url'}  || "/internet/mail/toaster";
    my $toaster_url = "$dl_site$dl_url";

    my $qmaildir = $conf->{'qmail_dir'}         || "/var/qmail";
    my $confdir  = $conf->{'system_config_dir'} || "/usr/local/etc";
    my $tmp      = $conf->{'toaster_tmp_dir'}   || "/tmp";
    my $prefix   = $conf->{'toaster_prefix'}    || "/usr/local";

    my $qmailctl = "$qmaildir/bin/qmailctl";

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # install a new qmailcontrol if newer than existing one.
    $self->control_write( $conf, "$tmp/qmailctl", $debug );
    my $r = $utility->install_if_changed(
        newfile  => "$tmp/qmailctl",
        existing => $qmailctl,
        mode     => '0755',
        notify   => 1,
        clean    => 1,
        debug    => $debug,
    );

    if ($r) {
        if ( $r == 1 ) { $r = "ok" }
        else { $r = "ok (same)" }
    }
    else { $r = "FAILED"; }
    $utility->_formatted( "control_create: installing $qmaildir/bin/qmailctl", $r ) if $debug;
    $utility->syscmd( command => "$qmailctl cdb", debug=>0 );

    # create aliases in the common locations
    foreach my $qmailctl ( "$prefix/sbin/qmail", "$prefix/sbin/qmailctl" ) {
        next if -l $qmailctl;
        if ( -e $qmailctl ) {
            unless ( -l $qmailctl ) {
                print "updating $qmailctl.\n" if $debug;
                unlink($qmailctl);
                symlink( "$qmaildir/bin/qmailctl", $qmailctl );
            }
        }
        else {
            print "control_create: adding symlink $qmailctl\n" if $debug;
            symlink( "$qmaildir/bin/qmailctl", $qmailctl )
              or carp "couldn't link $qmailctl: $!";
        }
    }

    if ( -e "$qmaildir/rc" ) {
        print "control_create: $qmaildir/rc already exists.\n" if $debug;
    }
    else {
        print "control_create: creating $qmaildir/rc.\n" if $debug;
        my $file = "/tmp/toaster-watcher-send-runfile";
        if ( $self->build_send_run( conf => $conf, file => $file ) ) {
            $self->install_supervise_run(
                tmpfile     => $file,
                destination => "$qmaildir/rc",
                debug       => $debug,
            );
            print "success.\n";
        }
        else { print "FAILED.\n" }
    }

    # the FreeBSD port installs this but we won't be using it
    if ( -e "$confdir/rc.d/qmail.sh" ) {
        unlink("$confdir/rc.d/qmail.sh")
          or croak "couldn't delete $confdir/rc.d/qmail.sh: $!";
        print "control_create: removing $confdir/rc.d/qmail.sh\n";
    }
}

sub control_write {

    my $self = shift;

    my ($conf, $file, $debug) = validate_pos(@_, HASHREF, SCALAR, {type=>SCALAR, optional=>1,default=>1} );

    my $FILE_HANDLE;
    unless ( open $FILE_HANDLE, ">", $file ) {
        carp "control_write: FAILED to open $file: $!\n";
        return;
    }

    my $qdir   = $conf->{'qmail_dir'}      || "/var/qmail";
    my $prefix = $conf->{'toaster_prefix'} || "/usr/local";
    my $tcprules = $utility->find_the_bin( bin => "tcprules", debug=>$debug );
    my $svc      = $utility->find_the_bin( bin => "svc", debug=>$debug );

    unless ( -x $tcprules && -x $svc ) {
        carp "control_write: FAILED to find tcprules or svc.\n";
        return;
    }

    print $FILE_HANDLE <<EOQMAILCTL;
#!/bin/sh

PATH=$qdir/bin:$prefix/bin:/usr/bin:/bin
export PATH

case "\$1" in
	stat)
		cd $qdir/supervise
		svstat * */log
	;;
	doqueue|alrm|flush)
		echo "Sending ALRM signal to qmail-send."
		$svc -a $qdir/supervise/send
	;;
	queue)
		qmail-qstat
		qmail-qread
	;;
	reload|hup)
		echo "Sending HUP signal to qmail-send."
		$svc -h $qdir/supervise/send
	;;
	pause)
		echo "Pausing qmail-send"
		$svc -p $qdir/supervise/send
		echo "Pausing qmail-smtpd"
		$svc -p $qdir/supervise/smtp
	;;
	cont)
		echo "Continuing qmail-send"
		$svc -c $qdir/supervise/send
		echo "Continuing qmail-smtpd"
		$svc -c $qdir/supervise/smtp
	;;
	restart)
		echo "Restarting qmail:"
		echo "* Stopping qmail-smtpd."
		$svc -d $qdir/supervise/smtp
		echo "* Sending qmail-send SIGTERM and restarting."
		$svc -t $qdir/supervise/send
		echo "* Restarting qmail-smtpd."
		$svc -u $qdir/supervise/smtp
	;;
	cdb)
		if [ -s ~vpopmail/etc/tcp.smtp ]
		then
			$tcprules ~vpopmail/etc/tcp.smtp.cdb ~vpopmail/etc/tcp.smtp.tmp < ~vpopmail/etc/tcp.smtp
			chmod 644 ~vpopmail/etc/tcp.smtp*
			echo "Reloaded ~vpopmail/etc/tcp.smtp."
		fi 
                
		if [ -s /etc/tcp.smtp ]
		then
			$tcprules /etc/tcp.smtp.cdb /etc/tcp.smtp.tmp < /etc/tcp.smtp
			chmod 644 /etc/tcp.smtp*
			echo "Reloaded /etc/tcp.smtp."
		fi

		if [ -s $qdir/control/simcontrol ]
		then
			if [ -x $qdir/bin/simscanmk ]
			then
				$qdir/bin/simscanmk
				echo "Reloaded $qdir/control/simcontrol."
				$qdir/bin/simscanmk -g
				echo "Reloaded $qdir/control/simversions."
			fi
		fi

		if [ -s $qdir/users/assign ]
		then
			if [ -x $qdir/bin/qmail-newu ]
			then
				echo "Reloaded $qdir/users/assign."
			fi
		fi

		if [ -s $qdir/control/morercpthosts ]
		then
			if [ -x $qdir/bin/qmail-newmrh ]
			then
				$qdir/bin/qmail-newmrh
				echo "Reloaded $qdir/control/morercpthosts"
			fi
		fi

		if [ -s $qdir/control/spamt ]
		then
			if [ -x $qdir/bin/qmail-newst ]
			then
				$qdir/bin/qmail-newst
				echo "Reloaded $qdir/control/spamt"
			fi
		fi
	;;
	help)
		cat <<HELP
		pause -- temporarily stops mail service (connections accepted, nothing leaves)
		cont -- continues paused mail service
		stat -- displays status of mail service
		cdb -- rebuild the cdb files (tcp.smtp, users, simcontrol)
		restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
		doqueue -- sends qmail-send ALRM, scheduling queued messages for delivery
		reload -- sends qmail-send HUP, rereading locals and virtualdomains
		queue -- shows status of queue
		alrm -- same as doqueue
		hup -- same as reload
HELP
	;;
	*)
		echo "Usage: \$0 {restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}"
		exit 1
	;;
esac

exit 0

EOQMAILCTL

    close $FILE_HANDLE;
}

sub get_domains_from_assign {

    my $self = shift;

    # parameter validation
    my %p = validate ( @_, {
            'assign'  => { type=>SCALAR,  optional=>1, default=>'/var/qmail/users/assign'},
            'match'   => { type=>SCALAR,  optional=>1, },
            'value'   => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $assign, $match, $value, $fatal, $debug ) 
        = ( $p{'assign'}, $p{'match'}, $p{'value'}, $p{'fatal'}, $p{'debug'} );

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( ! -s $assign ) {
        $err = "get_domains_from_assign: the file $assign is missing or empty!\n";
        croak $err if $fatal;
        carp $err if $debug;
        return;
    }

    my @domains;
    my @lines = $utility->file_read( file => $assign, debug=>$debug );
    print "Parsing through the file $assign..." if $debug;

    foreach my $line (@lines) {
        chomp $line;
        my @fields = split( ":", $line );
        if ( $fields[0] ne "" && $fields[0] ne "." ) {
            my %domain = (
                stat => $fields[0],
                dom  => $fields[1],
                uid  => $fields[2],
                gid  => $fields[3],
                dir  => $fields[4],
            );

            if (! $match) { push @domains, \%domain; }
            else {
                if ( $match eq "dom" && $value eq "$fields[1]" ) {
                    push @domains, \%domain;
                }
                elsif ( $match eq "uid" && $value eq "$fields[2]" ) {
                    push @domains, \%domain;
                }
                elsif ( $match eq "dir" && $value eq "$fields[4]" ) {
                    push @domains, \%domain;
                }
            }
        }
    }
    print "done.\n\n" if $debug;
    return @domains;
}

sub get_list_of_rbls {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'   => HASHREF,
            'fatal'  => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'  => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    # two arrays, one for sorted elements, one for unsorted
    my ( @sorted, @unsorted );
    my ( @list,   %sort_keys, $sort );

    foreach my $key ( keys %$conf ) {

        #print "checking $key \n" if $debug;

        # discard everything that doesn't start wih rbl
        next unless ( $key =~ /^rbl/ );

        # ignore other similar keys in $conf
        next if ( $key =~ /^rbl_enable/ );
        next if ( $key =~ /^rbl_reverse_dns/ );
        next if ( $key =~ /^rbl_timeout/ );
        next if ( $key =~ /_message$/ );

        # discard if it is not enabled
        next unless ( $conf->{$key} > 0 );

        $key =~ /^rbl_([a-zA-Z\.\-]*)\s*$/;

        #$key =~ /^rbl_([a-zA-Z_\.\-]*)\s*$/;

        print "good key: $1 " if $debug;

        # test for custom sort key
        if ( $conf->{$key} > 1 ) {

            print "\t  sorted value $conf->{$key}\n" if $debug;
            @sorted[ $conf->{$key} - 2 ] = $1;
        }
        else {
            print "\t  unsorted\n" if $debug;
            push @unsorted, $1;
        }
    }

    # add the unsorted values to the sorted list
    push @sorted, @unsorted;

    if ( $debug ) {
        print "\nsorted order:\n\t" . join( "\n\t", @sorted ) . "\n";
    };

    # test each RBL in the list
    my $good_rbls = $self->test_each_rbl(
        conf  => $conf,
        rbls  => \@sorted,
        debug => $debug,
        fatal => $fatal,
    );

    return q{} unless $good_rbls;

    # format them for use in a supervised (daemontools) run file
    my $string_of_rbls;
    foreach (@$good_rbls) {
        my $mess = $conf->{"rbl_${_}_message"};
        if ( defined $mess && $mess ) {
            print "adding $_:'$mess'\n" if $debug;
            $string_of_rbls .= "-r $_:'$mess' ";
        }
        else {
            print "adding $_ \n" if $debug;
            $string_of_rbls .= "-r $_ ";
        }
    }

    return $string_of_rbls;
}

sub get_list_of_rwls {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my @list;

    foreach my $key ( keys %$conf ) {

        next unless ( $key =~ /^rwl/ && $conf->{$key} == 1 );
        next if ( $key =~ /^rwl_enable/ );

        $key =~ /^rwl_([a-zA-Z_\.\-]*)\s*$/;

        print "good key: $1 \n" if $debug;
        push @list, $1;
    }
    return \@list;
}

sub get_qmailscanner_virus_sender_ips {

    # deprecated function

    my ( $self, $conf ) = @_;
    my @ips;

    my $debug      = $conf->{'debug'};
    my $block      = $conf->{'qs_block_virus_senders'};
    my $clean      = $conf->{'qs_quarantine_clean'};
    my $quarantine = $conf->{'qs_quarantine_dir'};

    unless ( -d $quarantine ) {
        $quarantine = "/var/spool/qmailscan/quarantine"
          if ( -d "/var/spool/qmailscan/quarantine" );
    }

    unless ( -d "$quarantine/new" ) {
        carp "no quarantine dir!";
        return;
    }

    my @files = $utility->get_dir_files( dir => "$quarantine/new" );

    foreach my $file (@files) {
        if ($block) {
            my $ipline = `head -n 10 $file | grep HELO`;
            chomp $ipline;

            next unless ($ipline);
            print " $ipline  - " if $debug;

            my @lines = split( /Received/, $ipline );
            foreach my $line (@lines) {
                print $line if $debug;

                # Received: from unknown (HELO netbible.org) (202.54.63.141)
                my ($ip) = $line =~ /([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/;

                # we need to check the message and verify that it's
                # a virus that was blocked, not an admin testing
                # (Matt 4/3/2004)

                if ( $ip =~ /\s+/ or !$ip ) { print "$line\n" if $debug; }
                else { push @ips, $ip; }
                print "\t$ip" if $debug;
            }
            print "\n" if $debug;
        }
        unlink $file if $clean;
    }

    my ( %hash, @sorted );
    foreach (@ips) { $hash{$_} = "1"; }
    foreach ( keys %hash ) { push @sorted, $_; delete $hash{$_} }
    return @sorted;
}

sub install_qmail {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'package' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $package, $fatal, $debug )
        = ( $p{'conf'}, $p{'package'}, $p{'fatal'}, $p{'debug'} );

    my ( $patch, $chkusr );

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # redirect if netqmail is selected
    if ( $conf->{'install_netqmail'} ) {
        return $self->netqmail(conf=>$conf, debug=>$debug );
    }

    my $ver = $conf->{'install_qmail'};

    if ( !$ver ) {
        print "install_qmail: installation disabled in .conf, SKIPPING"
          if $debug;
        return;
    }

    $self->install_qmail_groups_users( conf => $conf, debug=>$debug );

    $package ||= "qmail-$ver";

    my $src      = $conf->{'toaster_src_dir'}   || "/usr/local/src";
    my $qmaildir = $conf->{'qmail_dir'}         || "/var/qmail";
    my $vpopdir  = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $mysql = $conf->{'qmail_mysql_include'}
      || "/usr/local/lib/mysql/libmysqlclient.a";
    my $dl_site = $conf->{'toaster_dl_site'} || "http://www.tnpi.biz";
    my $dl_url  = $conf->{'toaster_dl_url'}  || "/internet/mail/toaster";
    my $toaster_url = "$dl_site$dl_url";

    $utility->chdir_source_dir( dir => "$src/mail", debug=>$debug );

    if ( -e $package ) {
        unless ( $utility->source_warning( package=>$package, src=>$src ) ) {
            carp "install_qmail: FATAL: sorry, I can't continue.\n";
            return;
        }
    }

    unless ( defined $conf->{'qmail_chk_usr_patch'} ) {
        print "\nCheckUser support causes the qmail-smtpd daemon to verify that
a user exists locally before accepting the message, during the SMTP conversation.
This prevents your mail server from accepting messages to email addresses that
don't exist in vpopmail. It is not compatible with system user mailboxes. \n\n";

        $chkusr =
          $utility->yes_or_no(
            question => "Do you want qmail-smtpd-chkusr support enabled?" );
    }
    else {
        if ( $conf->{'qmail_chk_usr_patch'} ) {
            $chkusr = 1;
            print "chk-usr patch: yes\n";
        }
    }

    if ($chkusr) { $patch = "$package-toaster-2.8.patch"; }
    else { $patch = "$package-toaster-2.6.patch"; }

    my $site = "http://cr.yp.to/software";

    unless ( -e "$package.tar.gz" ) {
        if ( -e "/usr/ports/distfiles/$package.tar.gz" ) {
            use File::Copy;
            copy( "/usr/ports/distfiles/$package.tar.gz",
                "$src/mail/$package.tar.gz" );
        }
        else {
            $utility->file_get( url => "$site/$package.tar.gz" );
            unless ( -e "$package.tar.gz" ) {
                croak "install_qmail FAILED: couldn't fetch $package.tar.gz!\n";
            }
        }
    }

    unless ( -e $patch ) {
        $utility->file_get( url => "$toaster_url/patches/$patch", debug=>$debug );
        unless ( -e $patch ) { croak "\n\nfailed to fetch patch $patch!\n\n"; }
    }

    my $tar      = $utility->find_the_bin( bin => "tar", debug=>$debug );
    my $patchbin = $utility->find_the_bin( bin => "patch", debug=>$debug );
    unless ( $tar && $patchbin ) { croak "couldn't find tar or patch!\n"; }

    $utility->syscmd( command => "$tar -xzf $package.tar.gz", debug=>$debug );
    chdir("$src/mail/$package")
      or croak "install_qmail: cd $src/mail/$package failed: $!\n";
    $utility->syscmd( command => "$patchbin < $src/mail/$patch", debug=>$debug );

    $utility->file_write( file => "conf-qmail", lines => [$qmaildir], debug=>$debug )
      or croak "couldn't write to conf-qmail: $!";

    $utility->file_write( file => "conf-vpopmail", lines => [$vpopdir], debug=>$debug )
      or croak "couldn't write to conf-vpopmail: $!";

    $utility->file_write( file => "conf-mysql", lines => [$mysql], debug=>$debug )
      or croak "couldn't write to conf-mysql: $!";

    my $servicectl = "/usr/local/sbin/services";

    if ( -x $servicectl ) {

        print "Stopping Qmail!\n";
        $utility->syscmd( command => "$servicectl stop", debug=>$debug );
        $self->send_stop( conf => $conf );
    }

    $utility->syscmd( command => "make setup", debug=>$debug );

    unless ( -f "$qmaildir/control/servercert.pem" ) {
        $utility->syscmd( command => "gmake cert", debug=>$debug );
    }

    if ($chkusr) {
        $utility->file_chown(
            file => "$qmaildir/bin/qmail-smtpd",
            uid  => 'vpopmail',
            gid  => 'vchkpw', 
            debug=> $debug,
        );

        $utility->file_chmod(
            file  => "$qmaildir/bin/qmail-smtpd",
            mode  => '6555',
            debug => $debug,
        );
    }

    unless ( -e "/usr/share/skel/Maildir" ) {

# deprecated, not necessary unless using system accounts
# $utility->syscmd( command=>"$qmaildir/bin/maildirmake /usr/share/skel/Maildir" );
    }

    $self->config( conf => $conf, debug => $debug );

    if ( -x $servicectl ) {
        print "Starting Qmail & supervised services!\n";
        $utility->syscmd( command => "$servicectl start", debug=>$debug );
    }
}

sub install_qmail_control_files {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    PROT: 
    foreach my $prot (qw/ pop3 send smtp submit /) {
        my $supervisedir = $self->supervise_dir_get(
            conf  => $conf,
            prot  => $prot,
            debug => $debug
        );
        my $run_f = "$supervisedir/run";

        if ( -e $run_f ) {
            print "install_qmail_control_files: $run_f already exists!\n" if $debug;
            next PROT;
        }

        my $file = "/tmp/toaster-watcher-$prot-runfile";

        if ( $prot eq "smtp" ) {

            #$file = "/tmp/toaster-watcher-smtpd-runfile";
            if (
                $self->build_smtp_run(
                    conf  => $conf,
                    file  => $file,
                    debug => $debug,
                )
              )
            {
                print "install_qmail_control_files: installing $run_f\n"
                  if $debug;
                $self->install_supervise_run(
                    tmpfile     => $file,
                    destination => $run_f,
                    debug       => $debug,
                    fatal       => $fatal,
                );
            }
        }
        elsif ( $prot eq "send" ) {
            if (
                $self->build_send_run(
                    conf  => $conf,
                    file  => $file,
                    debug => $debug,
                )
              )
            {
                print "install_qmail_control_files: installing $run_f\n"
                  if $debug;
                $self->install_supervise_run(
                    tmpfile     => $file,
                    destination => $run_f,
                    debug       => $debug,
                    fatal       => $fatal,
                );
            }
        }
        elsif ( $prot eq "pop3" ) {
            if (
                $self->build_pop3_run(
                    conf  => $conf,
                    file  => $file,
                    debug => $debug,
                )
              )
            {
                print "install_qmail_control_files: installing $run_f\n"
                  if $debug;
                $self->install_supervise_run(
                    tmpfile     => $file,
                    destination => $run_f,
                    debug       => $debug,
                    fatal       => $fatal,
                );
            }
        }
        elsif ( $prot eq "submit" ) {
            if (
                $self->build_submit_run(
                    conf  => $conf,
                    file  => $file,
                    debug => $debug,
                )
              )
            {
                print "install_qmail_control_files: installing $run_f\n"
                  if $debug;
                $self->install_supervise_run(
                    tmpfile     => $file,
                    destination => $run_f,
                    debug       => $debug,
                    fatal       => $fatal,
                );
            }
        }
    }
}

sub install_qmail_groups_users {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    $err = "ERROR: You need to update your toaster-watcher.conf file!\n";

    my $qmaildir = $conf->{'qmail_dir'}         || croak $err;
    my $alias    = $conf->{'qmail_user_alias'}  || croak "$err (alias)";
    my $qmaild   = $conf->{'qmail_user_daemon'} || croak "$err (qmaild)";
    my $qmailp   = $conf->{'qmail_user_passwd'} || croak "$err (qmailp)";
    my $qmailq   = $conf->{'qmail_user_queue'}  || croak "$err (qmailq)";
    my $qmailr   = $conf->{'qmail_user_remote'} || croak "$err (qmailr)";
    my $qmails   = $conf->{'qmail_user_send'}   || croak "$err (qmails)";
    my $qmaill   = $conf->{'qmail_user_log'}    || croak "$err (qmaill)";
    my $qmailg   = $conf->{'qmail_group'}       || croak "$err (qmailg)";
    my $nofiles  = $conf->{'qmail_log_group'}   || croak "$err (nofiles)";

    require Mail::Toaster::Passwd;
    my $passwd = Mail::Toaster::Passwd->new;

    my $uid = 81;
    my $gid = 81;

    if ( $OSNAME eq "darwin" ) {
        $uid = 200;
        $gid = 200;
    }

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    $passwd->creategroup( group => "qnofiles", gid => $gid, debug => $debug );
    $passwd->creategroup( group => "qmail", gid => $gid + 1, debug => $debug );

    unless ( $passwd->exist($alias) ) {
        $passwd->user_add(
            { user => $alias, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;

    unless ( $passwd->exist($qmaild) ) {
        $passwd->user_add(
            { user => $qmaild, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;

    unless ( $passwd->exist($qmaill) ) {
        $passwd->user_add(
            { user => $qmaill, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;

    unless ( $passwd->exist($qmailp) ) {
        $passwd->user_add(
            { user => $qmailp, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;
    $gid++;

    unless ( $passwd->exist($qmailq) ) {
        $passwd->user_add(
            { user => $qmailq, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;

    unless ( $passwd->exist($qmailr) ) {
        $passwd->user_add(
            { user => $qmailr, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
    $uid++;

    unless ( $passwd->exist($qmails) ) {
        $passwd->user_add(
            { user => $qmails, homedir => $qmaildir, uid => $uid, gid => $gid }
        );
    }
}

sub install_supervise_run {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'        => { type=>HASHREF, optional=>1, },
            'tmpfile'     => { type=>SCALAR,  },
            'destination' => { type=>SCALAR,  optional=>1, },
            'prot'        => { type=>SCALAR,  optional=>1, },
            'fatal'       => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'       => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok'     => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $tmpfile, $destination, $prot, $fatal, $debug )
        = ( $p{'conf'}, $p{'tmpfile'}, $p{'destination'}, $p{'prot'}, 
            $p{'fatal'}, $p{'debug'} );

    # we do not want to try changing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # if destination is not set, try to figure out where
    if ( !$destination ) {
        if ( !$prot ) {
            $err =
              "install_supervise_run: you didn't set destination or prot!\n";
            croak $err if $fatal;
            carp $err;
            return;
        }

        my $dir = $self->supervise_dir_get( conf => $conf, prot => $prot, debug=>$debug );
        if ( !$dir ) {
            $err = "Yikes, supervise_dir_get did not give me anything good!\n";
            croak $err if $fatal;
            carp $err;
            return;
        }
        $destination = "$dir/run";
    }

    unless ( -e $tmpfile ) {
        carp "ERROR: the file to install ($tmpfile) is missing!\n";
        return;
    }

    unless ( chmod oct('0755'), $tmpfile ) {
        carp "ERROR: couldn't chmod $tmpfile: $!\n";
        return;
    }

    if ($debug) {
        if ( -e $destination ) {
            print "install_supervise_run: updating $destination\n";
        }
        else { print "install_supervise_run: installing $destination\n" }
    }

    my $notify = $conf->{'supervise_rebuild_notice'} || 1;
    my $email = $conf->{'toaster_admin_email'} || 'postmaster';
    
    my $r = (
        $utility->install_if_changed(
            newfile  => $tmpfile,
            existing => $destination,
            mode     => '0755',
            notify   => 1,
            email    => $email,
            clean    => 1,
            debug    => $debug,
            fatal    => $fatal,
        )
    );

    print "done\n" if $debug;

    return $r;
}

sub install_qmail_control_log_files {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'prots'   => { type=>ARRAYREF,optional=>1, default=>["smtp", "send", "pop3", "submit"] },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $prots, $fatal, $debug )
        = ( $p{'conf'}, $p{'prots'}, $p{'fatal'}, $p{'debug'} );

    my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    my %valid_prots = (
        "smtp"   => 1, 
        "send"   => 1,
        "pop3"   => 1, 
        "submit" => 1,
    );

    # we do not want to try doing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # Create log/run files
    foreach my $serv (@$prots) {

        unless ( $valid_prots{$serv} ) {
            croak "invalid protocol: $serv!\n";
        };

        my $supervisedir =
          $self->supervise_dir_get( conf => $conf, prot => $serv );
        my $run_f = "$supervisedir/log/run";

        $utility->_formatted(
            "install_qmail_control_log_files: preparing $run_f")
          if $debug;

        my @lines = $toaster->supervised_do_not_edit_notice( conf => $conf );

        push @lines, $toaster->supervised_multilog( conf=>$conf, prot=>$serv, debug=>$debug );

        my $tmpfile = "/tmp/mt_supervise_" . $serv . "_log_run";
        $utility->file_write( file => $tmpfile, lines => \@lines );

        $utility->_formatted(
            "install_qmail_control_log_files: comparing $run_f")
          if $debug;

        my $notify = $conf->{'supervise_rebuild_notice'} || 1;

        if ( -s $tmpfile ) {
            return 0
              unless (
                $utility->install_if_changed(
                    newfile  => $tmpfile,
                    existing => $run_f,
                    mode     => '0755',
                    notify   => $notify,
                    email    => $conf->{'toaster_admin_email'},
                    clean    => 1,
                    debug    => $debug,
                )
              );
            $utility->_formatted( "install_supervise_run: updating $run_f...",
                "ok" );
        }
    }

    $toaster->supervised_dir_test(
        conf  => $conf,
        prot  => "smtp",
        debug => $debug
    );
    $toaster->supervised_dir_test(
        conf  => $conf,
        prot  => "send",
        debug => $debug
    );
    $toaster->supervised_dir_test(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug
    );
    $toaster->supervised_dir_test(
        conf  => $conf,
        prot  => "submit",
        debug => $debug
    );
}

sub maildir_in_skel {

    my $skel = "/usr/share/skel";
    unless ( -d $skel ) {
        $skel = "/etc/skel" if ( -d "/etc/skel" );    # linux
    }

    unless ( -e "$skel/Maildir" ) {

     #		only necessary for systems with local email accounts
     #		$utility->syscmd( command=>"$qmaildir/bin/maildirmake $skel/Maildir" ) ;
    }
}

sub netqmail {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'package' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $package, $fatal, $debug )
        = ( $p{'conf'}, $p{'package'}, $p{'fatal'}, $p{'debug'} );

    my $smtp_reject;
    my $ver      = $conf->{'install_netqmail'} || "1.05";
    my $src      = $conf->{'toaster_src_dir'}  || "/usr/local/src";
    my $qmaildir = $conf->{'qmail_dir'}        || "/var/qmail";

    $package ||= "netqmail-$ver";

    my $mysql = $conf->{'qmail_mysql_include'}
      || "/usr/local/lib/mysql/libmysqlclient.a";
    my $qmailgroup = $conf->{'qmail_log_group'}   || "qnofiles";
    my $vpopdir    = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $dl_site    = $conf->{'toaster_dl_site'}   || "http://www.tnpi.biz";
    my $dl_url     = $conf->{'toaster_dl_url'}    || "/internet/mail/toaster";
    my $toaster_url = "$dl_site$dl_url";
    my $vhome       = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

    # we do not want to try installing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # install the groups and users required by qmail
    $self->install_qmail_groups_users( conf => $conf, debug => $debug );

    # check to see if qmail-smtpd has vpopmail support already
    if ( -x "/var/qmail/bin/qmail-smtpd"
        && `strings /var/qmail/bin/qmail-smtpd | grep vpopmail` ) {
        if (
            !$utility->yes_or_no(
                {
                    question =>
"toasterized qmail is already installed, do you want to reinstall",
                    timeout => 30,
                }
            )
          )
        {
            return 0;
        }
    }

    $utility->chdir_source_dir( dir => "$src/mail" );

    unless ( $utility->source_warning( package=>$package, src=>"$src/mail" ) ) {
        carp "\nnetqmail: OK then, skipping install.\n\n";
        return;
    }

    if ( defined $conf->{'qmail_smtp_reject_patch'} ) {
        if ( $conf->{'qmail_smtp_reject_patch'} ) {
            $smtp_reject = 1;
            print "\t smtp_reject patch: yes\n";
        }
        else { print "\t smtp_reject patch: no\n" }
    }

    my $patch = "$package-toaster-3.1.patch";

    print "netqmail: using patch $patch\n";

    my $site = "http://www.qmail.org";

    # fetch the tarball if missing
    if ( !-e "$package.tar.gz" ) {

        # check to see if we have it in the ports repo
        if ( -e "/usr/ports/distfiles/$package.tar.gz" ) {
            use File::Copy;
            copy( "/usr/ports/distfiles/$package.tar.gz",
                "$src/mail/$package.tar.gz" );
        }
        else {
            $utility->file_get( url => "$site/$package.tar.gz", debug => $debug );
            unless ( -e "$package.tar.gz" ) {
                $err = "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
                croak $err if $fatal;
                carp $err;
                return;
            }
        }
    }

    unless ( -e $patch ) {
        $utility->file_get( url => "$toaster_url/patches/$patch", debug=>$debug );
        unless ( -e $patch ) {
            carp "\n\nfailed to fetch patch $patch!\n\n";
            croak if $fatal;
            return;
        }
    }

    my $smtp_rej_patch = "$package-smtp_reject-3.0.patch";

    unless ( -e $smtp_rej_patch ) {
        $utility->file_get( url => "$toaster_url/patches/$smtp_rej_patch", debug=>$debug );
        unless ( -e $smtp_rej_patch ) {
            $err = "\n\nfailed to fetch patch $smtp_rej_patch!\n\n";
            croak $err if $fatal;
            carp $err;
            return;
        }
    }

    unless ( $utility->archive_expand( archive => "$package.tar.gz", debug=>$debug ) ) {
        $err = "couldn't expand $package.tar.gz!\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    # netqmail requires a "collate" step before it can be built
    chdir("$src/mail/$package")
      or croak "netqmail: cd $src/mail/$package failed: $!\n";

    $utility->syscmd( command => "./collate.sh", debug=>$debug );

    chdir("$src/mail/$package/$package")
      or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";

    my $patchbin = $utility->find_the_bin( bin => "patch", debug=>$debug );

    # apply our custom patches
    print "netqmail: applying $patch\n";
    $utility->syscmd( command => "$patchbin < $src/mail/$patch", debug=>$debug );
    $utility->syscmd( command => "$patchbin < $src/mail/$smtp_rej_patch", debug=>$debug )
      if $smtp_reject;

    # make any localizations
    print "netqmail: fixing up conf-qmail\n";
    $utility->file_write( file => "conf-qmail", lines => [$qmaildir], debug=>$debug )
      or croak "couldn't write to conf-qmail: $!";

    print "netqmail: fixing up conf-vpopmail\n";
    $utility->file_write( file => "conf-vpopmail", lines => [$vpopdir], debug=>$debug )
      or croak "couldn't write to conf-vpopmail: $!";

    print "netqmail: fixing up conf-mysql\n";
    $utility->file_write( file => "conf-mysql", lines => [$mysql], debug=>$debug )
      or croak "couldn't write to conf-mysql: $!";

    # find those pesky openssl libraries
    my $prefix = $conf->{'toaster_prefix'} || "/usr/local/";
    my $ssl_lib = "$prefix/lib";
    if ( !-e "$ssl_lib/libcrypto.a" ) {
        if ( -e "/opt/local/lib/libcrypto.a" ) { $ssl_lib = "/opt/local/lib"; }
        elsif ( -e "/usr/local/lib/libcrypto.a" ) {
            $ssl_lib = "/usr/local/lib";
        }
        elsif ( -e "/opt/lib/libcrypto.a" ) { $ssl_lib = "/opt/lib"; }
        elsif ( -e "/usr/lib/libcrypto.a" ) { $ssl_lib = "/usr/lib"; }
    }

    my @lines = $utility->file_read( file => "Makefile", debug=>$debug );
    foreach my $line (@lines) {
        if ( $vpopdir ne "/home/vpopmail" ) {    # fix up vpopmail home dir
            if ( $line =~ /^VPOPMAIL_HOME/ ) {
                $line = 'VPOPMAIL_HOME=' . $vpopdir;
            }
        }

        # add in the discovered ssl library location
        if ( $line =~
            /tls.o ssl_timeoutio.o -L\/usr\/local\/ssl\/lib -lssl -lcrypto/ )
        {
            $line =
              '	tls.o ssl_timeoutio.o -L' . $ssl_lib . ' -lssl -lcrypto \\';
        }

        # again with the ssl libs
        if ( $line =~
/constmap.o tls.o ssl_timeoutio.o ndelay.a -L\/usr\/local\/ssl\/lib -lssl -lcrypto \\/
          )
        {
            $line =
                '	constmap.o tls.o ssl_timeoutio.o ndelay.a -L' . $ssl_lib
              . ' -lssl -lcrypto \\';
        }
    }
    $utility->file_write( file => "Makefile", lines => \@lines, debug=>$debug );

    if ( $conf->{'qmail_queue_extra'} ) {
        print "netqmail: enabling QUEUE_EXTRA...\n";
        my $success = 0;
        my @lines = $utility->file_read( file => "extra.h", debug=>$debug );
        foreach my $line (@lines) {
            if ( $line =~ /#define QUEUE_EXTRA ""/ ) {
                $line = '#define QUEUE_EXTRA "Tlog\0"';
                $success++;
            }

            if ( $line =~ /#define QUEUE_EXTRALEN 0/ ) {
                $line = '#define QUEUE_EXTRALEN 5';
                $success++;
            }
        }

        if ( $success == 2 ) {
            print "success.\n";
            $utility->file_write( file => "extra.h", lines => \@lines, debug=>$debug );
        }
        else {
            print "FAILED.\n";
        }
    }

    if ( $OSNAME eq "darwin" ) {
        $self->netqmail_darwin_fixups();
    }

    # add in the -I (include) dir for OpenSSL headers
    print "netqmail: fixing up conf-cc\n";
    my $cmd = "cc -O2 -DTLS=20060104 -I$vpopdir/include";

    if ( -d "/opt/local/include/openssl" ) {
        print "netqmail: building against /opt/local/include/openssl.\n";
        $cmd .= " -I/opt/local/include/openssl";
    }
    elsif ( -d "/usr/local/include/openssl" && $conf->{'install_openssl_port'} )
    {
        print
          "netqmail: building against /usr/local/include/openssl from ports.\n";
        $cmd .= " -I/usr/local/include/openssl";
    }
    elsif ( -d "/usr/include/openssl" ) {
        print "netqmail: using system supplied OpenSSL libraries.\n";
        $cmd .= " -I/usr/include/openssl";
    }
    else {
        if ( -d "/usr/local/include/openssl" ) {
            print "netqmail: building against /usr/local/include/openssl.\n";
            $cmd .= " -I/usr/local/include/openssl";
        }
        else {
            print
"netqmail: WARNING: I couldn't find your OpenSSL libraries. This might cause problems!\n";
        }
    }
    $utility->file_write( file => "conf-cc", lines => [$cmd], debug=>$debug )
      or croak "couldn't write to conf-cc: $!";

    print "netqmail: fixing up conf-groups\n";
    $utility->file_write(
        file  => "conf-groups",
        lines => [ "qmail", $qmailgroup ], 
        debug => $debug,
    ) or croak "couldn't write to conf-groups: $!";

    my $servicectl = "/usr/local/sbin/services";
    if ( -x "/usr/local/sbin/services" ) {
        print "Stopping Qmail!\n";
        $self->send_stop( conf => $conf );
        $utility->syscmd( command => "$servicectl stop", debug=>$debug );
    }

    my $make = $utility->find_the_bin( bin => "gmake", fatal => 0, debug=>$debug )
      or $utility->find_the_bin( bin => "make", debug=>$debug );

    $utility->syscmd( command => "$make setup", debug=>$debug );

    unless ( -f "$qmaildir/control/servercert.pem" ) {
        print "netqmail: installing SSL certificates \n";
        $utility->syscmd( command => "$make cert", debug=>$debug );
    }

    unless ( -f "$qmaildir/control/rsa512.pem" ) {
        print "netqmail: install temp SSL \n";
        $utility->syscmd( command => "$make tmprsadh", debug=>$debug );
    }

    $utility->file_chown(
        file => "$qmaildir/bin/qmail-smtpd",
        uid  => 'vpopmail',
        gid  => 'vchkpw', 
        debug=> $debug,
    );

    $utility->file_chmod(
        file_or_dir => "$qmaildir/bin/qmail-smtpd",
        mode        => '6555', 
        debug       => $debug,
    );

    $self->maildir_in_skel();
    $self->config( conf => $conf, debug=>$debug );

    if ( -x $servicectl ) {
        print "Starting Qmail & supervised services!\n";
        $utility->syscmd( command => "$servicectl start", debug=>$debug );
    }
}

sub netqmail_darwin_fixups {

    print "netqmail: fixing up conf-ld\n";
    $utility->file_write( file => "conf-ld", lines => ["cc -Xlinker -x"] )
      or croak "couldn't write to conf-ld: $!";

    print "netqmail: fixing up dns.c for Darwin\n";
    my @lines = $utility->file_read( file => "dns.c" );
    foreach my $line (@lines) {
        if ( $line =~ /#include <netinet\/in.h>/ ) {
            $line = "#include <netinet/in.h>\n#include <nameser8_compat.h>";
        }
    }
    $utility->file_write( file => "dns.c", lines => \@lines );

    print "netqmail: fixing up strerr_sys.c for Darwin\n";
    @lines = $utility->file_read( file => "strerr_sys.c" );
    foreach my $line (@lines) {
        if ( $line =~ /struct strerr strerr_sys/ ) {
            $line = "struct strerr strerr_sys = {0,0,0,0};";
        }
    }
    $utility->file_write( file => "strerr_sys.c", lines => \@lines );

    print "netqmail: fixing up hier.c for Darwin\n";
    @lines = $utility->file_read( file => "hier.c" );
    foreach my $line (@lines) {
        if ( $line =~
            /c\(auto_qmail,"doc","INSTALL",auto_uido,auto_gidq,0644\)/ )
        {
            $line =
              'c(auto_qmail,"doc","INSTALL.txt",auto_uido,auto_gidq,0644);';
        }
    }
    $utility->file_write( file => "hier.c", lines => \@lines );

    # fixes due to case sensitive file system
    move( "INSTALL",  "INSTALL.txt" );
    move( "SENDMAIL", "SENDMAIL.txt" );
}

sub netqmail_virgin {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'package' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $package, $fatal, $debug )
        = ( $p{'conf'}, $p{'package'}, $p{'fatal'}, $p{'debug'} );

    my ($chkusr);

    my $ver      = $conf->{'install_netqmail'} || "1.05";
    my $src      = $conf->{'toaster_src_dir'}  || "/usr/local/src";
    my $qmaildir = $conf->{'qmail_dir'}        || "/var/qmail";

    $package ||= "netqmail-$ver";

    my $mysql = $conf->{'qmail_mysql_include'}
      || "/usr/local/lib/mysql/libmysqlclient.a";
    my $qmailgroup = $conf->{'qmail_log_group'} || "qnofiles";

    # we do not want to try installing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    $self->install_qmail_groups_users( conf => $conf );

    $utility->chdir_source_dir( dir => "$src/mail" );

    unless ( $utility->source_warning( package=>$package, src=>$src ) ) {
        carp "\nnetqmail: OK then, skipping install.\n\n";
        return;
    }

    my $site = "http://www.qmail.org";

    # fetch the tarball if missing
    if ( !-e "$package.tar.gz" ) {
        if ( -e "/usr/ports/distfiles/$package.tar.gz" ) {
            use File::Copy;
            copy( "/usr/ports/distfiles/$package.tar.gz",
                "$src/mail/$package.tar.gz" );
        }
        else {
            $utility->file_get( url => "$site/$package.tar.gz", debug=>$debug );
            unless ( -e "$package.tar.gz" ) {
                croak "netqmail FAILED: couldn't fetch $package.tar.gz!\n";
            }
        }
    }

    unless ( $utility->archive_expand( archive => "$package.tar.gz", debug=>$debug ) ) {
        croak "couldn't expand $package.tar.gz\n";
    }

    # netqmail requires a "collate" step before it can be built
    chdir("$src/mail/$package")
      or croak "netqmail: cd $src/mail/$package failed: $!\n";
    $utility->syscmd( command => "./collate.sh", debug=>$debug );
    chdir("$src/mail/$package/$package")
      or croak "netqmail: cd $src/mail/$package/$package failed: $!\n";

    # make any localizations
    print "netqmail: fixing up conf-qmail\n";
    $utility->file_write( file => "conf-qmail", lines => [$qmaildir], debug=>$debug )
      or croak "couldn't write to conf-qmail: $!";

    print "netqmail: fixing up conf-mysql\n";
    $utility->file_write( file => "conf-mysql", lines => [$mysql], debug=>$debug )
      or croak "couldn't write to conf-mysql: $!";

    if ( $OSNAME eq "darwin" ) {
        $self->netqmail_darwin_fixups();
    }

    print "netqmail: fixing up conf-cc\n";
    $utility->file_write( file => "conf-cc", lines => ["cc -O2"], debug=>$debug )
      or croak "couldn't write to conf-cc: $!";

    print "netqmail: fixing up conf-groups\n";
    $utility->file_write(
        file  => "conf-groups",
        lines => [ "qmail", $qmailgroup ],
        debug => $debug,
    ) or croak "couldn't write to conf-groups: $!";

    my $servicectl = "/usr/local/sbin/services";
    if ( -x $servicectl ) {
        print "Stopping Qmail!\n";
        $self->send_stop( conf => $conf );
        $utility->syscmd( command => "$servicectl stop", debug=>$debug );
    }

    my $make = $utility->find_the_bin( bin => "gmake", fatal => 0 )
      or $utility->find_the_bin( bin => "make", debug=>$debug );

    $utility->syscmd( command => "$make setup", debug=>$debug );

    $self->maildir_in_skel();

    $self->config(conf=>$conf, debug=>$debug);

    if ( -x $servicectl ) {
        print "Starting Qmail & supervised services!\n";
        $utility->syscmd( command => "$servicectl start", debug=>$debug );
    }
}

sub queue_check {

    # used in qqtool.pl

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $base  = $conf->{'qmail_dir'};
    unless ( $base ) {
        print "queue_check: ERROR! qmail_dir is not set in conf! This is almost certainly an error!\n";
        $base = "/var/qmail"
    }
    
    my $queue = "$base/queue";

    print "queue_check: checking $queue..." if $debug;

    unless ( $queue && -d $queue ) {
        print "FAILED.\n" if $debug;

        $err = "\tHEY! The queue directory for qmail is missing!\n";
        $err .= "\tI expected it to be at $queue\n" if $queue;
        $err .= "\tIt should have been set via the qmail_dir setting in toaster-watcher.conf!\n";

        croak $err if $fatal;
        carp $err;
        return;
    }
    
    print "ok.\n" if $debug;
    return "$base/queue";
}

sub queue_process {

    my $svc = $utility->find_the_bin( bin => "svc", fatal => 0, debug=>0 );

    unless ( -x $svc ) {
        print "FAILED: unable to find svc! Is daemontools installed?\n";
        return;
    }

    # we may want to make this configurable at some point
    my $qcontrol = "/service/send";

    print "\nSending ALRM signal to qmail-send.\n";
    $utility->syscmd( command => "$svc -a $qcontrol", debug=>0 );
}

sub rebuild_ssl_temp_keys {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $openssl = $utility->find_the_bin( bin => "openssl", debug => $debug, fatal=>$fatal );

    my $qmdir = $conf->{'qmail_dir'} || "/var/qmail";
    my $cert  = "$qmdir/control/rsa512.pem";

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }
    
    if ( -M $cert >= 1 || !-e $cert ) {
        print "rebuild_ssl_temp_keys: rebuilding RSA key\n" if $debug;
        $utility->syscmd(
            command => "$openssl genrsa -out $cert.new 512 2>/dev/null",
            debug   => $debug,
            fatal   => $fatal,
        );

        install_ssl_temp_key( $conf, $cert, $debug, $fatal );
    }

    $cert = "$qmdir/control/dh512.pem";
    if ( -M $cert >= 1 || !-e $cert ) {
        print "rebuild_ssl_temp_keys: rebuilding DSA 512 key\n" if $debug;
        $utility->syscmd(
            command => "$openssl dhparam -2 -out $cert.new 512 2>/dev/null",
            debug   => $debug,
            fatal   => $fatal,
        );

        install_ssl_temp_key( $conf, $cert, $debug, $fatal );
    }

    $cert = "$qmdir/control/dh1024.pem";
    if ( -M $cert >= 1 || !-e $cert ) {
        print "rebuild_ssl_temp_keys: rebuilding DSA 1024 key\n" if $debug;
        $utility->syscmd(
            command => "$openssl dhparam -2 -out $cert.new 1024 2>/dev/null",
            debug   => $debug,
            fatal   => $fatal,
        );

        install_ssl_temp_key( $conf, $cert, $debug, $fatal );
    }

    return 1;

    sub install_ssl_temp_key {

        my ( $conf, $cert, $debug, $fatal ) = @_;

        my $user  = $conf->{'smtpd_run_as_user'} || "vpopmail";
        my $group = $conf->{'qmail_group'}       || "qmail";

        $utility->file_chmod(
            file_or_dir => "$cert.new",
            mode        => '0660',
            debug       => $debug,
            fatal       => $fatal,
        );

        $utility->file_chown(
            file  => "$cert.new",
            uid   => $user,
            gid   => $group,
            debug => $debug,
            fatal => $fatal,
        );

        move( "$cert.new", $cert );
    }
}

sub restart {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $svc = $utility->find_the_bin( bin => "svc", fatal => 0, debug=>$debug );

    unless ( -x $svc ) {
        carp "FAILED: unable to find svc! Is daemontools installed?\n";
        return;
    }

    my $qcontrol = $self->service_dir_get( conf => $conf, prot => "send", debug=>$debug );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    return $toaster->supervise_restart($qcontrol);
}

sub send_start {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    my $qcontrol = $self->service_dir_get( conf => $conf, prot => "send", debug=>$debug );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( ! -d $qcontrol ) {
        $err = "send_start: uh oh, the service directory $qcontrol "
            . "is missing! Giving up.\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    if ( ! $toaster->supervised_dir_test( conf=>$conf, prot=>"send",  debug=>$debug ) ) {
        $err = "send_start: something was wrong with the service/send dir.\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    unless ( $UID == 0 ) {
        $err = "Only root can control supervised daemons, and you aren't root!";
        croak $err if $fatal;
        carp $err;
        return;
    };

    my $svc    = $utility->find_the_bin( bin => "svc", debug=>0 );
    my $svstat = $utility->find_the_bin( bin => "svstat", debug=>0 );

    # Start the qmail-send (and related programs)
    system "$svc -u $qcontrol";

    # loop until it is up and running.
    foreach my $i ( 1 .. 200 ) {
        my $r = `$svstat $qcontrol`;
        chomp $r;
        if ( $r =~ /^.*:\sup\s\(pid [0-9]*\)\s[0-9]*\sseconds$/ ) {
            print "Yay, we're up!\n";
            return 1;
        }
        sleep 1;
    }
    return 1;
}

sub send_stop {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $fatal, $debug )
        = ( $p{'conf'}, $p{'fatal'}, $p{'debug'} );

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $svc    = $utility->find_the_bin( bin => "svc", debug=>0 );
    my $svstat = $utility->find_the_bin( bin => "svstat", debug=>0 );

    my $qcontrol = $self->service_dir_get( conf => $conf, prot => "send", debug=>$debug );

    unless ($qcontrol) {
        $err = "send_restart: uh oh, the service directory $qcontrol is missing! Giving up.\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    if ( ! $toaster->supervised_dir_test( conf=>$conf, prot=>"send", dir=>$qcontrol, debug=>$debug ) ) {
        $err = "send_start: something was wrong with the service/send dir.\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    unless ( $UID == 0 ) {
        $err = "Only root can control supervised daemons, and you aren't root!";
        croak $err if $fatal;
        carp $err;
        return;
    };

    # send qmail-send a TERM signal
    system "$svc -d $qcontrol";

    # loop up to a thousand seconds waiting for qmail-send to exit
    foreach my $i ( 1 .. 1000 ) {
        my $r = `$svstat $qcontrol`;
        chomp $r;
        if ( $r =~ /^.*:\sdown\s[0-9]*\sseconds/ ) {
            print "Yay, we're down!\n";
            return;
        }
        elsif ( $r =~ /supervise not running/ ) {
            print "Yay, we're down!\n";
            return;
        }
        else {

            # if more than 100 seconds passes, lets kill off the qmail-remote
            # processes that are forcing us to wait.

            if ( $i > 100 ) {
                $utility->syscmd( command => "killall qmail-remote", debug=>0 );
            }
            print "$r\n";
        }
        sleep 1;
    }
    return 1;
}

sub service_dir_get {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $prot, $fatal, $debug )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my ($servicedir);

    if ( defined $conf && $conf ) {
        $servicedir = $conf->{'qmail_service'};
    }
    $servicedir ||= "/var/service";

    # check for old location of service dir in /
    if ( !-d $servicedir and $servicedir eq "/var/service" ) {
        if ( -d "/service" ) { $servicedir = "/service" }
    }

    $utility->_formatted("service_dir_get: service dir is $servicedir")
      if $debug;

    # catch and fix this legacy usage.
    if ( $prot eq "smtpd" ) { $prot = "smtp" }

    # create a hash full of valid values
    my %valid = (
        'submit' => 1,
        'smtp'   => 1,
        'pop3'   => 1,
        'send'   => 1,
    );

    # make sure the passed value is present in the hash
    if ( !$valid{$prot} ) {
        $err = "\t an invalid value was sent for prot.";
        $utility->_formatted( $err, "FATAL" ) if $debug;
        croak $err if $fatal;
        return;
    }

    $utility->_formatted("\t getting dir for prot: $prot") if $debug;

    # get the value of $dir from the $conf->qmail_service_[$prot] setting
    my $dir = "qmail_service_" . $prot;
    $dir = $conf->{$dir};

    # if that was not set...
    if ( !defined $dir or !$dir ) {
        $utility->_formatted(
"\t qmail_service_$prot is not set correctly in toaster-watcher.conf! ",
            "WARNING"
        ) if $debug;
        $dir = "$servicedir/$prot";
    }
    $utility->_formatted( "\t configured $prot dir is $dir", "ok" ) if $debug;

    # expand any qmail_service aliases
    if ( $dir =~ /^qmail_service\/(.*)$/ ) {
        $dir = "$servicedir/$1";
        $utility->_formatted( "\t $prot dir expanded to: $dir", 'ok' )
          if $debug;
    }

    return $dir;
}

sub smtp_auth_enable {
    my $self = shift;
    my $conf = shift;
    my $debug = shift;

    if ( ! $conf->{'smtpd_auth_enable'} ) {
        return q{};
    };

    my $smtp_auth_cmd;

    print "build_smtp_run: enabling SMTP-AUTH\n" if $debug;

    # deprecated, should not be used any longer
    if ( $conf->{'smtpd_hostname'} && $conf->{'qmail_smtpd_auth_0.31'} ) {
        print "build_smtp_run: configuring smtpd hostname\n" if $debug;
        $smtp_auth_cmd .= $toaster->supervised_hostname(
            conf  => $conf,
            prot  => "smtpd",
            debug => $debug
        );
    }

    my $chkpass = $self->_set_checkpasswd_bin(
        conf  => $conf,
        prot  => "smtpd",
        debug => $debug
    );

    $smtp_auth_cmd .= $chkpass ? $chkpass : return q{};
    $smtp_auth_cmd .= "/usr/bin/true ";

    return $smtp_auth_cmd;
}

sub smtp_set_qmailqueue {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'prot'    => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $prot, $fatal, $debug )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my $qdir = $conf->{'qmail_dir'};

    if ( $conf->{'filtering_method'} ne "smtp" ) {
        print
"smtp_set_qmailqueue: filtering_method != smtp, not setting QMAILQUEUE.\n"
          if $debug;
        return "";
    }

    # typically this will be simscan, qmail-scanner, or qmail-queue
    my $queue = $conf->{'smtpd_qmail_queue'};

    if ( defined $prot && $prot eq "submit" ) {
        $queue = $conf->{'submit_qmail_queue'};
    }

    # if the selected one is not executable...
    if ( !-x $queue ) {

        # if qmail-queue is missing...
        if ( !-x "$qdir/bin/qmail-queue" ) {
            $err = "WARNING: $queue is not executable by uid $>.\n";
            croak $err if $fatal;
            carp $err;
            return;
        }

        carp "WARNING: $queue is not executable! I'm falling back to 
$qdir/bin/qmail-queue. You need to either (re)install $queue or update your
toaster-watcher.conf file to point to its correct location.

You will continue to get this notice every 5 minutes until you fix this.\n";
        $queue = "$qdir/bin/qmail-queue";
    }

    print "smtp_set_qmailqueue: using $queue for QMAILQUEUE\n" if $debug;

    return "QMAILQUEUE=\"$queue\"\nexport QMAILQUEUE\n";
}

sub smtp_set_rbls {
    my $self = shift;
    my $conf = shift;
    my $debug = shift;

    if (  ! $conf->{'rwl_enable'} && ! $conf->{'rbl_enable'} ) {
        return q{};
    }

    my $rbl_cmd_string;

    my $rblsmtpd =
        $utility->find_the_bin( bin => "rblsmtpd", debug => $debug );
    $rbl_cmd_string .= "$rblsmtpd ";

    print "smtp_set_rbls: using rblsmtpd\n" if $debug;

    my $timeout = $conf->{'rbl_timeout'} || 60;
    $rbl_cmd_string .= $timeout != 60 ? "-t $timeout " : q{};

    $rbl_cmd_string .= "-c " if  $conf->{'rbl_enable_fail_closed'};
    $rbl_cmd_string .= "-b " if !$conf->{'rbl_enable_soft_failure'};

    if ( $conf->{'rwl_enable'} && $conf->{'rwl_enable'} > 0 ) {
        print "testing RWLs...." if $debug;

        my $list = $self->get_list_of_rwls( $conf, $debug );
        foreach my $rwl (@$list) { $rbl_cmd_string .= "-a $rwl " }

        print "done.\n" if $debug;
    }
    else { print "no RWL's selected\n" if $debug }

    if ( $conf->{'rbl_enable'} && $conf->{'rbl_enable'} > 0 ) {
        print "testing RBLs...." if $debug;
        my $list =
            $self->get_list_of_rbls( conf => $conf, debug => $debug );
        $rbl_cmd_string .= $list if $list;
        print "done.\n" if $debug;
    }
    else { print "no RBL's selected\n" if $debug }

    return $rbl_cmd_string;
};

sub smtpd_restart {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $prot, $fatal, $debug )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my $dir =
      $self->service_dir_get( conf => $conf, prot => $prot, debug => $debug );

    unless ( -d $dir || -l $dir ) {
        $err = "smtpd_restart: no such dir: $dir!\n";
        croak $err if $fatal;
        carp $err;
        return;
    }

    print "restarting qmail smtpd..." if $debug;
    $toaster->supervise_restart($dir);
    print "done.\n" if $debug;
}

sub supervise_dir_get {


    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $prot, $fatal, $debug )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my $supervisedir = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    if ( !-d $supervisedir and $supervisedir eq "/var/supervise" ) {
        # this is for legacy/compatability
        if ( -d "/supervise" ) { $supervisedir = "/supervise" }
    }

    my $dir;
    if    ( $prot eq "smtp" )   { $dir = $conf->{'qmail_supervise_smtp'}; }
    elsif ( $prot eq "pop3" )   { $dir = $conf->{'qmail_supervise_pop3'}; }
    elsif ( $prot eq "send" )   { $dir = $conf->{'qmail_supervise_send'}; }
    elsif ( $prot eq "submit" ) { $dir = $conf->{'qmail_supervise_submit'}; }
    else {
        carp "supervise_dir_get: FAILURE: please read 'perldoc Mail::Toaster::Qmail'"
            . "to see how to use this subroutine.\n";
        return;
    }

    # make sure $dir got set
    if ( !$dir ) {
        carp "WARNING: qmail_supervise_$prot is not set correctly in toaster-watcher.conf!";
        $dir = "$supervisedir/$prot";
    }

    # expand the qmail_supervise shortcut
    if ( $dir =~ /^qmail_supervise\/(.*)$/ ) {
        $dir = "$supervisedir/$1";
    }

    print "supervise_dir_get: using $dir for $prot \n" if $debug;
    return $dir;
}

sub svscan_dir_exists {

    my $self = shift;

    # parameter validation
    my %p = validate (@_, {
            'conf'    => HASHREF,
            'name'    => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $conf, $name, $fatal) = ($p{'conf'}, $p{'name'}, $p{'fatal'} );

    my $qsupervise = $conf->{'qmail_supervise'};

    if ( !-d $qsupervise ) {
        if ( $p{'debug'} ) {
            print $name . ": " if $name;
            $err = "FAILURE: supervise dir $qsupervise doesn't exist!";
            carp $err;
        }
        croak $err if $p{'fatal'};
        return;
    }

    return 1;
}

sub test_each_rbl {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'rbls'    => { type=>ARRAYREF,  },
            'conf'    => { type=>HASHREF, optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $rbls, $fatal, $debug )
        = ( $p{'rbls'}, $p{'fatal'}, $p{'debug'} );

    require Mail::Toaster::DNS;
    my $t_dns = Mail::Toaster::DNS->new();

    my (@list);

    foreach my $rbl (@$rbls) {
        print "testing $rbl.... " if $debug;
        my $r = $t_dns->rbl_test( zone => $rbl, debug => $debug );
        if ($r) { push @list, $rbl }
        print "$r \n" if $debug;
    }
    return \@list;
}

sub UpdateVirusBlocks {

    # deprecated function - no longer maintained.

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'ips'     => { type=>ARRAYREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $ips, $fatal, $debug, $test_ok )
        = ( $p{'conf'}, $p{'ips'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

#	unless ( $utility->is_hashref($conf) )
#	{ #
#		my ($package, $filename, $line) = caller;
#		carp "FATAL: $filename:$line passed UpdateVirusBlocks an invalid argument.\n";
#		return 0;
#	}

    my $time  = $conf->{'qs_block_virus_senders_time'};
    my $relay = $conf->{'smtpd_relay_database'};
    my $vpdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

    if ( $relay =~ /^vpopmail_home_dir\/(.*)\.cdb$/ ) {
        $relay = "$vpdir/$1";
    }
    else {
        if ( $relay =~ /^(.*)\.cdb$/ ) { $relay = $1; }
    }
    unless ( -r $relay ) { croak "$relay selected but not readable!\n" }

    my @lines;

    $debug = 0;
    my $in     = 0;
    my $done   = 0;
    my $now    = time;
    my $expire = time + ( $time * 3600 );

    print "now: $now   expire: $expire\n" if $debug;

    my @userlines = $utility->file_read( file => $relay );
  USERLINES: foreach my $line (@userlines) {
        unless ($in) { push @lines, $line }
        if ( $line =~ /^### BEGIN QMAIL SCANNER VIRUS ENTRIES ###/ ) {
            $in = 1;

            for (@$ips) {
                push @lines,
"$_:allow,RBLSMTPD=\"-VIRUS SOURCE: Block will be automatically removed in $time hours: ($expire)\"\n";
            }
            $done++;
            next USERLINES;
        }

        if ( $line =~ /^### END QMAIL SCANNER VIRUS ENTRIES ###/ ) {
            $in = 0;
            push @lines, $line;
            next USERLINES;
        }

        if ($in) {
            my ($timestamp) = $line =~ /\(([0-9]+)\)"$/;
            unless ($timestamp) {
                print "ERROR: malformed line: $line\n" if $debug;
            }

            if ( $now > $timestamp ) {
                print "removing $timestamp\t" if $debug;
            }
            else {
                print "leaving $timestamp\t" if $debug;
                push @lines, $line;
            }
        }
    }

    if ($done) {
        if ($debug) {
            foreach my $line (@lines) { print "$line\n"; }
        }
        $utility->file_write( file => $relay, lines => \@lines, debug=>$debug );
    }
    else {
        print
"FAILURE: Couldn't find QS section in $relay\n You need to add the following lines as documented in the toaster-watcher.conf and FAQ:

### BEGIN QMAIL SCANNER VIRUS ENTRIES ###
### END QMAIL SCANNER VIRUS ENTRIES ###

";
    }

    my $tcprules = $utility->find_the_bin( bin => "tcprules", debug=>$debug );
    $utility->syscmd( 
        command => "$tcprules $vpdir/etc/tcp.smtp.cdb $vpdir/etc/tcp.smtp.tmp "
            . "< $vpdir/etc/tcp.smtp",
		  debug   => $debug,
    );
    chmod oct('0644'), "$vpdir/etc/tcp.smtp*";
}

sub _memory_explanation {

    my ( $self, $conf, $prot, $maxcon ) = @_;
    my (
        $sysmb,         $maxsmtpd,   $memorymsg,
        $perconnection, $connectmsg, $connections
    );

    carp "\nbuild_${prot}_run: your "
      . "${prot}_max_memory_per_connection and "
      . "${prot}_max_connections settings in toaster-watcher.conf have exceeded your "
      . "${prot}_max_memory setting. I have reduced the maximum concurrent connections "
      . "to $maxcon to compensate. You should fix your settings.\n\n";

    if ( $OSNAME eq "freebsd" ) {
        $sysmb = int( substr( `/sbin/sysctl hw.physmem`, 12 ) / 1024 / 1024 );
        $memorymsg = "Your system has $sysmb MB of physical RAM.  ";
    }
    else {
        $sysmb     = 1024;
        $memorymsg =
          "This example assumes a system with $sysmb MB of physical RAM.";
    }

    $maxsmtpd = int( $sysmb * 0.75 );

    if ( $conf->{'install_mail_filtering'} ) {
        $perconnection = 40;
        $connectmsg    =
          "This is a reasonable value for systems which run filtering.";
    }
    else {
        $perconnection = 15;
        $connectmsg    =
          "This is a reasonable value for systems which do not run filtering.";
    }

    $connections = int( $maxsmtpd / $perconnection );
    $maxsmtpd    = $connections * $perconnection;

    carp <<EOMAXMEM;

These settings control the concurrent connection limit set by tcpserver,
and the per-connection RAM limit set by softlimit. 

Here are some suggestions for how to set these options:

$memorymsg

smtpd_max_memory = $maxsmtpd # approximately 75% of RAM

smtpd_max_memory_per_connection = $perconnection
   # $connectmsg

smtpd_max_connections = $connections

If you want to allow more than $connections simultaneous SMTP connections,
you'll either need to lower smtpd_max_memory_per_connection, or raise 
smtpd_max_memory.

smtpd_max_memory_per_connection is a VERY important setting, because
softlimit/qmail will start soft-bouncing mail if the smtpd processes
exceed this value, and the number needs to be sufficient to allow for
any virus scanning, filtering, or other processing you have configured
on your toaster. 

If you raise smtpd_max_memory over $sysmb MB to allow for more than
$connections incoming SMTP connections, be prepared that in some
situations your smtp processes might use more than $sysmb MB of memory. 
In this case, your system will use swap space (virtual memory) to
provide the necessary amount of RAM, and this slows your system down. In
extreme cases, this can result in a denial of service-- your server can
become unusable until the services are stopped.

EOMAXMEM

}

sub _test_smtpd_config_values {


=for  _test_smtpd_config_values

 Runs the following tests:
 
   make sure toaster.conf exists
   make sure qmail_dir exists
   make sure vpopmail home dir exists
   make sure qmail_supervise is set and is not a directory

=cut


    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $test_ok, $fatal, $debug )
        = ( $p{'conf'}, $p{'test_ok'}, $p{'fatal'}, $p{'debug'} );

    # make sure toaster.conf is found
    my $file = $utility->find_config( file => "toaster.conf", debug => $debug );

    # make sure qmail_dir is defined and exists
    if ( !-d $conf->{'qmail_dir'} ) {
        $err = "FAILURE: qmail_dir does not exist as configured in $file\n";
        croak $err if $fatal; carp $err;
        return;
    }

    # if vpopmail is installed, make sure the vpopmail home dir exists
    if ( $conf->{'install_vpopmail'} && !-d $conf->{'vpopmail_home_dir'} ) {
        $err = "vpopmail_home_dir does not exist as configured in $file!";
        croak $err if $fatal;
        $utility->_formatted( $err , "FAILURE" );
        return;
    }

    # make sure qmail_supervise is set and is not a directory
    my $qsuper = $conf->{'qmail_supervise'};
    if ( !defined $qsuper || !$qsuper ) {
        $err = "_test_smtpd_config_values: conf->qmail_supervise is not set!\n";
        croak $err if $fatal; carp $err;
        return;
    }

    # make sure qmail_supervise is not a directory
    if ( !-d $qsuper ) {
        $err = "FAILURE: qmail_supervise ($qsuper) is not a directory!\n";
        croak $err if $fatal; carp $err if $debug;
        return;
    }

    return 1;

  #  This is no longer necessary with vpopmail > 5.4.0 and 0.4.2 SMTP-AUTH patch
  #	croak "FAILURE: smtpd_hostname is not set in $file.\n"
  #		unless ( $conf->{'smtpd_hostname'} );
}

sub _smtp_sanity_tests {

    my $self = shift;

    my %p = validate( @_, { 'conf' => HASHREF, },);

    my $conf = $p{'conf'};
    my $qdir = $conf->{'qmail_dir'} || "/var/qmail";

    return "
if [ ! -f $qdir/control/rcpthosts ]; then
	echo \"No $qdir/control/rcpthosts!\"
	echo \"Refusing to start SMTP listener because it'll create an open relay\"
	exit 1
fi\n";

}

sub _set_checkpasswd_bin {

    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, },
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $prot, $fatal, $debug, $test_ok )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );


    print "\t setting checkpasswd for protocol: $prot \n" if $debug;

    # get vpopmails base directory
    my $vdir = $conf->{'vpopmail_home_dir'};
    unless ($vdir) {
        carp "ERROR: why is vpopmail_home_dir not set in $conf?\n";
        return;
    }

    my $prot_dir = $prot . "_checkpasswd_bin";
    print "\t getting protocol directory for $prot from conf->$prot_dir\n"
      if $debug;

    my $chkpass = $conf->{$prot_dir};

    print "\t build_" . $prot . "_run: using $chkpass for checkpasswd\n"
      if $debug;

    unless ($chkpass) {
        print "WARNING: ${prot_dir} is not set in toaster-watcher.conf!\n";
        $chkpass = "$vdir/bin/vchkpw";
        print "build_" . $prot . "_run: using $chkpass\n" if $debug;
    }

    # vpopmail_home_dir is an alias, check for and expand it
    if ( $chkpass =~ /^vpopmail_home_dir\/(.*)$/ ) {

        $chkpass = "$vdir/$1";
        print "\t build_" . $prot . "_run: expanded to $chkpass\n" if $debug;
    }

    # make sure the program is a valid file and is executable
    unless ( -x $chkpass ) {
        carp "build_" . $prot
          . "_run: FATAL: chkpass program $chkpass selected but not executable!\n";
        return;
    }

    return "$chkpass ";
}

sub supervised_hostname_qmail {


    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF, optional=>1, },
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $conf, $prot, $fatal, $debug, $test_ok )
        = ( $p{'conf'}, $p{'prot'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    my $qsupervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    my $prot_val = "qmail_supervise_" . $prot;
    my $prot_dir = $conf->{$prot_val} || "$qsupervise/$prot";

    print "build_" . $prot . "_run: supervise dir is $prot_dir\n" if $debug;

    if ( $prot_dir =~ /^qmail_supervise\/(.*)$/ ) {
        $prot_dir = "$qsupervise/$1";
        print "build_" . $prot . "_run: expanded supervise dir to $prot_dir\n"
          if $debug;
    }

    # the qmail control file for setting the hostname
    my $me = "/var/qmail/control/me";
    if ( $conf && $conf->{'qmail_dir'} ) {

        # allow override via $conf settings
        $me = $conf->{'qmail_dir'} . "/control/me";
    }

    my @lines;
    push @lines, "LOCAL=\`head -1 $me\`";
    push @lines, "if [ -z \"\$LOCAL\" ]; then";
    push @lines,
"\techo ERROR: $prot_dir/run tried reading your hostname from $me and failed!";
    push @lines, "\texit 1";
    push @lines, "fi\n";
    print "build_" . $prot . "_run: hostname set to contents of $me\n"
      if $debug;

    return @lines;
}

sub _supervise_dir_exist {

    my $self = shift;

    # parameter validation
    my %p = validate (@_, {
            'dir'     => SCALAR,
            'name'    => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        }
    );
 
    my ( $dir, $name, $fatal) = ($p{'dir'}, $p{'name'}, $p{'fatal'} );

    if ( !-d $dir ) {
        if ( $p{'debug'} ) {
            print $name . ": " if $name;
            print "FAILURE: supervise dir $dir doesn't exist!\n";
        }
        return;
    }

    return 1;
}

1;
__END__


=head1 NAME
 
Mail::Toaster:::Qmail - Qmail specific functions
 
 
=head1 VERSION
 
This documentation refers to <Mail::Toaster::Qmail> version 5.00
 
 
=head1 SYNOPSIS

    use Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    $qmail->install();

Mail::Toaster::Qmail is a module of Mail::Toaster. It contains methods for use with qmail, like starting and stopping the deamons, installing qmail, checking the contents of config files, etc. Nearly all functionality  contained herein is accessed via toaster_setup.pl.

See http://mail-toaster.org/ for details.


=head1 DESCRIPTION
 
A full description of the module and its features.
May include numerous subsections (i.e. =head2, =head3, etc.) 
 
This module has all sorts of goodies, the most useful of which are the build_????_run modules which build your qmail control files for you. See the METHODS section for more details.
 

=head1 SUBROUTINES/METHODS 
 
An object of this class represents a means for interacting with qmail. There are functions for starting, stopping, installing, generating run-time config files, building ssl temp keys, testing functionality, monitoring processes, and training your spam filters. 

=over 8

=item new

To use any of the methods following, you need to create a qmail object:

	use Mail::Toaster::Qmail;
	my $qmail = Mail::Toaster::Qmail->new();



=item build_pop3_run

	$qmail->build_pop3_run( conf=>$conf, file=>$file, debug=>$debug) 
		? print "success" : print "failed";

Generate a supervise run file for qmail-pop3d. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see $utility->parse_config). I typically use it like this:

  my $file = "/tmp/toaster-watcher-pop3-runfile";
  if ( $qmail->build_pop3_run( conf=>$conf, file=>$file ) )
  {
    $qmail->install_supervise_run( tmpfile=>$file, prot=>"pop3", conf=>$conf);
  };

If it succeeds in building the file, it will install it. You should restart the service after installing a new run file.

 arguments required:
    conf - as hashref with the contents of toaster-watcher.conf
    file - the temp file to construct

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success


=item install_qmail_control_log_files

	$qmail->install_qmail_control_log_files( conf=>$conf );

$conf is a hash of values. See $utility->parse_config or toaster-watcher.conf for config values.

Installs the files that control your supervised processes logging. Typically this consists of qmail-smtpd, qmail-send, and qmail-pop3d. The generated files are:

 arguments required:
    conf

 arguments optional:
    prots - an arrayref list of protocols to build run files for. 
           Defaults to [pop3,smtp,send,submit]
	debug
	fatal

 Results:
    qmail_supervise/pop3/log/run
    qmail_supervise/smtp/log/run
    qmail_supervise/send/log/run
    qmail_supervise/submit/log/run


=item install_supervise_run

Installs a new supervise/run file for a supervised service. It first builds a new file, then compares it to the existing one and installs the new file if it has changed. It optionally notifies the admin.

  my $file = "/tmp/mtw-smtpd-runfile";

  if ( $qmail->build_smtp_run( conf=>$conf, tmpfile=>$file, debug=>$debug ) )
  {
    $qmail->install_supervise_run( tmpfile=>$file, prot=>"smtp", debug=>$debug );
  };

 arguments required:
   tmpfile   - new file that was created (typically /tmp/something)
   destination - either set it explicitely, or set prot.

 arguments optional:
   conf  
   destination - where the tmpfile gets installed to. Defaults to $service/$prot/run
   prot     - one of (smtp, send, pop3, submit)
   debug
   fatal

 result:
    1 - success
    0 - error

=item netqmail_virgin

Builds and installs a pristine netqmail. This is necessary to resolve a chicken and egg problem. You can't apply the toaster patches (specifically chkuser) against netqmail until vpopmail is installed, and you can't install vpopmail without qmail being installed. After installing this, and then vpopmail, you can rebuild netqmail with the toaster patches.

 Usage:
   $qmail->netqmail_virgin( conf=>$conf, debug=>1);

 arguments required:
    conf - a hash of values from toaster-watcher.conf

 arguments optional:
    package  - the name of the programs tarball, defaults to "netqmail-1.05"
    debug
    fatal

 result:
    qmail installed.


=item queue_process
	
queue_process - Tell qmail to process the queue immediately


=item restart

  $qmail->restart( conf=>$conf )

Use to restart the qmail-send process. It will send qmail-send the TERM signal and then return.


=item send_start

	$qmail->send_start( conf=>$conf ) - Start up the qmail-send process.

After starting up qmail-send, we verify that it's running before returning.


=item send_stop

  $qmail->send_stop( conf=>$conf )

Use send_stop to quit the qmail-send process. It will send qmail-send the TERM signal and then wait until it's shut down before returning. If qmail-send fails to shut down within 100 seconds, then we force kill it, causing it to abort any outbound SMTP sessions that are active. This is safe, as qmail will attempt to deliver them again, and again until it succeeds.


=item service_dir_get

This is necessary because things such as service directories are now in /var/service by default but older versions of my toaster installed them in /service. This will detect and adjust for that.


 Example
   $qmail->service_dir_get( conf=>$conf, prot=>'smtp' );


 arguments required:
   prot is one of these protocols: smtp, pop3, submit, send

 arguments optional:
   conf - a hash of values from toaster-watcher.conf
   debug
   fatal

 result:
    0 - failure
    a directory upon success



=item  smtpd_restart

  $qmail->smtpd_restart( conf=>$conf, prot=>"smtp")

Use smtpd_restart to restart the qmail-smtpd process. It will send qmail-smtpd the TERM signal causing it to exit. It will restart immediately because it's supervised. 



=item  supervise_dir_get

  my $dir = $qmail->supervise_dir_get( conf=>$conf, prot=>"smtp" );

This sub just sets the supervise directory used by the various qmail
services (qmail-smtpd, qmail-send, qmail-pop3d, qmail-submit). It sets
the values according to your preferences in toaster-watcher.conf. If
any settings are missing from the config, it chooses reasonable defaults.

This is used primarily to allow you to set your mail system up in ways
that are a different than mine, like a LWQ install.


=item  supervised_hostname_qmail

Gets/sets the qmail hostname for use in supervise/run scripts. It dynamically creates and returns those hostname portion of said run file such as this one based on the settings in $conf. 

 arguments required:
    prot - the protocol name (pop3, smtp, submit, send)

 arguments optional:

 result:
   an array representing the hostname setting portion of the shell script */run.

 Example result:

	LOCAL=`head -1 /var/qmail/control/me`
	if [ -z "$LOCAL" ]; then
		echo ERROR: /var/service/pop3/run tried reading your hostname from /var/qmail/control/me and failed!
		exit 1
	fi


=item  test_each_rbl

	my $available = $qmail->test_each_rbl( rbls=>$selected, debug=>1 );

We get a list of RBL's in an arrayref, run some tests on them to determine if they are working correctly, and pass back the working ones in an arrayref. 

 arguments required:
   rbls - an arrayref with a list of RBL zones

 arguments optional:
   conf  - conf settings from toaster-watcher.conf
   debug - print status messages

 result:
   an arrayref with the list of the correctly functioning RBLs.


=item  build_send_run

  $qmail->build_send_run( conf=>$conf, file=>$file) ? print "success";

build_send_run generates a supervise run file for qmail-send. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from toaster-watcher.conf. I typically use it like this:

  my $file = "/tmp/toaster-watcher-send-runfile";
  if ( $qmail->build_send_run( conf=>$conf, file=>$file ) )
  {
    $qmail->install_supervise_run( tmpfile=>$file, prot=>"send", conf=>$conf);
    $qmail->restart($conf, $debug);
  };

If it succeeds in building the file, it will install it. You can optionally restart qmail after installing a new run file.

 arguments required:
   conf - as hashref with the contents of toaster-watcher.conf
   file - the temp file to construct

 arguments optional:
   debug
   fatal

 results:
   0 - failure
   1 - success


=item  build_smtp_run

  if ( $qmail->build_smtp_run( conf=>$conf, file=>$file) ) { print "success" };

Generate a supervise run file for qmail-smtpd. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

  my $file = "/tmp/toaster-watcher-smtpd-runfile";
  if ( $qmail->build_smtp_run( conf=>$conf, file=>$file ) )
  {
    $qmail->install_supervise_run( tmpfile=>$file, prot=>"smtp", conf=>$conf);
  };

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

 arguments required:
    conf - as hashref with the contents of toaster-watcher.conf
    file - the temp file to construct

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success
 

=item  build_submit_run

  if ( $qmail->build_submit_run( conf=>$conf, file=>$file ) ) { print "success"};

Generate a supervise run file for qmail-smtpd running on submit. $file is the location of the file it's going to generate. $conf is a list of configuration variables pulled from a config file (see ParseConfigfile). I typically use it like this:

  my $file = "/tmp/toaster-watcher-smtpd-runfile";
  if ( $qmail->build_submit_run( conf=>$conf, file=>$file ) )
  {
    $qmail->install_supervise_run( tmpfile=>$file, prot=>"submit", conf=>$conf);
  };

If it succeeds in building the file, it will install it. You can optionally restart the service after installing a new run file.

 arguments required:
    conf - as hashref with the contents of toaster-watcher.conf
    file - the temp file to construct

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success
 

=item  check_control

Verify the existence of the qmail control directory (typically /var/qmail/control). 

 arguments required:
    dir - the directory whose existence we test for

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success
 

=item  check_rcpthosts

  $qmail->check_rcpthosts($qmaildir);

Checks the control/rcpthosts file and compares its contents to users/assign. Any zones that are in users/assign but not in control/rcpthosts or control/morercpthosts will be presented as a list and you will be expected to add them to morercpthosts.

 arguments required:
    none

 arguments optional:
    dir - defaults to /var/qmail

 result
    instructions to repair any problem discovered.


=item  config

Qmail is nice because it is quite easy to configure. Just edit files and put the right values in them. However, many find that a problem because it is not so easy to always know the syntax for what goes in every file, and exactly where that file might be. This sub takes your values from toaster-watcher.conf and puts them where they need to be. It modifies the following files:

   /var/qmail/control/concurrencyremote
   /var/qmail/control/me
   /var/qmail/control/mfcheck
   /var/qmail/control/spfbehavior
   /var/qmail/control/tarpitcount
   /var/qmail/control/tarpitdelay
   /var/qmail/control/sql
   /var/qmail/control/locals
   /var/qmail/alias/.qmail-postmaster
   /var/qmail/alias/.qmail-root
   /var/qmail/alias/.qmail-mailer-daemon

  FreeBSD specific:
   /etc/rc.conf
   /etc/mail/mailer.conf
   /etc/make.conf

You should not manually edit these files. Instead, make changes in toaster-watcher.conf and allow it to keep them updated.

 Usage:
   $qmail->config( conf=>$conf);

 arguments required:
    conf - as hashref with the contents of toaster-watcher.conf

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success
 

=item  control_create

To make managing qmail a bit easier, we install a control script that allows the administrator to interact with the running qmail processes. 

 Usage:
   $qmail->control_create(conf=>$conf);

 Sample Output
    /usr/local/sbin/qmail {restart|doqueue|flush|reload|stat|pause|cont|cdb|queue|help}

    # qmail help
	        pause -- temporarily stops mail service (connections accepted, nothing leaves)
	        cont -- continues paused mail service
	        stat -- displays status of mail service
	        cdb -- rebuild the cdb files (tcp.smtp, users, simcontrol)
	        restart -- stops and restarts smtp, sends qmail-send a TERM & restarts it
	        doqueue -- sends qmail-send ALRM, scheduling queued messages for delivery
	        reload -- sends qmail-send HUP, rereading locals and virtualdomains
	        queue -- shows status of queue
	        alrm -- same as doqueue
	        hup -- same as reload

 arguments required:
    conf - as hashref with the contents of toaster-watcher.conf

 arguments optional:
    debug
    fatal

 results:
    0 - failure
    1 - success


=item  get_domains_from_assign

Fetch a list of domains from the qmaildir/users/assign file.

  $qmail->get_domains_from_assign( assign=>$assign, debug=>$debug );

 arguments required:
    none

 arguments optional:
    assign - the path to the assign file (default: /var/qmail/users/assign)
    debug
    match - field to match (dom, uid, dir)
    value - the pattern to  match

 results:
    an array


=item  get_list_of_rbls

Gets passed a hashref of values and extracts all the RBLs that are enabled in the file. See the toaster-watcher.conf file and the rbl_ settings therein for the format expected. See also the t/Qmail.t for examples of usage.

  my $r = $qmail->get_list_of_rbls( 
     conf  => $hashref,
     debug => $debug 
  );

 arguments required:
    conf - a hashref of values, usually the contents of toaster-watcher.conf

 arguments optional:
    debug

 result:
   an arrayref of values


=item  get_list_of_rwls

  my $selected = $qmail->get_list_of_rwls( conf=>$conf, debug=>$debug);

Here we collect a list of the RWLs from the configuration file that gets passed to us and return them. 

 arguments required:
    conf - a hashref, typically the contents of toaster-watcher.conf

 arguments optional:
   debug
   fatal

 result:
   an arrayref with the enabled rwls.


=item  install_qmail

Builds qmail and installs qmail with patches (based on your settings in toaster-watcher.conf), installs the SSL certs, adjusts the permissions of several files that need it.

 Usage:
   $qmail->install_qmail( conf=>$conf, debug=>1);

 arguments required:
    conf - a hash of values from toaster-watcher.conf

 arguments optional:
     package  - the name of the programs tarball, defaults to "qmail-1.03"
     debug
     fatal

 result:
     one kick a55 mail server.

Patch info is here: http://www.tnpi.biz/internet/mail/toaster/patches/


=item  install_qmail_control_files

When qmail is first installed, it needs some supervised run files to run under tcpserver and daemontools. This sub generates the qmail/supervise/*/run files based on your settings. Perpetual updates are performed by toaster-watcher.pl. 

  $qmail->install_qmail_control_files( conf=>$conf, debug=>$debug);

 arguments required:
    conf - a hash of values from toaster-watcher.conf

 arguments optional:
    debug
    fatal

 result:
    qmail_supervise/pop3/run
    qmail_supervise/smtp/run
    qmail_supervise/send/run
    qmail_supervise/submit/run



=back

=head1 EXAMPLES

Working examples of the usage of these methods can be found in  t/Qmail.t, toaster-watcher.pl, and toaster_setup.pl. 

 
=head1 DIAGNOSTICS
 
All functions include debugging output which is enabled by default. You can disable the status/debugging messages by calling the functions with debug=>0. The default behavior is to die upon errors. That too can be overriddent by setting fatal=>0. See the tests in t/Qmail.t for code examples.
 

  #=head1 COMMON USAGE MISTAKES


 
=head1 CONFIGURATION AND ENVIRONMENT
 
Nearly all of the configuration options can be manipulated by setting the 
appropriate values in toaster-watcher.conf. After making changes in toaster-watcher.conf,
you can run toaster-watcher.pl and your changes will propagate immediately,
or simply wait a few minutes for them to take effect.


=head1 DEPENDENCIES
 
A list of all the other modules that this module relies upon, including any
restrictions on versions, and an indication whether these required modules are
part of the standard Perl distribution, part of the module's distribution,
or must be installed separately.

    Params::Validate        - from CPAN
    Mail::Toaster           - with package
    Mail::Toaster::Utility  - with package
    Mail::Toaster::Perl     - with package
 

=head1 BUGS AND LIMITATIONS
 
None known. When found, report to author.
Patches are welcome.


=head1 TODO


=head1 SEE ALSO

  Mail::Toaster 
  Mail::Toaster::Conf
  toaster.conf
  toaster-watcher.conf

 http://mail-toaster.org/


=head1 AUTHOR
 
Matt Simerson  (matt@tnpi.net)


=head1 ACKNOWLEDGEMENTS


=head1 LICENCE AND COPYRIGHT
 
Copyright (c) <year> The Network People, Inc. (info@tnpi.net). All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
