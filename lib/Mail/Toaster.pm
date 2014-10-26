package Mail::Toaster;

use strict;
use warnings;

our $VERSION = '5.26';

use Cwd;
use English qw/ -no_match_vars /;
use Params::Validate qw/ :all /;
use Sys::Hostname;
use version;

use vars qw/ $INJECT $util $conf $log $qmail %std_opts /;

sub new {
    my $class = shift;
    my %p = validate( @_, { 
            test_ok => { type => BOOLEAN, optional => 1 },
            debug   => { type => BOOLEAN, optional => 1, default => 1 },
            fatal   => { type => BOOLEAN, optional => 1, default => 1 },
        }
    );

    my $self = { 
        audit  => [],
        errors => [],
        last_audit => 0,
        last_error => 0,
        conf   => undef,
        util   => undef,
        debug  => $p{debug},
        fatal  => $p{fatal},
    };
    bless( $self, $class );

    $log  = $self;
    $self->{util} = $util = $self->get_util();

    %std_opts = (
        test_ok => { type => BOOLEAN, optional => 1 },
        debug   => { type => BOOLEAN, optional => 1, default => $self->{debug} },
        fatal   => { type => BOOLEAN, optional => 1, default => $self->{fatal} },
    );

    my @caller = caller;
    warn sprintf( "Toaster.pm loaded by %s, %s, %s\n", @caller )
        if $caller[0] ne 'main';
    return $self;
}

sub audit {
    my $self = shift;
    my $mess = shift; 

    my %p = validate( @_, { %std_opts, }, );

    if ($mess) {
        push @{ $self->{audit} }, $mess;
        print "$mess\n" if $self->{debug} || $p{debug};
    } 

    return \$self->{audit};
}   

sub error {
    my $self = shift;
    my $message = shift;
    my %p = validate(
        @_,
        {   location => { type => SCALAR,  optional => 1, },
            %std_opts,
        }, 
    );

    my $location = $p{location};
    my $debug = $p{debug};
    my $fatal = $p{fatal};

    if ( $message ) {
        my @caller = caller;

        # append message and location to the error stack
        push @{ $self->{errors} },
            {
            errmsg => $message,
            errloc => $location || join( ", ", $caller[0], $caller[2] ),
            };
    }
    else {
        $message = @{ $self->{errors} }[-1];
    }

    if ( $debug || $fatal ) {
        $self->dump_audit();
        $self->dump_errors();
    }

    exit 1 if $fatal;
    return;
}

sub dump_audit {
    my $self = shift;
    my %p = validate( @_, { 
        quiet => { type => SCALAR, optional=> 1, default => 0 },
    } );

    my $audit = $self->{audit};
    return if $self->{last_audit} == scalar @$audit; # nothing new

    if ( $p{quiet} ) {   # hide/mask unreported messages
        $self->{last_audit} = scalar @$audit;
        $self->{last_error} = scalar @{ $self->{errors}};
        return 1;
    };

    print "\n\t\t\tAudit History Report \n\n";
    for( my $i = $self->{last_audit}; $i < scalar @$audit; $i++ ) {
        print "   $audit->[$i]\n";
        $self->{last_audit}++;
    };
    return 1;
};

sub dump_errors {
    my $self = shift;
    my $last_line = $self->{last_error};

    return if $last_line == scalar @{ $self->{errors} }; # everything dumped

    print "\n\t\t\t Error History Report \n\n";
    my $i = 0;
    foreach ( @{ $self->{errors} } ) {
        $i++;
        next if $i < $last_line;
        my $msg = $_->{errmsg};
        my $loc = " at $_->{errloc}";
        print $msg;
        for (my $j=length($msg); $j < 90-length($loc); $j++) { print '.'; };
        print " $loc\n";
    };
    print "\n";
    $self->{last_error} = $i;
    return;
};

sub log {
    my $self = shift;
    my $mess = shift or return;

    my $logfile = $conf->{'toaster_watcher_log'} or return;
    return if ( -e $logfile && ! -w $logfile );

    $util->logfile_append(
        file  => $logfile,
        lines => [$mess],
        fatal => 0,
    );
};

sub test {
    my $self = shift;
    my $mess = shift or return;
    my $result = shift;

    my %p = validate(@_, { %std_opts,
            quiet => { type => SCALAR|UNDEF, optional => 1 },
        } );
    return if ( defined $p{test_ok} && ! $p{debug} );
    return if ( $p{quiet} && ! $p{debug} );

    print $mess;
    defined $result or do { print "\n"; return; };
    for ( my $i = length($mess); $i <=  65; $i++ ) { print '.'; };
    print $result ? 'ok' : 'FAILED', "\n";
};

sub find_config {
    my $self = shift;
    my %p = validate(
        @_,
        {   file   => { type => SCALAR, },
            etcdir => { type => SCALAR | UNDEF, optional => 1, },
            %std_opts,
        }
    );

#my @caller = caller;
#warn sprintf( "Toaster->find_config loaded by %s, %s, %s\n", @caller );

    my $file   = $p{file};
    my $etcdir = $p{etcdir};

    $log->audit("find_config: searching for $file");

    return $self->find_readable( $file, $etcdir ) if $etcdir;

    my @etc_dirs;
    push @etc_dirs, $etcdir if $etcdir;
    push @etc_dirs, qw{ /opt/local/etc /usr/local/etc /etc etc };
    push @etc_dirs, cwd;

    my $r = $self->find_readable( $file, @etc_dirs );
    if ( $r  ) {
        $log->audit( "  found $r" );
        return $r;
    };

    # try $file-dist in the working dir
    if ( -r "./$file-dist" ) {
        $log->audit("  found in ./");
        return cwd . "/$file-dist";
    }

    return $self->error( "could not find $file", fatal => $p{fatal} );
}

sub find_readable {
    my $self = shift;
    my $file = shift;
    my $dir  = shift or return;   # break recursion at end of @_

    #$log->audit("looking for $file in $dir") if $self->{debug};
    if ( -r "$dir/$file" ) {
        no warnings;
        return "$dir/$file";       # success
    }

    if ( -d $dir ) {

        # warn about directories we don't have read access to
        if ( !-r $dir ) {
            $self->error( "$dir is not readable", fatal => 0 );
        }
        else {

            # warn about files that exist but aren't readable
            $self->error( "$dir/$file is not readable", fatal => 0)
                if -e "$dir/$file";
        }
    }

    return $self->find_readable( $file, @_ );
}

sub has_module {
    my $self = shift;
    my ($name, $ver) = @_;

## no critic ( ProhibitStringyEval )
    eval "use $name" . ($ver ? " $ver;" : ";");
## use critic

    !$EVAL_ERROR;
};

sub parse_config {
    my $self = shift;
    my %p = validate( @_, {
            file   => { type=>SCALAR, },
            etcdir => { type=>SCALAR,  optional=>1, },
            %std_opts,
        },
    );

    my %args = ( debug => $p{debug}, fatal => $p{fatal} );
    my $file  = $p{file};
    my $etc   = $p{etcdir};

    if ( ! -f $file ) {
        $file = $self->find_config( file => $file, etcdir => $etc, %args );
    };

    if ( ! $file || ! -r $file ) {
        return $self->error( "could not find config file!", %args);
    };

    my %hash;
    $log->audit( "  read config from $file");

    my @config = $util->file_read( $file );
    foreach ( @config ) {
        next if ! $_;
        chomp;
        next if $_ =~ /^#/;          # skip lines beginning with #
        next if $_ =~ /^[\s+]?$/;    # skip empty lines

        my ( $key, $val ) = $self->parse_line( $_ );

        next if ! $key;
        $hash{$key} = $val;
    }

    return \%hash;
}

sub parse_line {
    my $self = shift;
    my $line = shift;
    my %p = validate( @_, {
            strip => { type => BOOLEAN, optional=>1, default=>1 },
        },
    );

    my $strip = $p{strip};

    # this regexp must match and return these patterns
    # localhost1  = localhost, disk, da0, disk_da0
    # hosts   = localhost lab.simerson.net seattle.simerson.net
            
    my ( $key, $val ) = $line =~ /\A
        \s*      # any amount of leading white space, greedy
        (.*?)    # all characters, non greedy
        \s*      # any amount of white space, greedy
        =
        \s*      # same, except on the other side of the =
        (.*?)
        \s*
        \z/xms;
    
    # remove any comments
    if ( $strip && $val && $val =~ /#/ ) {

        # removes everything from a # to the right, including
        # any spaces to the left of the # symbol.
        ($val) = $val =~ /(.*?\S)\s*#/;
    }
        
    return ( $key, $val );
}
 
sub check {
    my $self = shift;
    my %p = validate( @_, { %std_opts,
        quiet => { type => SCALAR, optional => 1, default=>0 },
    } );
    my %args = $self->get_std_args( %p );
    my %targs = ( %args, quiet => $p{quiet} );

    $conf ||= $self->get_config();

    $self->check_permissions( %args );
    $self->check_processes( %targs );
    $self->check_watcher_log_size( %args );

    # check that we can't SMTP AUTH with random user names and passwords

    # make sure the supervised processes are configured correctly.
    $self->supervised_dir_test( prot=>"smtp",  %targs );
    $self->supervised_dir_test( prot=>"send",  %targs );
    $self->supervised_dir_test( prot=>"pop3",  %targs );
    $self->supervised_dir_test( prot=>"submit",%targs );
    
    return 1;
}

sub check_permissions {
    my $self = shift;
    my %p = validate( @_, { %std_opts, },);

    $conf ||= $self->get_config();

    # check permissions on toaster-watcher.conf
    my $etc = $conf->{'system_config_dir'} || '/usr/local/etc';
    my $twconf = "$etc/toaster-watcher.conf";
    if ( -f $twconf ) {
        my $mode = $util->file_mode( file=>$twconf, debug=>0 );
        $log->audit( "file mode of $twconf is $mode.", %p);
        my $others = substr($mode, -1, 1);
        if ( $others > 0 ) {
            chmod 0600, $twconf;
            $log->audit( "Changed the permissions on $twconf to 0600" );
        }
    };

    # check permissions on toaster.conf
    $twconf = "$etc/toaster.conf";
    if ( -f $twconf ) {
        my $mode = $util->file_mode(file=>$twconf, debug=>0);
        $log->audit( "file mode of $twconf is $mode", %p);
        my $others = substr($mode, -1, 1);
        if ( ! $others ) {
            chmod 0644, $twconf;
            $log->audit( "Changed the permissions on $twconf to 0644");
        }
    };
};

sub check_processes {
    my $self = shift;
    my %p = validate( @_, { %std_opts,
        quiet => { type => SCALAR, optional => 1 },
    } );
    my %args = $self->get_std_args( %p );
    my %targs = ( %args, quiet => $p{quiet} );

    $conf ||= $self->get_config();
    
    $log->audit( "checking running processes");

    my @processes = qw( svscan qmail-send );

    push @processes, "httpd"              if $conf->{'install_apache'};
    push @processes, "mysqld"             if $conf->{'install_mysqld'};
    push @processes, "snmpd"              if $conf->{'install_snmp'};
    push @processes, "clamd", "freshclam" if $conf->{'install_clamav'};
    push @processes, "sqwebmaild"         if $conf->{'install_sqwebmail'};
    push @processes, "imapd-ssl", "imapd", "pop3d-ssl"
      if $conf->{'install_courier-imap'};
      
    push @processes, "authdaemond"
      if ( $conf->{'install_courier_imap'} eq "port"
        || $conf->{'install_courier_imap'} > 4 );

    push @processes, "sendlog"
      if ( $conf->{'send_log_method'} eq "multilog"
        && $conf->{'send_log_postprocessor'} eq "maillogs" );

    push @processes, "smtplog"
      if ( $conf->{'smtpd_log_method'} eq "multilog"
        && $conf->{'smtpd_log_postprocessor'} eq "maillogs" );

    foreach (@processes) {
        $self->test( "  $_", $util->is_process_running($_), %targs );
    }
    
    return 1;
}

sub check_watcher_log_size {
    my $self = shift;

    $conf ||= $self->get_config();

    my $logfile = $conf->{'toaster_watcher_log'} or return;
    return if ! -e $logfile;

    # make sure watcher.log is not larger than 1MB
    my $size = ( stat($logfile) )[7];
    if ( $size > 999999 ) {
        $log->audit( "compressing $logfile! ($size)");
        $util->syscmd( "gzip -f $logfile" );
    }
};

sub learn_mailboxes {
    my $self = shift;
    my %p = validate( @_, {
            fatal   => { type=>BOOLEAN, optional=>1, default=>1 },
            debug   => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug ) = ( $p{fatal}, $p{debug} );
    my %args = ( debug => $p{debug}, fatal => $p{fatal} );

    my $days = $conf->{'maildir_learn_interval'} or return $log->error(
        'email spam/ham learning is disabled because maildir_learn_interval is not set in \$conf', fatal => 0 );

    my $log_base = $conf->{'qmail_log_base'} || '/var/log/mail';
    my $learn_log = "$log_base/learn.log";
    $log->audit( "learn log file is: $learn_log");

    return $p{test_ok} if defined $p{test_ok};

    # create the log file if it does not exist
    $util->logfile_append( %args,
        file  => $learn_log,
        prog  => $0,
        lines => ["created file"],
    )
    if ! -e $learn_log;

    return $log->audit( "skipping message learning, $learn_log is less than $days old")
        if -M $learn_log <= $days;
    
    $util->logfile_append(
        file  => $learn_log,
        prog  => $0,
        lines => ["learn_mailboxes running."],
        %args,
    ) or return;
    
    my $tmp      = $conf->{'toaster_tmp_dir'} || "/tmp";
    my $hamlist  = "$tmp/toaster-ham-learn-me";
    my $spamlist = "$tmp/toaster-spam-learn-me";
    unlink $hamlist  if -e $hamlist;
    unlink $spamlist if -e $spamlist;

    my @every_maildir_on_server = $self->get_maildir_paths();
    foreach my $maildir (@every_maildir_on_server) {
        next if ( ! $maildir || ! -d $maildir );
        $log->audit( "processing in $maildir");
        $self->build_ham_list( path =>$maildir ) if $conf->{'maildir_learn_Read'};
        $self->build_spam_list( path => $maildir ) if $conf->{'maildir_learn_Spam'};
    };

    my $nice    = $util->find_bin( "nice" );
    my $salearn = $util->find_bin( "sa-learn" );

    $util->syscmd( "$nice $salearn --ham -f $hamlist", %args )
        if -s $hamlist;
    unlink $hamlist;
    
    $util->syscmd( "$nice $salearn --spam -f $spamlist", %args )
        if -s $spamlist;
    unlink $spamlist;
}

sub clean_mailboxes {
    my $self = shift;
    my %p = validate( @_, {
            fatal   => { type=>BOOLEAN, optional=>1, default=>1 },
            debug   => { type=>BOOLEAN, optional=>1, default=>1 },
            test_ok => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug ) = ( $p{fatal}, $p{debug} );
    my %args = ( debug => $p{debug}, fatal => $p{fatal} );

    return $p{test_ok} if defined $p{test_ok};

    my $days = $conf->{'maildir_clean_interval'} or 
        return $log->error( 'skipping maildir cleaning, maildir_clean_interval not set in $conf', fatal => 0 );

    my $log_base = $conf->{'qmail_log_base'} || '/var/log/mail';
    my $clean_log = "$log_base/clean.log";
    $log->audit( "clean log file is: $clean_log") if $debug;

    # create the log file if it does not exist
    if ( ! -e $clean_log ) {
        $util->file_write( $clean_log, lines => ["created file"], %args );
        return if ! -e $clean_log;
    }

    if ( -M $clean_log <= $days ) {
        $log->audit( "skipping, $clean_log is less than $days old") if $debug;
        return 1;
    }

    $util->logfile_append(
        file  => $clean_log,
        prog  => $0,
        lines => ["clean_mailboxes running."],
        %args,
    ) or return;
        
    $log->audit( "checks passed, cleaning");

    my @every_maildir_on_server = 
        $self->get_maildir_paths( debug=>$debug );

    foreach my $maildir (@every_maildir_on_server) {
        
        if ( ! $maildir || ! -d $maildir ) {
            $log->audit( "$maildir does not exist, skipping!");
            next;
        };

        $log->audit( "  processing $maildir");

        $self->maildir_clean_ham( path=>$maildir );
        $self->maildir_clean_new( path=>$maildir );
        $self->maildir_clean_sent( path=>$maildir );
        $self->maildir_clean_trash( path=>$maildir );
        $self->maildir_clean_spam( path=>$maildir );
    };

    return 1;
}

sub clear_open_smtp {
    my $self = shift;
    
    return if ! $conf->{'vpopmail_roaming_users'};

    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

    if ( ! -x "$vpopdir/bin/clearopensmtp" ) {
        return $log->error( "cannot find clearopensmtp program!",fatal=>0 );
    };

    $log->audit( "running clearopensmtp");
    $util->syscmd( "$vpopdir/bin/clearopensmtp" );
};

sub maildir_clean_spam {
    my $self = shift;
    my %p = validate( @_, { path  => { type=>SCALAR } } );

    my $path = $p{path};
    my $days = $conf->{'maildir_clean_Spam'} or return;
    my $spambox = "$path/Maildir/.Spam";

    return $log->error( "clean_spam: skipped because $spambox does not exist.",fatal=>0)
        if !-d $spambox;

    $log->audit( "clean_spam: cleaning spam messages older than $days days." );

    my $find = $util->find_bin( 'find' );
    $util->syscmd( "$find $spambox/cur -type f -mtime +$days -exec rm {} \\;" );
    $util->syscmd( "$find $spambox/new -type f -mtime +$days -exec rm {} \\;" );
};

sub build_spam_list {
    my $self = shift;
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    my $spam = "$path/Maildir/.Spam";
    unless ( -d $spam ) {
        $log->audit( "skipped spam learning because $spam does not exist.");
        return;
    }

    my $find = $util->find_bin( "find", debug=>0 );
    my $tmp  = $conf->{'toaster_tmp_dir'};
    my $list = "$tmp/toaster-spam-learn-me";

    $log->audit( "build_spam_list: finding new spam to recognize.");

    # how often do we process spam?  It's not efficient (or useful) to feed spam
    # through sa-learn if we've already learned from them.

    my $interval = $conf->{'maildir_learn_interval'} || 7;    # default 7 days
       $interval = $interval + 2;

    my @files = `$find $spam/cur -type f -mtime +1 -mtime -$interval;`;
    push @files, `$find $spam/new -type f -mtime +1 -mtime -$interval;`;
    chomp @files;
    $util->file_write( $list, lines => \@files, append=>1 );
}

sub maildir_clean_trash {
    my $self = shift;
    my %p = validate( @_, { 'path' => { type=>SCALAR  } } );

    my $path = $p{path};
    my $trash = "$path/Maildir/.Trash";
    my $days = $conf->{'maildir_clean_Trash'} or return;

    return $log->error( "clean_trash: skipped because $trash does not exist.", fatal=>0)
        if ! -d $trash;

    $log->audit( "clean_trash: cleaning deleted messages older than $days days");

    my $find = $util->find_bin( "find" );
    $util->syscmd( "$find $trash/new -type f -mtime +$days -exec rm {} \\;");
    $util->syscmd( "$find $trash/cur -type f -mtime +$days -exec rm {} \\;");
}

sub maildir_clean_sent {
    my $self = shift;
    my %p = validate( @_, { 'path' => { type=>SCALAR,  }, },);

    my $path = $p{path};
    my $sent = "$path/Maildir/.Sent";
    my $days = $conf->{'maildir_clean_Sent'} or return;

    if ( ! -d $sent ) {
        $log->audit("clean_sent: skipped because $sent does not exist.");
        return 0;
    }

    $log->audit( "clean_sent: cleaning sent messages older than $days days");

    my $find = $util->find_bin( "find", debug=>0 );
    $util->syscmd( "$find $sent/new -type f -mtime +$days -exec rm {} \\;");
    $util->syscmd( "$find $sent/cur -type f -mtime +$days -exec rm {} \\;");
}

sub maildir_clean_new {
    my $self = shift;
    my %p = validate( @_, { 'path' => { type=>SCALAR,  }, },);

    my $path = $p{path};
    my $unread = "$path/Maildir/new";
    my $days = $conf->{'maildir_clean_Unread'} or return;

    if ( ! -d $unread ) {
        $log->audit( "clean_new: skipped because $unread does not exist.");
        return 0;
    }

    my $find = $util->find_bin( "find", debug=>0 );
    $log->audit( "clean_new: cleaning unread messages older than $days days");
    $util->syscmd( "$find $unread -type f -mtime +$days -exec rm {} \\;" );
}

sub maildir_clean_ham {
    my $self = shift;
    my %p = validate( @_, { 'path' => { type=>SCALAR, }, }, );

    my $path = $p{path};
    my $read = "$path/Maildir/cur";
    my $days = $conf->{'maildir_clean_Read'} or return;
    
    if ( ! -d $read ) {
        $log->audit( "clean_ham: skipped because $read does not exist.");
        return 0;
    }

    $log->audit( "clean_ham: cleaning read messages older than $days days");
    my $find = $util->find_bin( "find", debug=>0 );
    $util->syscmd( "$find $read -type f -mtime +$days -exec rm {} \\;" );
}

sub build_ham_list {
    my $self = shift;
    my %p = validate( @_, { 'path' => { type=>SCALAR } } );
    my $path = $p{'path'};
    
    return $log->error( "learn_ham: $path/Maildir/cur does not exist!",fatal=>0)
        unless -d "$path/Maildir/cur";

    my $tmp  = $conf->{'toaster_tmp_dir'};
    my $list = "$tmp/toaster-ham-learn-me";
    my $find = $util->find_bin( "find" );
    my $interval = $conf->{'maildir_learn_interval'} || 7;
       $interval = $interval + 2;
    my $days     = $conf->{'maildir_learn_Read_days'};
    my @files;

    if ($days) {
        $log->audit( "learning read INBOX messages older than $days days as ham ($path)");
        push @files, `$find $path/Maildir/cur -type f -mtime +$days -mtime -$interval;`;
    }

    foreach my $folder ( "$path/Maildir/.read", "$path/Maildir/.Read" ) {
        $log->audit( "learning read messages as ham ($folder)");
        next if ! -d $folder;
        push @files, `$find $folder/cur -type f`;
    };

    chomp @files;
    $util->file_write( $list, append=>1, lines => \@files );
}

sub email_send {
    my $self = shift;
    my %p = validate( @_, {
            'type'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $type, $fatal, $debug )
        = ( $p{'type'}, $p{'fatal'}, $p{'debug'} );

    my $email = $conf->{'toaster_admin_email'} || "root";

    my $qdir = $conf->{'qmail_dir'} || "/var/qmail";
    return 0 unless -x "$qdir/bin/qmail-inject";

    ## no critic
    unless ( open( $INJECT, "| $qdir/bin/qmail-inject -a -f \"\" $email" ) ) {
        warn "FATAL: couldn't send using qmail-inject!\n";
        return;
    }
    ## use critic

    if    ( $type eq "clean" )  { $self->email_send_clean($email) }
    elsif ( $type eq "spam" )   { $self->email_send_spam($email) }
    elsif ( $type eq "virus" )  { $self->email_send_eicar($email) }
    elsif ( $type eq "attach" ) { $self->email_send_attach($email) }
    elsif ( $type eq "clam" )   { $self->email_send_clam($email) }
    else { print "man Mail::Toaster to figure out how to use this!\n" }

    close $INJECT;

    return 1;
}

sub email_send_attach {

    my ( $self, $email ) = @_;

    print "\n\t\tSending .com test attachment - should fail.\n";
    print $INJECT <<"EOATTACH";
From: Mail Toaster Testing <$email>
To: Email Administrator <$email>
Subject: Email test (blocked attachment message)
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="gKMricLos+KVdGMg"
Content-Disposition: inline

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

This is an example of an Email message containing a virus. It should
trigger the virus scanner, and not be delivered.

If you are using qmail-scanner, the server admin should get a notification.

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="Eicar.com"

00000000000000000000000000000000000000000000000000000000000000000000

--gKMricLos+KVdGMg--

EOATTACH

}

sub email_send_clam {

    my ( $self, $email ) = @_;

    print "\n\t\tSending ClamAV test virus - should fail.\n";
    print $INJECT <<EOCLAM;
From: Mail Toaster testing <$email>
To: Email Administrator <$email>
Subject: Email test (virus message)

This is a viral message containing the clam.zip test virus pattern. It should be blocked by any scanning software using ClamAV. 


--Apple-Mail-7-468588064
Content-Transfer-Encoding: base64
Content-Type: application/zip;
        x-unix-mode=0644;
        name="clam.zip"
Content-Disposition: attachment;
        filename=clam.zip

UEsDBBQAAAAIALwMJjH9PAfvAAEAACACAAAIABUAY2xhbS5leGVVVAkAA1SjO0El6E1BVXgEAOgD
6APzjQpgYGJgYGBh4Gf4/5+BYQeQrQjEDgxSDAQBIwPD7kIBBwbjAwEB3Z+DgwM2aDoYsKStqfy5
y5ChgndtwP+0Aj75fYYML5/+38J5VnGLz1nFJB4uRqaCMnEmOT8eFv1bZwRQjTwA5Degid0C8r+g
icGAt2uQn6uPsZGei48PA4NrRWZJQFF+cmpxMUNosGsQVNzZx9EXKJSYnuqUX+HI8Axqlj0QBLgy
MPgwMjIkOic6wcx8wNDXyM3IJAkMFAYGNoiYA0iPAChcwDwwGxRwjFA9zAxcEIYCODDBgAlMCkDE
QDTUXmSvtID8izeQaQOiQWHiGBbLAPUXsl+QwAEAUEsBAhcDFAAAAAgAvAwmMf08B+8AAQAAIAIA
AAgADQAAAAAAAAAAAKSBAAAAAGNsYW0uZXhlVVQFAANUoztBVXgAAFBLBQYAAAAAAQABAEMAAAA7
AQAAAAA=

--Apple-Mail-7-468588064


EOCLAM

}

sub email_send_clean {

    my ( $self, $email ) = @_;

    print "\n\t\tsending a clean message - should arrive unaltered\n";
    print $INJECT <<EOCLEAN;
From: Mail Toaster testing <$email>
To: Email Administrator <$email>
Subject: Email test (clean message)

This is a clean test message. It should arrive unaltered and should also pass any virus or spam checks.

EOCLEAN

}

sub email_send_eicar {

    my ( $self, $email ) = @_;

    # http://eicar.org/anti_virus_test_file.htm
    # X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*

    print "\n\t\tSending the EICAR test virus - should fail.\n";
    print $INJECT <<EOVIRUS;
From: Mail Toaster testing <$email'>
To: Email Administrator <$email>
Subject: Email test (eicar virus test message)
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="gKMricLos+KVdGMg"
Content-Disposition: inline

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

This is an example email containing a virus. It should trigger any good virus
scanner.

If it is caught by AV software, it will not be delivered to its intended 
recipient (the email admin). The Qmail-Scanner administrator should receive 
an Email alerting him/her to the presence of the test virus. All other 
software should block the message.

--gKMricLos+KVdGMg
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="sneaky.txt"

X5O!P%\@AP[4\\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*

--gKMricLos+KVdGMg--

EOVIRUS
      ;

}

sub email_send_spam {

    print "\n\t\tSending a sample spam message - should fail\n";

    print $INJECT 'Return-Path: sb55sb55@yahoo.com
Delivery-Date: Mon, 19 Feb 2001 13:57:29 +0000
Return-Path: <sb55sb55@yahoo.com>
Delivered-To: jm@netnoteinc.com
Received: from webnote.net (mail.webnote.net [193.120.211.219])
   by mail.netnoteinc.com (Postfix) with ESMTP id 09C18114095
   for <jm7@netnoteinc.com>; Mon, 19 Feb 2001 13:57:29 +0000 (GMT)
Received: from netsvr.Internet (USR-157-050.dr.cgocable.ca [24.226.157.50] (may be forged))
   by webnote.net (8.9.3/8.9.3) with ESMTP id IAA29903
   for <jm7@netnoteinc.com>; Sun, 18 Feb 2001 08:28:16 GMT
From: sb55sb55@yahoo.com
Received: from R00UqS18S (max1-45.losangeles.corecomm.net [216.214.106.173]) by netsvr.Internet with SMTP (Microsoft Exchange Internet Mail Service Version 5.5.2653.13)
   id 1429NTL5; Sun, 18 Feb 2001 03:26:12 -0500
DATE: 18 Feb 01 12:29:13 AM
Message-ID: <9PS291LhupY>
Subject: anti-spam test: checking SpamAssassin [if present] (There yours for FREE!)
To: undisclosed-recipients:;

Congratulations! You have been selected to receive 2 FREE 2 Day VIP Passes to Universal Studios!

Click here http://209.61.190.180

As an added bonus you will also be registered to receive vacations discounted 25%-75%!


@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
This mailing is done by an independent marketing co.
We apologize if this message has reached you in error.
Save the Planet, Save the Trees! Advertise via E mail.
No wasted paper! Delete with one simple keystroke!
Less refuse in our Dumps! This is the new way of the new millennium
To be removed please reply back with the word "remove" in the subject line.
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

';
}

sub get_config {
    my ($self, $config) = @_;

    if ( $config && ref $config eq 'HASH' ) {
        $self->{conf} = $conf = $config;
        return $conf;
    }

    return $self->{conf} if (defined $self->{conf} && ref $self->{conf});

    $self->{conf} = $conf = $self->parse_config( file => "toaster-watcher.conf" );
    return $conf;
};  
    
sub get_debug {
    my ($self, $debug) = @_;
    return $debug if defined $debug;
    return $self->{debug};
};  
    
sub get_fatal {
    my ($self, $fatal) = @_;
    return $fatal if defined $fatal;
    return $self->{fatal};
};

sub get_maildir_paths {
    my $self = shift;
    my %p = validate( @_, { %std_opts } );

    my @paths;
    my $vpdir = $conf->{'vpopmail_home_dir'};

    # this method requires a SQL query for each domain
    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new( 'log' => $self );

    my $qdir  = $conf->{'qmail_dir'} || "/var/qmail";

    my @all_domains = $qmail->get_domains_from_assign(
        assign => "$qdir/users/assign",
        fatal  => 0,
    );

    return $log->error( "No domains found in qmail/users/assign",fatal=>0 )
        unless $all_domains[0];

    my $count = @all_domains;
    $log->audit( "get_maildir_paths: found $count domains.");

    foreach (@all_domains) {
        my $domain_name = $_->{'dom'};
        $log->audit( "  processing $domain_name mailboxes.");
        my @list_of_maildirs = `$vpdir/bin/vuserinfo -d -D $domain_name`;
        chomp @list_of_maildirs;
        push @paths, @list_of_maildirs;
    }

    chomp @paths;
    $count = @paths;
    $log->audit( "found $count mailboxes.");
    return @paths;
}

sub get_std_args {
    my $self = shift;
    my %p = @_;
    my %args;
    foreach ( qw/ debug fatal test_ok / ) {
        next if ! defined $p{$_};
        $args{$_} = $p{$_};
    };
    return %args;
};

sub get_toaster_htdocs {
    my $self = shift;
    my %p = validate( @_, { %std_opts } );

    # if available, use the configured location
    if ( defined $conf && $conf->{'toaster_http_docs'} ) {
        return $conf->{'toaster_http_docs'};
    }

    # otherwise, check the usual locations
    my @dirs = (
        "/usr/local/www/toaster",       # toaster
        "/usr/local/www/data/mail",     # legacy
        "/usr/local/www/mail",
        "/Library/Webserver/Documents", # Mac OS X
        "/var/www/html",                # Linux
        "/usr/local/www/data",          # FreeBSD
    );

    foreach my $dir ( @dirs ) {
        return $dir if -d $dir;
    };

    $log->error("could not find htdocs location.");
}

sub get_toaster_cgibin {

    my $self = shift;

    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $fatal, $debug, $test_ok )
        = ( $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    # if it is set, then use it.
    if ( defined $conf && defined $conf->{'toaster_cgi_bin'} ) {
        return $conf->{'toaster_cgi_bin'};
    }

    # Mail-Toaster preferred
    if ( -d "/usr/local/www/cgi-bin.mail" ) {
        return "/usr/local/www/cgi-bin.mail";
    }

    # FreeBSD default
    if ( -d "/usr/local/www/cgi-bin" ) {
        return "/usr/local/www/cgi-bin";
    }

    # linux
    if ( -d "/var/www/cgi-bin" ) {
        return "/var/www/cgi-bin";
    }

    # Mac OS X standard location
    if ( -d "/Library/WebServer/CGI-Executables" ) {
        return "/Library/WebServer/CGI-Executables";
    }
    
    # all else has failed, we must try to predict
    return $OSNAME eq "linux"  ? "/var/www/cgi-bin"
         : $OSNAME eq "darwin" ? "/Library/WebServer/CGI-Executables"
         : $OSNAME eq "netbsd" ? "/var/apache/cgi-bin"
         : "/usr/local/www/cgi-bin"   # last resort
         ;

}

sub get_toaster_logs {
    my $self = shift;

    # if it is set, then use it.
    if ( defined $conf && defined $conf->{'qmail_log_base'} ) {
        return $conf->{'qmail_log_base'};
    };
    
    #otherwise, we simply default to /var/log/mail
    return "/var/log/mail";
}

sub get_toaster_conf {

    my $self = shift;

    # if it is set, then use it.
    if ( defined $conf && defined $conf->{'system_config_dir'} ) {
        return $conf->{'system_config_dir'};
    };
    
	return $OSNAME eq "darwin"  ? "/opt/local/etc"  # Mac OS X
	     : $OSNAME eq "freebsd" ? "/usr/local/etc"  # FreeBSD
	     : $OSNAME eq "linux"   ? "/etc"            # Linux
	     : "/usr/local/etc"                         # reasonably good guess
	     ;
	     
}

sub get_util {
    my $self = shift;
    return $util if ref $util;
    use lib 'lib';
    require Mail::Toaster::Utility;
    $self->{util} = $util = Mail::Toaster::Utility->new( 'log' => $self );
    return $util;
};

sub process_logfiles {
    my $self = shift;

    my $pop3_logs = $conf->{pop3_log_method} || $conf->{'logs_pop3d'};

    $self->supervised_log_rotate( prot => 'send' );
    $self->supervised_log_rotate( prot => 'smtp' );
    $self->supervised_log_rotate( prot => 'submit' ) if $conf->{submit_enable};
    $self->supervised_log_rotate( prot => 'pop3'   ) if $pop3_logs eq 'qpop3d';

    require Mail::Toaster::Logs;
    my $logs = Mail::Toaster::Logs->new( 'log' => $self, conf => $conf ) or return;

    $logs->compress_yesterdays_logs( file=>"sendlog" );
    $logs->compress_yesterdays_logs( file=>"smtplog" );
    $logs->compress_yesterdays_logs( file=>"pop3log" ) if $pop3_logs eq "qpop3d";

    $logs->purge_last_months_logs() if $conf->{'logs_archive_purge'};

    return 1;
};

sub run_isoqlog {
    my $self = shift;

    return if ! $conf->{'install_isoqlog'};

    my $isoqlog = $util->find_bin( "isoqlog", debug=>0,fatal => 0 )
        or return;

    system "$isoqlog >/dev/null" or return 1;
    return;
};

sub run_qmailscanner {
    my $self = shift;

    return if ! ( $conf->{'install_qmailscanner'} 
        && $conf->{'qs_quarantine_process'} );

    $log->audit( "checking qmail-scanner quarantine.");

    my $qs_debug = $conf->{'qs_quarantine_verbose'};
    $qs_debug++ if $self->{debug};

    my @list = $qmail->get_qmailscanner_virus_sender_ips( $qs_debug );
         
    $log->audit( "found " . scalar @list . " infected files" ) if scalar @list;

    $qmail->UpdateVirusBlocks( ips => \@list ) 
        if $conf->{'qs_block_virus_senders'};
};

sub service_dir_get {
    my $self = shift;
    my %p = validate( @_, { prot => { type=>SCALAR,  }, },);

    my $prot = $p{prot};
       $prot = "smtp" if $prot eq "smtpd"; # catch and fix legacy usage.

    my @valid = qw/ send smtp pop3 submit /;
    my %valid = map { $_=>1 } @valid;
    return $log->error( "invalid service: $prot",fatal=>0) if ! $valid{$prot};

    my $svcdir = $conf->{'qmail_service'} || '/var/service';
       $svcdir = "/service" if ( !-d $svcdir && -d '/service' ); # legacy

    my $dir = $conf->{ "qmail_service_" . $prot } || "$svcdir/$prot";

    $log->audit("service dir for $prot is $dir");

    # expand qmail_service aliases
    if ( $dir =~ /^qmail_service\/(.*)$/ ) {
        $dir = "$svcdir/$1";
        $log->audit( "\t $prot dir expanded to: $dir, ok" );
    }

    return $dir;
}

sub service_symlinks {
    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my $debug = $p{'debug'};
    my $fatal = $p{'fatal'};

    my @active_services = ("smtp", "send");

    if ( $conf->{'pop3_daemon'} eq "qpop3d" ) {
        push @active_services, "pop3";
    }
    else {
        my $pop_service_dir = $self->service_dir_get( prot => "pop3" );
        my $pop_supervise_dir = $self->supervise_dir_get( prot => "pop3");

        if ( -e $pop_service_dir ) {
            $log->audit( "deleting $pop_service_dir because we aren't using qpop3d!");
            unlink($pop_service_dir);
        }
        else {
            $log->audit( "qpop3d not enabled due to configuration settings.");
        }
    }

    if ( $conf->{'submit_enable'} ) {
        push @active_services, "submit";
    }
    else {
        my $serv_dir = $self->service_dir_get( prot => "submit" );
        my $submit_supervise_dir = $self->supervise_dir_get( prot  => "submit" );
        if ( -e $serv_dir ) {
            $log->audit("deleting $serv_dir because submit isn't enabled!");
            unlink($serv_dir);
        }
        else {
            $log->audit("submit not enabled due to configuration settings.");
        }
    }

    foreach my $prot ( @active_services ) {

        my $svcdir = $self->service_dir_get( prot => $prot );
        my $supdir = $self->supervise_dir_get( prot => $prot );

        if ( -d $supdir ) {
            if ( -e $svcdir ) {
                $log->audit( "service_symlinks: $svcdir already exists.");
            }
            else {
                print
                "service_symlinks: creating symlink from $supdir to $svcdir\n";
                symlink( $supdir, $svcdir ) or die "couldn't symlink $supdir: $!";
            }
        }
        else {
            $log->audit( "skipping symlink to $svcdir because target $supdir doesn't exist.");
        };
    }

    return 1;
}

sub service_dir_create {
    my $self = shift;
    my %p = validate( @_, { %std_opts } );

    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    return $p{test_ok} if defined $p{test_ok};
    
    my $service = $conf->{'qmail_service'} || "/var/service";

    if ( ! -d $service ) {
        mkdir( $service, oct('0775') ) or
            return $log->error( "service_dir_create: failed to create $service: $!");
    };

    $log->audit("$service exists");

    unless ( -l "/service" ) {
        if ( -d "/service" ) {
            $util->syscmd( "rm -rf /service", fatal=>0 );
        }
        symlink( "/var/service", "/service" );
    }
}

sub service_dir_test {
    my $self = shift;
    
    my %p = validate( @_, {
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my $service = $conf->{'qmail_service'} || "/var/service";

    return $log->error( "service_dir_test: $service is missing!",fatal=>0)
        if !-d $service;

    $log->audit( "service_dir_test: $service already exists.");

    return $log->error( "/service symlink is missing!",fatal=>0)
        unless ( -l "/service" && -e "/service" );

    $log->audit( "service_dir_test: /service symlink exists.");

    return 1;
}

sub sqwebmail_clean_cache {
    my $self = shift;

    return 1 if ! $conf->{install_sqwebmail};

    my $script = "/usr/local/share/sqwebmail/cleancache.pl";
    return if ! -x $script; 
    system $script;
};

sub supervise_dir_get {
    my $self = shift;
    my %p = validate( @_, { prot => { type=>SCALAR,  }, },);

    my $prot = $p{prot};

    my $sdir = $conf->{'qmail_supervise'};
    $sdir = "/var/supervise" if ( !-d $sdir && -d '/var/supervise'); # legacy
    $sdir = "/supervise" if ( !-d $sdir && -d '/supervise');
    $sdir ||= "/var/qmail/supervise";

    my $dir = $prot eq 'smtp'   ? $conf->{'qmail_supervise_smtp'}
            : $prot eq 'pop3'   ? $conf->{'qmail_supervise_pop3'}
            : $prot eq 'send'   ? $conf->{'qmail_supervise_send'}
            : $prot eq 'submit' ? $conf->{'qmail_supervise_submit'}
            : 0;

    if ( !$dir ) {
        $log->error( "qmail_supervise_$prot is not set correctly in toaster-watcher.conf!", fatal => 0);
        $dir = "$sdir/$prot";
    }

    # expand the qmail_supervise shortcut
    $dir = "$sdir/$1" if $dir =~ /^qmail_supervise\/(.*)$/;

    $log->audit( "supervise dir for $prot is $dir");
    return $dir;
}

sub supervise_dirs_create {
    my $self = shift;
    my %p = validate( @_, { %std_opts } );
    my %args = $self->get_std_args( %p );

    my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    return $p{test_ok} if defined $p{test_ok};
    
    if ( -d $supervise ) {
        $log->audit( "supervise_dirs_create: $supervise, ok (exists)", %args );
    }
    else {
        mkdir( $supervise, oct('0775') ) or die "failed to create $supervise: $!\n";
        $log->audit( "supervise_dirs_create: $supervise, ok", %args );
    }

    chdir $supervise;

    foreach my $prot (qw/ smtp send pop3 submit /) {

        my $dir = $self->supervise_dir_get( prot => $prot );
        if ( -d $dir ) {
            $log->audit( "supervise_dirs_create: $dir, ok (exists)", %args );
            next;
        }

        mkdir( $dir, oct('0775') ) or die "failed to create $dir: $!\n";
        $log->audit( "supervise_dirs_create: creating $dir, ok", %args );
        
        mkdir( "$dir/log", oct('0775') ) or die "failed to create $dir/log: $!\n";
        $log->audit( "supervise_dirs_create: creating $dir/log, ok", %args );
            
        $util->syscmd( "chmod +t $dir", debug=>0 );

        symlink( $dir, $prot ) if ! -e $prot;
    }
}

sub supervised_dir_test {
    my $self = shift;
    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'dir'     => { type=>SCALAR,  optional=>1, },
            'quiet'   => { type=>SCALAR,  optional=>1, },
            %std_opts,
        },
    );

    my ($prot, $dir ) = ( $p{'prot'}, $p{'dir'} );
    my %args = $self->get_std_args( %p );
    my %targs = ( %args, quiet => $p{quiet} );

    return $p{test_ok} if defined $p{test_ok};

    if ( ! $dir ) {
        $dir = $self->supervise_dir_get( prot => $prot ) or return;
    }

    return $log->error("directory $dir does not exist", %args )
        unless ( -d $dir || -l $dir );
    $log->test( "exists, $dir", -d $dir, %targs );

    return $log->error("$dir/run does not exist!", %args ) if ! -f "$dir/run";
    $log->test( "exists, $dir/run", -f "$dir/run", %targs);

    return $log->error("$dir/run is not executable", %args ) if ! -x "$dir/run";
    $log->test( "perms,  $dir/run", -x "$dir/run", %targs );

    return $log->error("$dir/down is present", %args ) if -f "$dir/down";
    $log->test( "!exist, $dir/down", !-f "$dir/down", %targs );

    my $log_method = $conf->{ $prot . '_log_method' }
      || $conf->{ $prot . 'd_log_method' }
      || "multilog";

    return 1 if $log_method =~ /syslog|disabled/i;

    # make sure the log directory exists
    return $log->error( "$dir/log does not exist", %args ) if ! -d "$dir/log";
    $log->test( "exists, $dir/log", -d "$dir/log", %targs );

    # make sure the supervise/log/run file exists
    return $log->error( "$dir/log/run does not exist", %args ) if ! -f "$dir/log/run";
    $log->test( "exists, $dir/log/run", -f "$dir/log/run", %targs );

    # check the log/run file permissions
    return $log->error( "perms, $dir/log/run", %args) if ! -x "$dir/log/run";
    $log->test( "perms,  $dir/log/run", -x "$dir/log/run", %targs );

    # make sure the supervise/down file does not exist
    return $log->error( "$dir/log/down exists", %args) if -f "$dir/log/down";
    $log->test( "!exist, $dir/log/down", "$dir/log/down", %targs );
    return 1;
}

sub supervised_do_not_edit_notice {
    my $self = shift;
    my %p = validate( @_, {
            vdir  => { type=>SCALAR,  optional=>1, },
        },
    );

    my $vdir = $p{'vdir'};

    if ($vdir) {
        $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    }

    my $qdir   = $conf->{'qmail_dir'}      || "/var/qmail";
    my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

    my @lines = "#!/bin/sh

#    NOTICE: This file is generated automatically by toaster-watcher.pl.
#
#    Please DO NOT hand edit this file. Instead, edit toaster-watcher.conf
#      and then run toaster-watcher.pl to make your settings active.
#      Run: perldoc toaster-watcher.conf  for more detailed info.
";

    my $path  = "PATH=$qdir/bin";
       $path .= ":$vdir/bin" if $vdir;
       $path .= ":$prefix/bin:/usr/bin:/bin";
    
    push @lines, $path;
    push @lines, "export PATH\n";
    return @lines;
}

sub supervised_hostname {
    my $self = shift;
    my %p = validate( @_, { 'prot' => { type=>SCALAR }, },);

    my $prot = $p{'prot'};

    $prot .= "_hostname";
    $prot = $conf->{ $prot . '_hostname' };
    
    if ( ! $prot || $prot eq "system" ) {
        $log->audit( "using system hostname (" . hostname() . ")" );
        return hostname() . " ";
    }
    elsif ( $prot eq "qmail" ) {
        $log->audit( "  using qmail hostname." );
        return '\"$LOCAL" ';
    }
    else {
        $log->audit( "using conf defined hostname ($prot).");
        return "$prot ";
    }
}

sub supervised_multilog {
    my $self = shift;
    my %p = validate( @_, { 'prot' => SCALAR, %std_opts, },);

    my ( $prot, $fatal ) = ( $p{'prot'}, $p{'fatal'} );

    my $setuidgid = $util->find_bin( 'setuidgid', fatal=>0 );
    my $multilog  = $util->find_bin( 'multilog', fatal=>0);

    return $log->error( "supervised_multilog: missing daemontools components!",fatal=>$fatal)
        unless ( -x $setuidgid && -x $multilog );

    my $loguser  = $conf->{'qmail_log_user'} || "qmaill";
    my $log_base = $conf->{'qmail_log_base'} || $conf->{'log_base'} || '/var/log/mail';
    my $logprot  = $prot eq 'smtp' ? 'smtpd' : $prot;
    my $runline  = "exec $setuidgid $loguser $multilog t ";

    if ( $conf->{ $logprot . '_log_postprocessor' } eq "maillogs" ) {
        $log->audit( "supervised_multilog: using maillogs for $prot");
        $runline .= "!./" . $prot . "log ";
    }

    my $maxbytes = $conf->{ $logprot . '_log_maxsize_bytes' } || "100000";
    my $method   = $conf->{ $logprot . '_log_method' };

    if    ( $method eq "stats" )    { $runline .= "-* +stats s$maxbytes "; }
    elsif ( $method eq "disabled" ) { $runline .= "-* "; }
    else                            { $runline .= "s$maxbytes "; };

    $log->audit( "supervised_multilog: log method for $prot is $method");

    if ( $prot eq "send" && $conf->{'send_log_isoqlog'} ) {
        $runline .= "n288 ";    # keep a days worth of logs around
    }

    $runline .= "$log_base/$prot";
    return $runline;
}

sub supervised_log_method {
    my $self = shift;
    my %p = validate( @_, { prot => SCALAR } );

    my $prot = $p{'prot'} . "_hostname";

    if ( $conf->{$prot} eq "syslog" ) {
        $log->audit( "  using syslog logging." );
        return "\\\n\tsplogger qmail ";
    };

    $log->audit( "  using multilog logging." );
    return "\\\n\t2>&1 ";
}

sub supervised_log_rotate {
    my $self  = shift;
    my %p = validate( @_, { 'prot' => SCALAR } );
    my $prot = $p{prot};

    return $log->error( "root privs are needed to rotate logs.",fatal=>0)
        if $UID != 0;

    my $dir = $self->supervise_dir_get( prot => $prot ) or return;

    return $log->error( "the supervise directory '$dir' is missing", fatal=>0)
        if ! -d $dir;

    return $log->error( "the supervise run file '$dir/run' is missing", fatal=>0)
        if ! -f "$dir/run";

    $log->audit( "sending ALRM signal to $prot at $dir");
    my $svc = $util->find_bin('svc',debug=>0,fatal=>0) or return;
    system "$svc -a $dir";

    return 1;
};

sub supervise_restart {
    my $self = shift;
    my $dir  = shift or die "missing dir\n";

    return $self->error( "supervise_restart: is not a dir: $dir" ) if !-d $dir;

    my $svc  = $util->find_bin( 'svc',  debug=>0, fatal=>0 );
    my $svok = $util->find_bin( 'svok', debug=>0, fatal=>0 );

    return $self->error( "unable to find svc! Is daemontools installed?")
        if ! -x $svc;

    if ( $svok ) {
        system "$svok $dir" and 
            return $log->error( "sorry, $dir isn't supervised!" );
    };

    # send the service a TERM signal
    $log->audit( "sending TERM signal to $dir" );
    system "$svc -t $dir";
    return 1;
}

sub supervised_tcpserver {
    my $self = shift;
    my %p = validate( @_, { prot => { type=>SCALAR,  }, },);

    my $prot = $p{'prot'};

    # get max memory, default 4MB if unset
    my $mem = $conf->{ $prot . '_max_memory_per_connection' };
    $mem = $mem ? $mem * 1024000 : 4000000;
    $log->audit( "memory limited to $mem bytes" );

    my $softlimit = $util->find_bin( 'softlimit', debug => 0);
    my $tcpserver = $util->find_bin( 'tcpserver', debug => 0);

    my $exec = "exec\t$softlimit -m $mem \\\n\t$tcpserver ";
    $exec .= $self->supervised_tcpserver_mysql( $prot, $tcpserver );
    $exec .= "-H " if $conf->{ $prot . '_lookup_tcpremotehost' } == 0;
    $exec .= "-R " if $conf->{ $prot . '_lookup_tcpremoteinfo' } == 0;
    $exec .= "-p " if $conf->{ $prot . '_dns_paranoia' } == 1;
    $exec .= "-v " if (defined $conf->{$prot . '_verbose'} && $conf->{ $prot . '_verbose' } == 1);

    my $maxcon = $conf->{ $prot . '_max_connections' } || 40;
    my $maxmem = $conf->{ $prot . '_max_memory' };

    if ( $maxmem ) {
        if ( ( $mem / 1024000 ) * $maxcon > $maxmem ) {
            require POSIX;
            $maxcon = POSIX::floor( $maxmem / ( $mem / 1024000 ) );
            require Mail::Toaster::Qmail;
            my $qmail = Mail::Toaster::Qmail->new( 'log'  => $self );
            $qmail->_memory_explanation( $prot, $maxcon );
        }
    }
    $exec .= "-c$maxcon " if $maxcon != 40;
    $exec .= "-t$conf->{$prot.'_dns_lookup_timeout'} "
      if $conf->{ $prot . '_dns_lookup_timeout' } != 26;

    $exec .= $self->supervised_tcpserver_cdb( $prot );

    if ( $prot =~ /^smtpd|submit$/ ) {

        my $uid = getpwnam( $conf->{ $prot . '_run_as_user' } );
        my $gid = getgrnam( $conf->{ $prot . '_run_as_group' } );

        unless ( $uid && $gid ) {
            print
"uid or gid is not set!\n Check toaster_watcher.conf and make sure ${prot}_run_as_user and ${prot}_run_as_group are set to valid usernames\n";
            return 0;
        }
        $exec .= "\\\n\t-u $uid -g $gid ";
    }

    # default to 0 (all) if not selected
    my $address = $conf->{ $prot . '_listen_on_address' } || 0;
    $exec .= $address eq "all" ? "0 " : "$address ";
    $log->audit( "  listening on ip $address.");

    my $port = $conf->{ $prot . '_listen_on_port' };
       $port ||= $prot eq "smtpd"      ? "smtp"
               : $prot eq "submission" ? "submission"
               : $prot eq "pop3"       ? "pop3"
               : die "can't figure out what port $port should listen on!\n";
    $exec .= "$port ";
    $log->audit( "listening on port $port.");

    return $exec;
}

sub supervised_tcpserver_mysql {
    my $self = shift;
    my ($prot, $tcpserver ) = @_;

    return '' if ! $conf->{ $prot . '_use_mysql_relay_table' };

    # is tcpserver mysql patch installed
    my $strings = $util->find_bin( 'strings', debug=>0);

    if ( grep /sql/, `$strings $tcpserver` ) {
        $log->audit( "using MySQL based relay table" );
        return "-S ";
    }

    $log->error( "The mysql relay table option is selected but the MySQL patch for ucspi-tcp (tcpserver) is not installed! Please re-install ucspi-tcp with the patch (toaster_setup.pl -s ucspi) or disable ${prot}_use_mysql_relay_table.", fatal => 0);
    return '';
};

sub supervised_tcpserver_cdb {
    my ($self, $prot) = @_;

    my $cdb = $conf->{ $prot . '_relay_database' };
    return '' if ! $cdb;

    my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    $log->audit( "relay db set to $cdb");

    if ( $cdb =~ /^vpopmail_home_dir\/(.*)$/ ) {
        $cdb = "$vdir/$1";
        $log->audit( "  expanded to $cdb" );
    }

    $log->error( "$cdb selected but not readable" ) if ! -r $cdb;
    return "\\\n\t-x $cdb ";
};

1;
__END__


=head1 NAME

Mail::Toaster - turns a computer into a secure, full-featured, high-performance mail server.


=head1 SYNOPSIS

    functions used in: toaster-watcher.pl
                       toaster_setup.pl
                       qqtool.pl

To expose much of what can be done with these, run toaster_setup.pl -s help and you'll get a list of the available targets. 

The functions in Mail::Toaster.pm are used by toaster-watcher.pl (which is run every 5 minutes via cron), as well as in toaster_setup.pl and other functions, particularly those in Qmail.pm and mailadmin. 


=head1 USAGE

    use Mail::Toaster;
    my $toaster = Mail::Toaster->new;
    
    # verify that processes are all running and complain if not
    $toaster->check();

    # get a list of all maildirs on the system
    my @all_maildirs = $toaster->get_maildir_paths();
    
    # clean up old messages over X days old
    $toaster->clean_mailboxes();
    
    # clean up messages in Trash folders that exceed X days
    foreach my $maildir ( @all_maildirs ) {
        $toaster->maildir_clean_trash( path => $maildir );
    };

These functions can all be called indivually, see the working
examples in the aforementioned scripts or the t/Toaster.t file.


=head1 DESCRIPTION


Mail::Toaster, Everything you need to build a industrial strength mail system.

A collection of perl scripts and modules that are quite useful for building and maintaining a mail system. It was first authored for FreeBSD and has since been extended to Mac OS X, and Linux. It has become quite useful on other platforms and may grow to support other MTA's (think postfix) in the future.


=head1 SUBROUTINES


A separate section listing the public components of the module's interface. 
These normally consist of either subroutines that may be exported, or methods
that may be called on objects belonging to the classes that the module provides.
Name the section accordingly.
 
In an object-oriented module, this section should begin with a sentence of the 
form "An object of this class represents...", to give the reader a high-level
context to help them understand the methods that are subsequently described.


=over 8


=item new

  ############################################
  # Usage      : use Mail::Toaster;
  #            : my $toaster = Mail::Toaster->new;
  # Purpose    : create a new Mail::Toaster object
  # Returns    : an object to access Mail::Toaster functions
  # Parameters : none
  # Throws     : no exceptions


=item check

  ############################################
  # Usage      : $toaster->check();
  # Purpose    : Runs a series of tests to inform admins of server problems
  # Returns    : prints out a series of test failures
  # Throws     : no exceptions
  # See Also   : toaster-watcher.pl
  # Comments   : 
  
Performs the following tests:

   • check for processes that should be running.
   • make sure watcher.log is less than 1MB
   • make sure ~alias/.qmail-* exist and are not empty
   • verify multilog log directories are working

When this is run by toaster-watcher.pl via cron, the mail server admin will get notified via email any time one of the tests fails. Otherwise, there is no output generated.


=item learn_mailboxes

  ############################################
  # Usage      : $toaster->learn_mailboxes();
  # Purpose    : train SpamAssassin bayesian filters with your ham & spam
  # Returns    : 0 - failure, 1 - success
  # See Also   : n/a
  # Comments   : 

Powers an easy to use mechanism for training SpamAssassin on what you think is ham versus spam. It does this by trawling through a mail system, finding mail messages that have arrived since the last time it ran. It passes these messages through sa-learn with the appropriate flags (sa-learn --ham|--spam) to train its bayesian filters. 


=item clean_mailboxes

  ############# clean_mailboxes ##############
  # Usage      : $toaster->clean_mailboxes();
  # Purpose    : cleaning out old mail messages from user mailboxes
  # Returns    : 0 - failure, 1 - success
  # See Also   : n/a
  # Comments   :


This sub trawls through the mail system pruning all messages that exceed the threshholds defined in toaster-watcher.conf.

Peter Brezny suggests adding another option which is good. Set a window during which the cleaning script can run so that it is not running during the highest load times.


=item email_send


  ############ email_send ####################
  # Usage      : $toaster->email_send(type=>"clean" );
  #            : $toaster->email_send(type=>"spam"  );
  #            : $toaster->email_send(type=>"attach");
  #            : $toaster->email_send(type=>"virus" );
  #            : $toaster->email_send(type=>"clam"  );
  #
  # Purpose    : send test emails to test the content scanner
  # Returns    : 1 on success
  # Parameters : type (clean, spam, attach, virus, clam)
  # See Also   : email_send_[clean|spam|...]


Email test routines for testing a mail toaster installation.

This sends a test email of a specified type to the postmaster email address configured in toaster-watcher.conf.


=item email_send_attach


  ######### email_send_attach ###############
  # Usage      : internal only
  # Purpose    : send an email with a .com attachment
  # Parameters : an email address
  # See Also   : email_send

Sends a sample test email to the provided address with a .com file extension. If attachment scanning is enabled, this should trigger the content scanner (simscan/qmailscanner/etc) to reject the message.


=item email_send_clam

Sends a test clam.zip test virus pattern, testing to verify that the AV engine catches it.


=item email_send_clean

Sends a test clean email that the email filters should not block.


=item email_send_eicar

Sends an email message with the Eicar virus inline. It should trigger the AV engine and block the message.


=item email_send_spam

Sends a sample spam message that SpamAssassin should block.


=item find_config

This sub is called by several others to determine which configuration file to use. The general logic is as follows:

  If the etc dir and file name are provided and the file exists, use it.

If that fails, then go prowling around the drive and look in all the usual places, in order of preference:

  /opt/local/etc/
  /usr/local/etc/
  /etc

Finally, if none of those work, then check the working directory for the named .conf file, or a .conf-dist. 

Example:
  my $twconf = $util->find_config (
      file   => 'toaster-watcher.conf', 
      etcdir => '/usr/local/etc',
    )

 arguments required:
   file - the .conf file to read in

 arguments optional:
   etcdir - the etc directory to prefer
   debug
   fatal

 result:
   0 - failure
   the path to $file  


=item get_toaster_cgibin

Determine the location of the cgi-bin directory used for email applications.

=item get_toaster_conf

Determine where the *.conf files for mail-toaster are stored.


=item get_toaster_logs

Determine where log files are stored.


=item get_toaster_htdocs

Determine the location of the htdocs directory used for email applications.


=item maildir_clean_spam

  ########### maildir_clean_spam #############
  # Usage      : $toaster->maildir_clean_spam( 
  #                  path => '/home/domains/example.com/user',
  #              );
  # Purpose    : Removes spam that exceeds age as defined in t-w.conf.
  # Returns    : 0 - failure, 1 - success
  # Parameters : path - path to a maildir
  

results in the Spam folder of a maildir with messages older than X days removed.


=item get_maildir_paths

  ############################################
  # Usage      : $toaster->get_maildir_paths()
  # Purpose    : build a list of email dirs to perform actions upon
  # Returns    : an array listing every maildir on a Mail::Toaster
  # Throws     : exception on failure, or 0 if fatal=>0

This sub creates a list of all the domains on a Mail::Toaster, and then creates a list of every email box (maildir) on every domain, thus generating a list of every mailbox on the system. 


=item  build_spam_list

  ############################################
  # Usage      : $toaster->build_spam_list( 
  #                  path => '/home/domains/example.com/user',
  #              );
  # Purpose    : find spam messages newer than the last spam learning run
  # Returns    : 0 - failure, 1 - success
  # Results    : matching spam messages are appended to a tmpfile to be
  #              fed to sa-learn via the caller.
  # Parameters : path - path to a maildir
  # Throws     : no exceptions
  # See Also   : learn_mailboxes
  # Comments   : this is for a single mailbox
  

=item maildir_clean_trash

  ############################################
  # Usage      : $toaster->maildir_clean_trash( 
  #                 path => '/home/domains/example.com/user',
  #              );
  # Purpose    : expire old messages in Trash folders
  # Returns    : 0 - failure, 1 - success
  # Results    : a Trash folder with messages older than X days pruned
  # Parameters : path - path to a maildir
  # Throws     : no exceptions

Comments: Removes messages in .Trash folders that exceed the number of days defined in toaster-watcher.conf.


=item maildir_clean_sent

  ############################################
  # Usage      : $toaster->maildir_clean_sent(
  #                 path => '/home/domains/example.com/user',
  #              );
  # Purpose    : expire old messages in Sent folders
  # Returns    : 0 - failure, 1 - success
  # Results    : messages over X days in Sent folders are deleted
  # Parameters : path - path to a maildir
  # Throws     : no exceptions


=item maildir_clean_new


  ############ maildir_clean_new #############
  # Usage      : $toaster->maildir_clean_new(
  #                 path => '/home/domains/example.com/user',
  #              );
  # Purpose    : expire unread messages older than X days
  # Returns    : 0 - failure, 1 - success
  # Parameters : path - path to a maildir
  # Throws     : no exceptions

  This should be set to a large value, such as 180 or 365. Odds are, if a user hasn't read their messages in that amount of time, they never will so we should clean them out.


=item maildir_clean_ham


  ############################################
  # Usage      : $toaster->maildir_clean_ham(
  #                 path => '/home/domains/example.com/user',
  #              );
  # Purpose    : prune read email messages
  # Returns    : 0 - failure, 1 - success
  # Results    : an INBOX minus read messages older than X days
  # Parameters : path - path to a maildir
  # Throws     : no exceptions



=item build_ham_list


  ############################################
  # Usage      : $toaster->build_ham_list(
  #                 path => '/home/domains/example.com/user',
  #              );
  # Purpose    : find ham messages newer than the last learning run
  # Returns    : 0 - failure, 1 - success
  # Results    : matching ham messages are appended to a tmpfile to be
  #              fed to sa-learn via the caller.
  # Parameters : path - path to a maildir
  # Throws     : no exceptions
  # See Also   : learn_mailboxes
  # Comments   : this is for a single mailbox


=item service_dir_create

Create the supervised services directory (if it doesn't exist).

	$toaster->service_dir_create();

Also sets the permissions to 775.


=item service_dir_get

This is necessary because things such as service directories are now in /var/service by default but older versions of my toaster installed them in /service. This will detect and adjust for that.


 Example
   $toaster->service_dir_get( prot=>'smtp' );


 arguments required:
   prot is one of these protocols: smtp, pop3, submit, send

 arguments optional:
   debug
   fatal

 result:
    0 - failure
    the path to a directory upon success

=item service_dir_test

Makes sure the service directory is set up properly

	$toaster->service_dir_test();

Also sets the permissions to 775.


=item service_symlinks

Sets up the supervised mail services for Mail::Toaster

    $toaster->service_symlinks();

This populates the supervised service directory (default: /var/service) with symlinks to the supervise control directories (typically /var/qmail/supervise/). Creates and sets permissions on the following directories and files:

    /var/service/pop3
    /var/service/smtp
    /var/service/send
    /var/service/submit


=item supervise_dir_get

  my $dir = $toaster->supervise_dir_get( prot=>"smtp" );

This sub just sets the supervise directory used by the various qmail
services (qmail-smtpd, qmail-send, qmail-pop3d, qmail-submit). It sets
the values according to your preferences in toaster-watcher.conf. If
any settings are missing from the config, it chooses reasonable defaults.

This is used primarily to allow you to set your mail system up in ways
that are a different than mine, like a LWQ install.


=item supervise_dirs_create

Creates the qmail supervise directories.

	$toaster->supervise_dirs_create(debug=>$debug);

The default directories created are:

  $supervise/smtp
  $supervise/submit
  $supervise/send
  $supervise/pop3

unless otherwise specified in $conf


=item supervised_dir_test

Checks a supervised directory to see if it is set up properly for supervise to start it. It performs a bunch of tests including:

 • directory exists
 • dir/run file exists and is executable
 • dir/down file is not present
 • dir/log exists
 • dir/log/run exists and is executable
 • dir/log/down does not exist

 arguments required:
    prot - a protocol to check (smtp, pop3, send, submit)

 arguments optional:
    debug 


=item supervise_restart

Restarts a supervised process. 


=item check_processes

Tests to see if all the processes on your Mail::Toaster that should be running in fact are.

 usage:
    $toaster->check_processes();

 arguments optional:
    debug



=back  

=head1 SEE ALSO

The following man (perldoc) pages: 

  Mail::Toaster 
  Mail::Toaster::Conf
  toaster.conf 
  toaster-watcher.conf

  http://www.mail-toaster.org/


=head1 DIAGNOSTICS
 
Since the functions in the module are primarily called by toaster-watcher.pl, they are designed to do their work with a minimum amount of feedback, complaining only when a problem is encountered. Whether or not they produce status messages and verbose errors is governed by the "debug" argument which is passed to each sub/function. 

Status messages and verbose logging is enabled by default. toaster-watcher.pl and most of the automated tests (see t/toaster-watcher.t and t/Toaster.t) explicitely turns this off by setting debug=>0.


=head1 CONFIGURATION AND ENVIRONMENT

The primary means of configuration for Mail::Toaster is via toaster-watcher.conf. It is typically installed in /usr/local/etc, but may also be found in /opt/local/etc, or simply /etc. Documentation for the man settings in toaster-watcher.conf can be found in the man page (perldoc toaster-watcher.conf). 


=head1 DEPENDENCIES

    Params::Validate - must be installed seperately
    POSIX (floor only - included with Perl)
    Mail::Toaster::Utility


=head1 BUGS AND LIMITATIONS
 
There are no known bugs in this module. 
Please report problems to author
Patches are welcome.


=head1 TODO

  Install an optional stub DNS resolver (dnscache)

=head1 AUTHOR

Matt Simerson (matt@tnpi.net)


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2004-2010, The Network People, Inc. C<< <matt@tnpi.net> >>. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
