#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: toaster-watcher.pl, matt Exp $
#

use vars qw/$VERSION/;

$VERSION = "5.06";

use lib "lib";  

use Mail::Toaster::Utility 5; my $utility = Mail::Toaster::Utility->new();    
use Mail::Toaster::Qmail   5; my $qmail = Mail::Toaster::Qmail->new();
use Mail::Toaster          5; my $toaster = Mail::Toaster->new();

use vars qw/ $opt_d $opt_v $file /;
use Carp;
use English qw( -no_match_vars );
use Getopt::Std;
getopts('dv');

$|++;

# this script must be run as root
if ( $UID != 0 ) { 
    croak "Thou shalt have root to proceed!\n"; 
};

my $pidfile = "/var/run/toaster-watcher.pid";
if ( ! $utility->pidfile_check( pidfile => $pidfile, fatal=>0, debug=>0 ) ) {
    carp "Another toaster-watcher is running,  I refuse to!\n";
    exit 500;
};

my $conf = $utility->parse_config( file => "toaster-watcher.conf", debug => 0 );
my $debug = $conf->{'toaster_debug'} || $opt_d || 0;

if ($opt_v) { $debug = 1; print "$0 v$VERSION\n"; }

my $logfile = $conf->{'toaster_watcher_log'};
if ($logfile) {
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Starting up"],
        fatal => 0,
        debug => $debug,
    );
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Running toaster_check"],
        fatal => 0,
        debug => $debug,
    );
}

$qmail->config( 
    conf       => $conf, 
    first_time => 0,
    debug      => $debug,
);

print "generating send/run..." if $debug;
$utility->logfile_append(
    file  => $logfile,
    prog  => "watcher",
    lines => ["Building send/run"],
    debug => 0,
)                              if $logfile;

$file = "/tmp/toaster-watcher-send-runfile";
if ( $qmail->build_send_run( conf => $conf, file => $file, debug => $debug ) ) {
    print "success.\n" if $debug;
    if (
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => 'send',
            debug   => 0,
            conf    => $conf
        ) == 1
      )
    {
        $qmail->restart( conf=>$conf, debug=>$debug );
    }
}
else { print "FAILED.\n" if $debug; }

# if qpop3d is our selected pop3 daemon ...
if ( $conf->{'pop3_daemon'} eq "qpop3d" ) {
    print "generating pop3/run..." if $debug;
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Building pop3/run"],
        debug => 0,
    ) if $logfile;

    $file = "/tmp/toaster-watcher-pop3-runfile";
    if ( $qmail->build_pop3_run( conf => $conf, file => $file, debug => $debug )
      )
    {
        print "success.\n" if $debug;
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => 'pop3',
            debug   => $debug,
            conf    => $conf,
        );
    }
    else { print "FAILED.\n" if $debug; }
}

print "generating smtp/run..." if $debug;
$utility->logfile_append(
    file  => $logfile,
    prog  => "watcher",
    lines => ["Building smtp/run"],
    debug => 0,
) if $logfile;

$file = "/tmp/toaster-watcher-smtpd-runfile";

if ( $qmail->build_smtp_run( conf => $conf, file => $file, debug => $debug ) ) {
    print "success.\n" if $debug;
    if (
        $qmail->install_supervise_run(
            tmpfile => $file,
            prot    => 'smtp',
            debug   => $debug,
            conf    => $conf
        )
      )
    {
        $qmail->smtpd_restart( conf => $conf, prot => "smtp", debug => $debug );
    }
}
else { print "FAILED.\n" if $debug; }

if ( $conf->{'submit_enable'} ) {
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Building submit/run"],
        debug => 0,
    )                                if $logfile;
    print "generating submit/run..." if $debug;

    $file = "/tmp/toaster-watcher-submit-runfile";
    if (
        $qmail->build_submit_run(
            conf  => $conf,
            file  => $file,
            debug => $debug,
        )
      )
    {
        print "success.\n" if $debug;
        if (
            $qmail->install_supervise_run(
                tmpfile => $file,
                prot    => 'submit',
                debug   => $debug,
                conf    => $conf,
            )
          )
        {
            $qmail->smtpd_restart(
                conf  => $conf,
                prot  => "submit",
                debug => $debug,
            );
        }
    }
    else { print "FAILED.\n" if $debug; }
}

$toaster->toaster_check( conf=>$conf, debug=>$debug );
$toaster->service_symlinks( conf=>$conf, debug=>$debug );

if ( $conf->{'vpopmail_roaming_users'} ) {
    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    if ( -x "$vpopdir/bin/clearopensmtp" ) {
        print "running clearopensmtp..." if $debug;
        $utility->syscmd( command => "$vpopdir/bin/clearopensmtp", debug=>$debug );
        print "done.\n " if $debug;
    }
    else {
        print "ERROR: I cannot find your clearopensmtp program!\n";
    }
}

if ( $conf->{'install_isoqlog'} ) {
    my $isoqlog = $utility->find_the_bin( bin => "isoqlog", debug=>0 );
    if ( -x $isoqlog ) {
        $utility->syscmd( command => "$isoqlog >/dev/null", debug=>$debug );
    }
}

if ( $conf->{'install_rrdutil'} ) {
    print "trigger rrdutil from here, maybe...\n" if $debug;

    # must test this a bit first
}

if ( $conf->{'install_qmailscanner'} && $conf->{'qs_quarantine_process'} ) {
    print "checking qmail-scanner quarantine.\n" if $debug;
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Processing the qmail-scanner quarantine"],
        debug => 0,
    ) if $logfile;

    my $qs_debug = $conf->{'qs_quarantine_verbose'};
    if ( $debug && !$qs_debug ) { $qs_debug++ }

    my @list = $qmail->get_qmailscanner_virus_sender_ips( $conf, $qs_debug );

    my $count = @list;
    if ( $count && $qs_debug ) {
        print "\nfound $count infected files\n\n";
    }

    if ( $conf->{'qs_block_virus_senders'} ) {
        $qmail->UpdateVirusBlocks( conf => $conf, ips => \@list );
    }
}

if ( $conf->{'maildir_clean_interval'} ) {
    print "cleaning mailbox messages..." if ($debug);
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["Cleaning mailbox messages"],
        debug => 0,
    ) if $logfile;

    $toaster->clean_mailboxes( conf => $conf, debug => $debug );
    print "done.\n" if ($debug);
}

if ( $conf->{'maildir_learn_interval'} ) {
    print "learning mailbox messages..." if ($debug);
    $utility->logfile_append(
        file  => $logfile,
        prog  => "watcher",
        lines => ["learning mailbox messages"],
        debug => 0,
    ) if $logfile;

    $toaster->learn_mailboxes( conf => $conf, debug => $debug );
    print "done.\n" if ($debug);
}

# rebuild ssl temp keys for qmail
$utility->logfile_append(
    file  => $logfile,
    prog  => "watcher",
    lines => ["rebuilding SSL temp keys"],
    debug => 0,
) if $logfile;
$qmail->rebuild_ssl_temp_keys( conf => $conf, debug => 0 );

if ( -x "/var/qmail/bin/simscanmk" ) {

    # this needs to be done, but quietly
    #	$utility->syscmd( command=>"/var/qmail/bin/simscanmk" );
    #	$utility->syscmd( command=>"/var/qmail/bin/simscanmk -g" );
}

unlink $pidfile;
$utility->logfile_append(
    file  => $logfile,
    prog  => "watcher",
    lines => ["Exiting\n"],
    debug => 0,
) if $logfile;

exit 0;

__END__


=head1 NAME

toaster-watcher.pl - monitors and configure various aspects of a qmail toaster


=head1 SYNOPSIS

toaster-watcher does several unique and important things. First, it includes a configuration file that stores settings about your mail system. You configure it to suit your needs and it goes about making sure all the settings on your system are as you selected. Various other scripts (like toaster_setup.pl) and programs use this configuration file to determine how to configure themselves and other parts of the mail toaster solution.

The really cool part about toaster-watcher.pl is that it dynamically builds the run files for your qmail daemons (qmail-smtpd, qmail-send, and qmail-pop3). You choose all your settings in toaster-watcher.conf and toaster-watcher.pl builds your run files for you, on the fly. It tests the RBL's you've selected to use, and builds a control file based on your settings and dynamic information such as the availability of the RBLs you want to use.


=head1 DESCRIPTION

=head1 SUBROUTINES

=over

=item build_send_run

We first build a new $service/send/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.


=item build_pop3_run

We first build a new $service/pop3/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.


=item build_smtp_run

We first build a new $service/smtp/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.


=item build_submit_run

We first build a new $service/submit/run file based on your settings in 
toaster-watcher.conf. There are a ton of configuration options, be sure
to check out the docs for toaster-watcher.conf. 

If the new generated file is different than the installed version, we 
install the updated run file and restart the daemon.


=item Clear Open SMTP

This script runs the clearopensmtp program which expires old ip addresses from the vpopmail smtp relay table. It will only run if you have vpopmail_roaming_users enabled in toaster-watcher.conf.


=item Isoqlog

If you have isoqlog installed, you'll want to have it running frequently. I suggest running it from here, or from crondirectly.


=item Qmail-Scanner Quarantine Processing

Qmail-Scanner quarantines any files that fail certain tests, such as banned attachments, Virus laden messages, etc. The messages get left laying around in the quarantine until someone does something about it. If you enable this feature, toaster-watcher.pl will go through the quarantine and deal with messages as you see fit.

I have mine configured to block the IP (for 24 hours) of anyone that's sent me a virus and delete the quarantined message. I run toaster-watcher.pl from cron every 5 minutes so this usually keeps virus infected hosts from sending me another virus laden message for at least 24 hours, after which we hope the owner of the system has cleaned up his computer.


=item Maildir Processing

Many times its useful to have a script that cleans up old mail messages on your mail system and enforces policy. Now toaster-watcher.pl does that. You tell it how often to run (I use every 7 days), what mail folders to clean (Inbox, Read, Unread, Sent, Trash, Spam), and then how old the messaged need to be before you remove them. 

I have my system set to remove messages in Sent folders more than 180 days old and messages in Trash and Spam folders that are over 14 days old. I have also instructed toaster-watcher to feed any messages in my Spam and Read folders that are more than 1 day old through sa-learn. That way I train SpamAssassin by merely moving my messages into appropriate folders.


=back

=head1 TODO

Optionally send an email notification to an admin if a file gets updated. Make this
configurable on a per service basis. I can imagine wanting to know if pop3/run or send/run ever
changed but I don't care to get emailed every time a RBL fails a DNS check.

Feature request by David Chaplin-Leobell: check for low disk space on the queue and
mail delivery partitions.  If low disk is detected, it could either just
notify the administrator, or it could do some cleanup of things like the
qmail-scanner quarantine folder.


=head1 AUTHOR

Matt Simerson <matt@tnpi.net>


=head1 DEPENDENCIES

This module requires these other modules and libraries:

Net::DNS


=head1 SEE ALSO

http://mail-toaster.org/

=head1 ACKNOWLEDGEMENTS

Thanks to Randy Ricker, Anton Zavrin, Randy Jordan, Arie Gerszt, Joe Kletch, and Marius Kirschner for contributing to the development of this script.


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004-2007, The Network People, Inc.  All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

