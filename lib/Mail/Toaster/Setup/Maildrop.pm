package Mail::Toaster::Setup::Maildrop;

use strict;
use warnings;

use English '-no_match_vars';
use Params::Validate ':all';

use lib 'lib';
use parent 'Mail::Toaster::Base';

sub install {
    my $self  = shift;
    my %p = validate( @_, { $self->get_std_opts },);

    my $ver = $self->conf->{'install_maildrop'} or do {
        $self->audit( "skipping maildrop install, not enabled.");
        return 0;
    };

    my $prefix = $self->conf->{'toaster_prefix'} || "/usr/local";

    if ( $ver eq "port" || $ver eq "1" ) {
        if ( $OSNAME eq "freebsd" ) {
            # pre-installing pcre supresses a dialog
            $self->freebsd->install_port( "pcre",
                    options => '# written by Mail::Toaster
# Options for pcre-8.33
_OPTIONS_READ=pcre-8.33
_FILE_COMPLETE_OPTIONS_LIST=STACK_RECURSION
OPTIONS_FILE_SET+=STACK_RECURSION
',
                    );
            $self->freebsd->install_port( "maildrop", flags => "WITH_MAILDIRQUOTA=1",);
        }
        elsif ( $OSNAME eq "darwin" ) {
            $self->darwin->install_port( "maildrop" );
        }
        $ver = "2.5.0";
    }

    $self->util->find_bin( "maildrop", fatal => 0 )
        or $self->util->install_from_source(
                package => 'maildrop-' . $ver,
                site    => 'http://' . $self->conf->{'toaster_sf_mirror'},
                url     => '/courier',
                targets => [
                    './configure --prefix=' . $prefix . ' --exec-prefix=' . $prefix,
                    'make',
                    'make install-strip',
                    'make install-man'
                ],
                source_sub_dir => 'mail',
            );

    my $etcmail = "$prefix/etc/mail";
    unless ( -d $etcmail ) {
        mkdir( $etcmail, oct('0755') )
          or $self->util->mkdir_system( dir => $etcmail, mode=>'0755' );
    }

    $self->filter();
    $self->imap_subscribe();
    $self->filter_logs();
};

sub filter {
    my $self  = shift;
    my %p = validate( @_, { $self->get_std_opts },);

    my $prefix  = $self->conf->{'toaster_prefix'} || "/usr/local";
    my $logbase = $self->conf->{'qmail_log_base'};

    if ( !$logbase ) {
        $logbase = -d "/var/log/qmail" ? "/var/log/qmail" : "/var/log/mail";
    }

    my $filterfile = $self->conf->{'filtering_maildrop_filter_file'}
      || "$prefix/etc/mail/mailfilter";

    my ( $path, $file ) = $self->util->path_parse($filterfile);

    $self->util->mkdir_system( dir => $path )  if ! -d $path;

    return $self->error( "$path doesn't exist and I couldn't create it.")
        if ! -d $path;

    my @lines = $self->filter_file( logbase => $logbase );

    my $user  = $self->conf->{'vpopmail_user'}  || "vpopmail";
    my $group = $self->conf->{'vpopmail_group'} || "vchkpw";

    # if the mailfilter file doesn't exist, create it
    if ( -e $filterfile ) {
        $self->util->file_write( "$filterfile.new", lines => \@lines, mode  =>'0600' );
        $self->util->install_if_changed(
            newfile  => "$filterfile.new",
            existing => $filterfile,
            mode     => '0600',
            clean    => 0,
            notify   => 1,
            archive  => 1,
        );
    }
    else {
        $self->util->file_write( $filterfile, lines => \@lines, mode  => '0600' );
        $self->audit("installed new $filterfile, ok");
    };

    $self->util->chown( $filterfile, uid => $user, gid => $group );

    $file = "/etc/newsyslog.conf";
    if ( -e $file  && ! `grep maildrop $file`) {
        $self->util->file_write( $file,
            lines =>
            ["/var/log/mail/maildrop.log $user:$group 644	3	1000 *	Z"],
            append => 1,
        );
    };
    return 1;
}

sub filter_file {
    my $self  = shift;
    my %p = validate( @_, { 'logbase' => SCALAR, $self->get_std_opts, },);

    my $logbase = $p{'logbase'};

    my $prefix  = $self->conf->{'toaster_prefix'} || "/usr/local";
    my $filterfile = $self->conf->{'filtering_maildrop_filter_file'}
      || "$prefix/etc/mail/mailfilter";

    my @lines = 'SHELL="/bin/sh"';
    push @lines, <<"EOMAILDROP";
import EXT
import HOST
VHOME=`pwd`
TIMESTAMP=`date "+\%b \%d \%H:\%M:\%S"`

##
#  title:  mailfilter-site
#  author: Matt Simerson
#  version 2.17
#
#  This file is automatically generated by toaster_setup.pl,
#  DO NOT HAND EDIT, your changes may get overwritten!
#
#  Make changes to toaster-watcher.conf, and run
#  toaster_setup.pl -s maildrop to rebuild this file. Old versions
#  are preserved as $filterfile.timestamp
#
#  Usage: Install this file in your local etc/mail/mailfilter. On
#  your system, this is $prefix/etc/mail/mailfilter
#
#  Create a .qmail file in each users Maildir as follows:
#  echo "| $prefix/bin/maildrop $prefix/etc/mail/mailfilter" \
#      > ~vpopmail/domains/example.com/user/.qmail
#
#  You can also use qmailadmin v1.0.26 or higher to do that for you
#  via it is --enable-modify-spam and --enable-spam-command options.
#  This is the default behavior for your Mail::Toaster.
#
# Environment Variables you can import from qmail-local:
#  SENDER  is  the envelope sender address
#  NEWSENDER is the forwarding envelope sender address
#  RECIPIENT is the envelope recipient address, local\@domain
#  USER is user
#  HOME is your home directory
#  HOST  is the domain part of the recipient address
#  LOCAL is the local part
#  EXT  is  the  address extension, ext.
#  HOST2 is the portion of HOST preceding the last dot
#  HOST3 is the portion of HOST preceding the second-to-last dot
#  HOST4 is the portion of HOST preceding the third-to-last dot
#  EXT2 is the portion of EXT following the first dash
#  EXT3 is the portion following the second dash;
#  EXT4 is the portion following the third dash.
#  DEFAULT  is  the  portion corresponding to the default part of the .qmail-... file name
#  DEFAULT is not set if the file name does not end with default
#  DTLINE  and  RPLINE are the usual Delivered-To and Return-Path lines, including newlines
#
# qmail-local will be calling maildrop. The exit codes that qmail-local
# understands are:
#     0 - delivery is complete
#   111 - temporary error
#   xxx - unknown failure
##
EOMAILDROP

    $self->conf->{'filtering_verbose'} ? push @lines, qq{logfile "$logbase/maildrop.log"}
                               : push @lines, qq{#logfile "$logbase/maildrop.log"};

    push @lines, <<'EOMAILDROP2';
log "$TIMESTAMP - BEGIN maildrop processing for $EXT@$HOST ==="

# I have seen cases where EXT or HOST is unset. This can be caused by
# various blunders committed by the sysadmin so we should test and make
# sure things are not too messed up.
#
# By exiting with error 111, the error will be logged, giving an admin
# the chance to notice and fix the problem before the message bounces.

if ( $EXT eq "" )
{
        log "  FAILURE: EXT is not a valid value"
        log "=== END ===  $EXT@$HOST failure (EXT variable not imported)"
        EXITCODE=111
        exit
}

if ( $HOST eq "" )
{
        log "  FAILURE: HOST is not a valid value"
        log "=== END ===  $EXT@$HOST failure (HOST variable not imported)"
        EXITCODE=111
        exit
}

EOMAILDROP2

    my $spamass_method = $self->conf->{'filtering_spamassassin_method'};

    if ( $spamass_method eq "user" || $spamass_method eq "domain" ) {

        push @lines, <<"EOMAILDROP3";
##
# Note that if you want to pass a message larger than 250k to spamd
# and have it processed, you will need to also set spamc -s. See the
# spamc man page for more details.
##

exception {
	if ( /^X-Spam-Status: /:h )
	{
		# do not pass through spamassassin if the message already
		# has an X-Spam-Status header.

		log "Message already has X-Spam-Status header, skipping spamc"
	}
	else
	{
		if ( \$SIZE < 256000 ) # Filter if message is less than 250k
		{
			`test -x $prefix/bin/spamc`
			if ( \$RETURNCODE == 0 )
			{
				log `date "+\%b \%d \%H:\%M:\%S"`" \$PID - running message through spamc"
				exception {
					xfilter '$prefix/bin/spamc -u "\$EXT\@\$HOST"'
				}
			}
			else
			{
				log "   WARNING: no $prefix/bin/spamc binary!"
			}
		}
	}
}
EOMAILDROP3

    }

    push @lines, <<"EOMAILDROP4";
##
# Include any rules set up for the user - this gives the
# administrator a way to override the sitewide mailfilter file
#
# this is also the "suggested" way to set individual values
# for maildrop such as quota.
##

`test -r \$VHOME/.mailfilter`
if( \$RETURNCODE == 0 )
{
	log "   including \$VHOME/.mailfilter"
	exception {
		include \$VHOME/.mailfilter
	}
}

##
# create the maildirsize file if it does not already exist
# (could also be done via "deliverquota user\@dom.com 10MS,1000C)
##

`test -e \$VHOME/Maildir/maildirsize`
if( \$RETURNCODE == 1)
{
	VUSERINFO="$prefix/vpopmail/bin/vuserinfo"
	`test -x \$VUSERINFO`
	if ( \$RETURNCODE == 0)
	{
		log "   creating \$VHOME/Maildir/maildirsize for quotas"
		`\$VUSERINFO -Q \$EXT\@\$HOST`

		`test -s "\$VHOME/Maildir/maildirsize"`
   		if ( \$RETURNCODE == 0 )
   		{
     			`/usr/sbin/chown vpopmail:vchkpw \$VHOME/Maildir/maildirsize`
				`/bin/chmod 640 \$VHOME/Maildir/maildirsize`
		}
	}
	else
	{
		log "   WARNING: cannot find vuserinfo! Please edit mailfilter"
	}
}

EOMAILDROP4

    my $head = $self->util->find_bin( 'head' );

    push @lines, <<"EOMAILDROP5";
##
# Set MAILDIRQUOTA. If this is not set, maildrop and deliverquota
# will not enforce quotas for message delivery.
##

`test -e \$VHOME/Maildir/maildirsize`
if( \$RETURNCODE == 0)
{
	MAILDIRQUOTA=`$head -n1 \$VHOME/Maildir/maildirsize`
}

# if the user does not have a Spam folder, create it.

`test -d \$VHOME/Maildir/.Spam`
if( \$RETURNCODE == 1 )
{

    MAILDIRMAKE="$prefix/bin/maildirmake"
    `test -x \$MAILDIRMAKE`
    if ( \$RETURNCODE == 1 )
    {
        MAILDIRMAKE="$prefix/bin/maildrop-maildirmake"
        `test -x \$MAILDIRMAKE`
    }

    if ( \$RETURNCODE == 1 )
    {
        log "   WARNING: no maildirmake!"
    }
    else
    {
        log "   creating \$VHOME/Maildir/.Spam "
        `\$MAILDIRMAKE -f Spam \$VHOME/Maildir`
        `$prefix/sbin/subscribeIMAP.sh Spam \$VHOME`
    }
}

##
# The message should be tagged, so lets bag it.
##
# HAM:  X-Spam-Status: No, score=-2.6 required=5.0
# SPAM: X-Spam-Status: Yes, score=8.9 required=5.0
#
# Note: SA < 3.0 uses "hits" instead of "score"
#
# if ( /^X-Spam-Status: *Yes/)  # test if spam status is yes
# The following regexp matches any spam message and sets the
# variable \$MATCH2 to the spam score.

if ( /X-Spam-Status: Yes/:h)
{
    if ( /X-Spam-Status: Yes, (hits|score)=([\\d\\.\\-]+)\\s/:h)
    {
EOMAILDROP5

    my $discard   = $self->conf->{'filtering_spama_discard_score'};
    my $pyzor     = $self->conf->{'filtering_report_spam_pyzor'};
    my $sa_report = $self->conf->{'filtering_report_spam_spamassassin'};

    if ($discard) {

        push @lines, <<"EOMAILDROP6";
	# if the message scored a $discard or higher, then there is no point in
	# keeping it around. SpamAssassin already knows it as spam, and
	# has already "autolearned" from it if you have that enabled. The
	# end user likely does not want it. If you wanted to cc it, or
	# deliver it elsewhere for inclusion in a spam corpus, you could
	# easily do so with a cc or xfilter command

        if ( \$MATCH2 >= $discard )   # from Adam Senuik post to mail-toasters
        {
EOMAILDROP6

        if ( $pyzor && !$sa_report ) {

            push @lines, <<"EOMAILDROP7";
            `test -x $prefix/bin/pyzor`
            if( \$RETURNCODE == 0 )
            {
                # if the pyzor binary is installed, report all messages with
                # high spam scores to the pyzor servers

                log "   SPAM: score \$MATCH2: reporting to Pyzor"
                exception {
                    xfilter "$prefix/bin/pyzor report"
                }
            }
EOMAILDROP7
        }

        if ($sa_report) {

            push @lines, <<"EOMAILDROP8";

            # new in version 2.5 of Mail::Toaster mailfiter
            `test -x $prefix/bin/spamassassin`
            if( \$RETURNCODE == 0 )
            {
                # if the spamassassin binary is installed, report messages with
                # high spam scores to spamassassin (and consequently pyzor, dcc,
                # razor, and SpamCop)

                log "   SPAM: score \$MATCH2: reporting spam via spamassassin -r"
                exception {
                    xfilter "$prefix/bin/spamassassin -r"
                }
            }
EOMAILDROP8
        }

        push @lines, <<"EOMAILDROP9";
                log "   SPAM: score \$MATCH2 exceeds $discard: nuking message!"
                log "=== END === \$EXT\@\$HOST success (discarded)"
                EXITCODE=0
                exit
            }
EOMAILDROP9
    }

    push @lines, <<"EOMAILDROP10";
        log "   SPAM: score \$MATCH2: delivering to \$VHOME/Maildir/.Spam"
        log "=== END ===  \$EXT\@\$HOST success"
        exception {
            to "\$VHOME/Maildir/.Spam"
        }
    }
    else
    {
        log "   SpamAssassin regexp match error!"
    }
}

if ( /^X-Spam-Status: No, (score|hits)=([\\d\\.\\-]+)\\s/:h)
{
    log "   message is SA clean (\$MATCH2)"
}

EOMAILDROP10

if ( $self->conf->{install_dspam} ) {

    push @lines, <<"EOMAILDROP_DSPAM";
if ( /^X-DSPAM-Result: /:h )
{
    log "   has X-DSPAM-Result header"
}
else
{
    if ( \$SIZE < 4194304 ) # Filter if message is less than 4MB
    {
        `test -x $prefix/bin/dspam`
        if ( \$RETURNCODE == 0 )
        {
            log `date "+\%b \%d \%H:\%M:\%S"`" \$PID - running message through dspam"
            exception {
                xfilter '$prefix/bin/dspam --user \$EXT\@\$HOST --process --deliver=innocent,spam --stdout'
            }
        }
        else
        {
            log "   WARNING: no $prefix/bin/dspam binary!"
        }
    }
}

##
# Check for DSPAM tag
##
# HAM:  X-DSPAM-Result: Innocent, probability=0.0000, confidence=0.94
# SPAM: X-DSPAM-Result: Spam, probability=1.0000, confidence=0.99
#

if ( /X-DSPAM-Result: /:h)
{
    if ( /X-DSPAM-Result: Spam/:h)
    {
        if ( /X-DSPAM-Result: Spam, probability=([\\d\\.]+), confidence=([\\d\\.]+)/:h)
        {
            if ( \$MATCH1 == 1 && \$MATCH2 >= .50 )
            {
                if ( /^X-Spam-Status: /:h )
                {
                    if ( /X-Spam-Status: Yes/:h)
                    {
                        log "   DSPAM: delivering spam (\$MATCH2) to \$VHOME/Maildir/.Spam"
                        log "=== END ===  \$EXT\@\$HOST success"
                        exception {
                            to "\$VHOME/Maildir/.Spam"
                        }
                    }
                    else
                    {
                        log "   DSPAM says spam (\$MATCH2) SA says no"
                    }
                }
            }
            else
            {
                log "   DSPAM suspects spam (\$MATCH2)"
            }
        }
        else
        {
            log "   DSPAM regexp match error!"
        }
    }
    else
    {
        log "   dspam says innocent"
    }
}

EOMAILDROP_DSPAM
;
};

    push @lines, <<"EOMAILDROP11";
##
# Include any other rules that the user might have from
# sqwebmail or other compatible program
##

`test -r \$VHOME/Maildir/.mailfilter`
if( \$RETURNCODE == 0 )
{
	log "   including \$VHOME/Maildir/.mailfilter"
	exception {
		include \$VHOME/Maildir/.mailfilter
	}
}

`test -r \$VHOME/Maildir/mailfilter`
if( \$RETURNCODE == 0 )
{
	log "   including \$VHOME/Maildir/mailfilter"
	exception {
		include \$VHOME/Maildir/mailfilter
	}
}

log "   delivering to \$VHOME/Maildir"

# make sure the deliverquota binary exists and is executable
# if not, then we cannot enforce quotas. If we do not check
# and the binary is missing, maildrop silently discards mail.

DELIVERQUOTA="$prefix/bin/deliverquota"
`test -x \$DELIVERQUOTA`
if ( \$RETURNCODE == 1 )
{
	DELIVERQUOTA="$prefix/bin/maildrop-deliverquota"
    `test -x \$DELIVERQUOTA`
}

if ( \$RETURNCODE == 1 )
{
    log "   WARNING: no deliverquota!"
    log "=== END ===  \$EXT\@\$HOST success"
    exception {
        to "\$VHOME/Maildir"
    }
}
else
{
	exception {
		xfilter "\$DELIVERQUOTA -w 90 \$VHOME/Maildir"
	}

	##
	# check to make sure the message was delivered
	# returncode 77 means that out maildir was overquota - bounce mail
	##
	if( \$RETURNCODE == 77)
	{
		#log "   BOUNCED: bouncesaying '\$EXT\@\$HOST is over quota'"
		log "=== END ===  \$EXT\@\$HOST  bounced"
		to "|/var/qmail/bin/bouncesaying '\$EXT\@\$HOST is over quota'"
	}
	else
	{
		log "=== END ===  \$EXT\@\$HOST  success (quota)"
		EXITCODE=0
		exit
	}
}

log "WARNING: This message should never be printed!"
EOMAILDROP11

    return @lines;
}

sub filter_logs {
    my $self = shift;

    my $log = $self->conf->{'qmail_log_base'} || "/var/log/mail";

    $self->util->mkdir_system( dir => $log, verbose => 0 ) if ! -d $log;

    $self->util->chown( $log,
        uid   => $self->conf->{'qmail_log_user'}  || 'qmaill',
        gid   => $self->conf->{'qmail_log_group'} || 'qnofiles',
        sudo  => $UID == 0 ? 0 : 1,
    );

    my $logf = "$log/maildrop.log";

    $self->util->file_write( $logf, lines => ["begin"] ) if ! -e $logf;

    $self->util->chown( $logf,
        uid   => $self->conf->{'vpopmail_user'}  || "vpopmail",
        gid   => $self->conf->{'vpopmail_group'} || "vchkpw",
        sudo  => $UID == 0 ? 0 : 1,
    );
}

sub imap_subscribe {
    my $self = shift;
    my $prefix = $self->conf->{'toaster_prefix'} || "/usr/local";
    my $sub_file = "$prefix/sbin/subscribeIMAP.sh";

    my $sub_bin = $self->util->find_bin( "$prefix/sbin/subscribeIMAP.sh", verbose => 0, fatal => 0 );
    return 1 if ( $sub_bin && -e $sub_bin );

    my $chown = $self->util->find_bin( 'chown' );
    my $chmod = $self->util->find_bin( 'chmod' );

    my @lines = '#!/bin/sh
#
# This subscribes the folder passed as $1 to courier imap
# so that Maildir reading apps (Sqwebmail, Courier-IMAP) and
# IMAP clients (squirrelmail, Mailman, etc) will recognize the
# extra mail folder.

# Matt Simerson - 12 June 2003

LIST="$2/Maildir/courierimapsubscribed"

if [ -f "$LIST" ]; then
	# if the file exists, check it for the new folder
	TEST=`cat "$LIST" | grep "INBOX.$1"`

	# if it is not there, add it
	if [ "$TEST" = "" ]; then
		echo "INBOX.$1" >> $LIST
	fi
else
	# the file does not exist so we define the full list
	# and then create the file.
	FULL="INBOX\nINBOX.Sent\nINBOX.Trash\nINBOX.Drafts\nINBOX.$1"

	echo -e $FULL > $LIST
	' . $chown . ' vpopmail:vchkpw $LIST
	' . $chmod . ' 644 $LIST
fi
';

    $self->util->file_write( $sub_file, lines => \@lines );

    $self->util->chmod(
        file_or_dir => $sub_file,
        mode        => '0555',
        sudo        => $UID == 0 ? 0 : 1,
    );
};

1;
__END__;

