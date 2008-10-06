package Mail::Toaster;

use version;
our $VERSION = '5.12_01';

use strict;
use warnings;

use Carp;
use English qw/ -no_match_vars /;
use Params::Validate qw/ :all /;

use vars qw/ $INJECT $perl $util $conf /;

use lib "inc";
use lib "lib";
use Mail::Toaster::Utility 5;
use Mail::Toaster::Perl    5; 

sub new {

    my $class = shift;

    $perl = Mail::Toaster::Perl->new;
    $util = Mail::Toaster::Utility->new;
    $conf = $util->parse_config( file => "toaster-watcher.conf", debug => 0 );

    my $self = { conf => $conf };
    bless( $self, $class );

    return $self;
}

sub toaster_check {

    my $self = shift;
    
    my %p = validate( @_, {
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my $debug = $p{debug};

    # Do other sanity tests here

    # check permissions on toaster-watcher.conf
    my $twconf = $conf->{'system_config_dir'} . "/toaster-watcher.conf";
    if ( -f $twconf ) {
        my $mode = $util->file_mode(file=>$twconf, debug=>0);
        print "file mode of $twconf is $mode.\n" if $debug;
        my $others = substr($mode, -1, 1);
        if ( $others > 0 ) {
            print "HEY! Change the permissions on $twconf and remove others access! Hint\n
            chmod 600 $twconf\n\n";
        }
    };

    # check permissions on toaster.conf
    $twconf = $conf->{'system_config_dir'} . "/toaster.conf";
    if ( -f $twconf ) {
        my $mode = $util->file_mode(file=>$twconf, debug=>0);
        print "file mode of $twconf is $mode.\n" if $debug;
        my $others = substr($mode, -1, 1);
        if ( ! $others ) {
            print "HEY! Change the permissions on $twconf and allow group and other access! Hint:\n
            chmod 644 $twconf\n\n";
        }
    };

    # check for running processes
    $self->test_processes(debug=>$debug);

    # check that we can't SMTP AUTH with random user names and passwords

    # make sure watcher.log is not larger than 1MB
    my $logfile = $conf->{'toaster_watcher_log'};
    if ( $logfile && -e $logfile ) {
        my $size = ( stat($logfile) )[7];
        if ( $size > 999999 ) {
            print "toaster_check: compressing $logfile! ($size)\n" if $debug;
            $util->syscmd( command => "gzip -f $logfile", debug=>$debug );
        }
    }

# make sure the qmail alias files exist and are not empty
# UPDATE: this is now handled by qmail->config
#	my $qdir = $conf->{'qmail_dir'}; $qdir ||= "/var/qmail";
#	foreach ( qw/ .qmail-postmaster .qmail-root .qmail-mailer-daemon / ) {}
#		unless ( -s "$qdir/alias/$_" ) {)
#			print "\n\nWARNING: your administrative email address needs to be in $_!\n\n";
#			sleep 3;
#		};
#	};

    # make sure the supervised processes are configured correctly.

    $self->supervised_dir_test( prot=>"smtp",  debug=>$debug );
    $self->supervised_dir_test( prot=>"send",  debug=>$debug );
    $self->supervised_dir_test( prot=>"pop3",  debug=>$debug );
    $self->supervised_dir_test( prot=>"submit",debug=>$debug );
    
    return 1;
}

sub learn_mailboxes {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    my $days = $conf->{'maildir_learn_interval'};
    unless ($days) {
        warn "email spam/ham learning is disabled because maildir_learn_interval is not set in \$conf!";
        return 0;
    }

    my $log = $conf->{'qmail_log_base'};
    unless ($log) {
        print
"NOTICE: qmail_log_base is not set in toaster-watcher.conf! Using default /var/log/mail. \n";
        $log = "/var/log/mail";
    }
    print "learn_mailboxes: qmail log base is: $log\n" if $debug;
    $log = "$log/learn.log";

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'} };

    # create the log file if it does not exist
    unless ( -e $log ) {
        $util->logfile_append(
            file  => $log,
            prog  => $0,
            lines => ["created file"],
            debug => $debug,
            fatal => $fatal,
        );
        unless ( -e $log ) {
            croak if $fatal;
            return 0;
        }
    }

    if ( $OSNAME eq "freebsd" ) {
        # let periodic trigger the message learning if possible

    }
    else {
    }
        unless ( -M $log > $days ) {
            print "learn_mailboxes: skipping, $log is less than $days old\n"
                if $debug;
            return 1;
        }
    
    $util->logfile_append(
        file  => $log,
        prog  => $0,
        lines => ["learn_mailboxes running."],
        debug => $debug,
        fatal => $fatal,
    ) or return;
    
    print "learn_mailboxes: checks passed, getting ready to clean\n"
      if $debug;
    
    my $tmp = $conf->{'toaster_tmp_dir'} || "/tmp";
    
    my $spamlist = "$tmp/toaster-spam-learn-me";
    unlink $spamlist if ( -e $spamlist );

    my $hamlist = "$tmp/toaster-ham-learn-me";
    unlink $hamlist if ( -e $hamlist );

    my @every_maildir_on_server = 
        $self->get_maildir_paths( debug=>$debug );

    MAILDIR:
    foreach my $maildir (@every_maildir_on_server) {
        
        if ( ! $maildir || ! -d $maildir ) {
            print "learn_mailboxes: $maildir does not exist, skipping!\n";
            next MAILDIR;
        };
        
        print "learn_mailboxes: processing in $maildir\n" if $debug;

        if ( $conf->{'maildir_learn_Read'} ) {
            $self->maildir_learn_ham( 
                path  =>$maildir, 
                debug =>$debug,
            );
        };
        
        if ( $conf->{'maildir_learn_Spam'} ) {
            $self->maildir_learn_spam( 
                path  => $maildir, 
                debug => $debug,
            );
        };
    };

    my $nice    = $util->find_the_bin( bin => "nice", debug=>$debug );
    my $salearn = $util->find_the_bin( bin => "sa-learn", debug=>$debug );

    $util->syscmd( command => "$nice $salearn --ham  -f $hamlist", debug=>$debug );
    unlink $hamlist;
    
    $util->syscmd( command => "$nice $salearn --spam -f $spamlist", debug=>$debug );
    unlink $spamlist;
}

sub clean_mailboxes {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug, $test_ok )
        = ( $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    my $days = $conf->{'maildir_clean_interval'};
    unless ($days) {
        warn "maildir_clean_interval not set in \$conf!";
        return;
    }

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $log_base = $conf->{'qmail_log_base'};
    if ( ! $log_base) {
        carp "NOTICE: qmail_log_base is not set in toaster-watcher.conf! "
            . " Using default /var/log/mail.";
        $log_base = "/var/log/mail";
    }
    print "clean_mailboxes: qmail log base is: $log_base\n" if $debug;
    my $log = "$log_base/clean.log";

    # create the log file if it does not exist
    unless ( -e $log ) {
        $util->file_write(
            file  => $log,
            lines => ["created file"],
            debug => $debug,
            fatal => $fatal,
        );
        unless ( -e $log ) {
            croak if $fatal;
            return;
        };
    }

    unless ( -M $log > $days ) {
        print "clean_mailboxes: skipping, $log is less than $days old\n"
          if $debug;
        return 1;
    }

    $util->logfile_append(
        file  => $log,
        prog  => $0,
        lines => ["clean_mailboxes running."],
        debug => $debug,
        fatal => $fatal,
    ) or return;
        
    print "clean_mailboxes: checks passed, getting ready to clean\n"
      if $debug;

    my @every_maildir_on_server = 
        $self->get_maildir_paths( debug=>$debug );

    MAILDIR:
    foreach my $maildir (@every_maildir_on_server) {
        
        if ( ! $maildir || ! -d $maildir ) {
            print "clean_mailboxes: $maildir does not exist, skipping!\n";
            next MAILDIR;
        };
        
        print "clean_mailboxes: processing in $maildir\n" if $debug;

        if ( $conf->{'maildir_clean_Read'} ) {
            $self->maildir_clean_ham( path=>$maildir, debug=>$debug );
        };
        
        if ( $conf->{'maidir_clean_Unread'} ) {
            $self->maildir_clean_new( path=>$maildir, debug=>$debug );
        };
          
        if ( $conf->{'maidir_clean_Sent'} ) {
            $self->maildir_clean_sent( path=>$maildir, debug=>$debug );
        };
        
        if ( $conf->{'maidir_clean_Trash'} ) {
            $self->maildir_clean_trash( path=>$maildir, debug=>$debug );
        };
                      
        if ( $conf->{'maildir_clean_Spam'} ) {
            $self->maildir_clean_spam( path=>$maildir, debug=>$debug );
        };
    };

    print "done.\n" if $debug;
}

sub maildir_clean_spam {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    my $find = $util->find_the_bin( bin => "find", debug=>$debug );

    my $days = $conf->{'maildir_clean_Spam'};

    print "clean_spam: cleaning spam messages older than $days days.\n" if $debug;

    if ( !-d "$path/Maildir/.Spam" ) {
        print
"clean_spam: skipped cleaning because $path/Maildir/.Spam does not exist.\n"
          if $debug;
        return 0;
    };
    
    $util->syscmd(
        command =>
"$find $path/Maildir/.Spam/cur -type f -mtime +$days -exec rm {} \\;",
        debug   => $debug,
    );
        
    $util->syscmd( 
        command =>
"$find $path/Maildir/.Spam/new -type f -mtime +$days -exec rm {} \\;",
        debug   => $debug,
    );
};

sub maildir_learn_spam {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    unless ( -d "$path/Maildir/.Spam" ) {
        print
"learn_spam: skipped spam learning because $path/Maildir/.Spam does not exist.\n"
          if $debug;
        return 0;
    }

    my $find = $util->find_the_bin( bin => "find", debug=>0 );
    my $tmp  = $conf->{'toaster_tmp_dir'};
    my $list = "$tmp/toaster-spam-learn-me";

    #	This now gets done in the calling sub, for efficiency
    #	my $salearn = $util->find_the_bin( bin=>"sa-learn" );
    #	unless ( -x $salearn) {}
    #		carp "No sa-learn found!\n";
    #		return 0;
    #	{};

    print "maildir_learn_spam: finding new messages to learn from.\n" if $debug;

    # how often do we process spam?  It's not efficient (or useful) to feed spam
    # through sa-learn if we've already learned from them.

    my $interval = $conf->{'maildir_learn_interval'} || 7;    # default 7 days
    $interval = $interval + 2;

    my @files =
      `$find $path/Maildir/.Spam/cur -type f -mtime +1 -mtime -$interval;`;
    chomp @files;
    $util->file_write( file => $list, lines => \@files, append=>1, debug=>$debug );

    @files =
      `$find $path/Maildir/.Spam/new -type f -mtime +1 -mtime -$interval;`;
    chomp @files;
    $util->file_write( file => $list, lines => \@files, append=>1,debug=>$debug );

    #	$util->syscmd( command=>"$salearn --spam $path/Maildir/.Spam/cur" );
    #	$util->syscmd( command=>"$salearn --spam $path/Maildir/.Spam/new" );
}

sub maildir_clean_trash {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    unless ( -d "$path/Maildir/.Trash" ) {
        print
"clean_trash: skipped cleaning because $path/Maildir/.Trash does not exist.\n"
          if $debug;
        return 0;
    }

    my $find = $util->find_the_bin( bin => "find", debug=>0 );

    my $days = $conf->{'maildir_clean_Trash'};

    print "clean_trash: cleaning deleted messages older than $days days\n"
      if $debug;

    $util->syscmd( command =>
          "$find $path/Maildir/.Trash/new -type f -mtime +$days -exec rm {} \\;"
    );
    $util->syscmd( command =>
          "$find $path/Maildir/.Trash/cur -type f -mtime +$days -exec rm {} \\;"
    );
}

sub maidir_clean_sent {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    unless ( -d "$path/Maildir/.Sent" ) {
        print
"clean_sent: skipped cleaning because $path/Maildir/.Sent does not exist.\n"
          if $debug;
        return 0;
    }

    my $find = $util->find_the_bin( bin => "find", debug=>0 );
    my $days = $conf->{'maildir_clean_Sent'};

    print "clean_sent: cleaning sent messages older than $days days\n"
      if $debug;

    $util->syscmd( command =>
          "$find $path/Maildir/.Sent/new -type f -mtime +$days -exec rm {} \\;"
    );
    $util->syscmd( command =>
          "$find $path/Maildir/.Sent/cur -type f -mtime +$days -exec rm {} \\;"
    );
}

sub maildir_clean_new {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );

    unless ( -d "$path/Maildir/new" ) {
        print "clean_new: FAILED because $path/Maildir/new does not exist.\n"
          if $debug;
         return 0;
    }

    my $find = $util->find_the_bin( bin => "find", debug=>0 );
    my $days = $conf->{'maildir_clean_Unread'};

    print "clean_new: cleaning unread messages older than $days days\n"
      if $debug;

    $util->syscmd( command =>
          "$find $path/Maildir/new  -type f -mtime +$days -exec rm {} \\;" );
}

sub maildir_clean_ham {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug ) = ( $p{'path'}, $p{'debug'} );
    
    unless ( -d "$path/Maildir/cur" ) {
        print "clean_ham: FAILED because $path/Maildir/cur does not exist.\n"
          if $debug;
        return 0;
    }

    my $find = $util->find_the_bin( bin => "find", debug=>$debug );

    my $days = $conf->{'maildir_clean_Read'};

    print "clean_ham: cleaning read messages older than $days days\n" if $debug;
    
    $util->syscmd( command =>
          "$find $path/Maildir/cur  -type f -mtime +$days -exec rm {} \\;" );
}

sub maildir_learn_ham {

    my $self = shift;
    
    my %p = validate( @_, {
            'path'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $path, $debug )
        = ( $p{'path'}, $p{'debug'} );
    
    my @files;
    
    unless ( -d "$path/Maildir/cur" ) {
        print "learn_ham: ERROR, $path/Maildir/cur does not exist!\n" if $debug;
        return 0;
    }

    my $tmp  = $conf->{'toaster_tmp_dir'};
    my $list = "$tmp/toaster-ham-learn-me";

    my $find = $util->find_the_bin( bin => "find", debug=>0 );

    print "learn_ham: training SpamAsassin from ham (read) messages\n"
      if $debug;

    my $interval = $conf->{'maildir_learn_interval'} || 7;
    $interval = $interval + 2;

    my $days = $conf->{'maildir_learn_Read_days'};
    if ($days) {
        print "learn_ham: learning read messages older than $days days.\n"
          if $debug;
        @files =
          `$find $path/Maildir/cur -type f -mtime +$days -mtime -$interval;`;
        chomp @files;
        $util->file_write( append=>1, file => $list, lines => \@files, debug=>$debug );
    }
    else {
        if ( -d "$path/Maildir/.read" ) {

            #$util->syscmd( command=>"$salearn --ham $path/Maildir/cur" );
            @files = `$find $path/Maildir/.read/cur -type f`;
            chomp @files;
            $util->file_write( append=>1, file => $list, lines => \@files, debug=>$debug );
        }

        if ( -d "$path/Maildir/.Read" ) {

         #$util->syscmd( command=>"$salearn --ham $path/Maildir/.Read/cur" );
            @files = `$find $path/Maildir/.Read/cur -type f`;
            chomp @files;
            $util->file_write( append=>1, file => $list, lines => \@files, debug=>$debug );
        }
    }
}

sub service_dir_create {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug, $test_ok )
        = ( $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    defined $test_ok ? return $test_ok : print q{};
    
    my $service = $conf->{'qmail_service'} || "/var/service";

    if ( ! -d $service ) {
        if ( ! mkdir( $service, oct('0775') ) ){
            print "service_dir_create: failed to create $service: $!\n";
            croak if $fatal;
            return 0;
        }  
    };

    $util->_formatted("service_dir_create: $service exists", "ok");

    unless ( -l "/service" ) {
        if ( -d "/service" ) {
            $util->syscmd( command => "rm -rf /service", fatal=>0, debug=>$debug );
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

    if ( !-d $service ) {
        print "service_dir_test: $service is missing!\n";
        return 0;
    }

    print "service_dir_test: $service already exists.\n" if $p{debug};

    unless ( -l "/service" && -e "/service" ) {
        print "/service symlink is missing!\n";
        return 0;
    }

    print "service_dir_test: /service symlink exists.\n" if $p{debug};

    return 1;
}

sub supervise_dirs_create {

    my $self = shift;
    
    my %p = validate( @_, {
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";

    defined $p{'test_ok'} ? return $p{'test_ok'} : print q{};
    
    if ( -d $supervise ) {
        $util->_formatted( "supervise_dirs_create: $supervise",
            "ok (exists)" );
    }
    else {
        mkdir( $supervise, oct('0775') ) or croak "failed to create $supervise: $!\n";
        $util->_formatted( "supervise_dirs_create: $supervise", "ok" )
          if $p{debug};
    }

    chdir($supervise);

    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new;

    foreach my $prot (qw/ smtp send pop3 submit /) {
        my $dir = $prot;
        $dir = $qmail->supervise_dir_get( prot => $prot, debug=>$p{debug} );

        if ( -d $dir ) {
            $util->_formatted( "supervise_dirs_create: $dir",
                "ok (exists)" );
            next;
        }

        mkdir( $dir, oct('0775') ) or croak "failed to create $dir: $!\n";
        $util->_formatted( "supervise_dirs_create: creating $dir", "ok" );
        
        mkdir( "$dir/log", oct('0775') ) or croak "failed to create $dir/log: $!\n";
        $util->_formatted( "supervise_dirs_create: creating $dir/log",
            "ok" );
            
        $util->syscmd( command => "chmod +t $dir", debug=>$p{debug} );

        symlink( $dir, $prot ) unless ( -e $prot );
    }
}

sub supervised_dir_test {

    my $self = shift;
    
    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'dir'     => { type=>SCALAR,  optional=>1, },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ($prot, $dir, $debug, $test_ok) 
        = ( $p{'prot'}, $p{'dir'}, $p{'debug'}, $p{'test_ok'} );

    if ( ! $dir ) {
        require Mail::Toaster::Qmail;
        my $qmail = Mail::Toaster::Qmail->new;

        # set the directory based on config settings
        $dir = $qmail->supervise_dir_get( prot => $prot, debug=>$debug );
    }

    my $r;

    defined $test_ok ? return $test_ok : print q{};

    # make sure the directory exists
    if ($debug) {
        $r = -d $dir ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: exists $dir", $r );
    }
    return 0 unless ( -d $dir || -l $dir );

    # make sure the supervise/run file exists
    if ($debug) {
        $r = -f "$dir/run" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: exists $dir/run", $r );
    }
    return 0 unless -f "$dir/run";

    # check the run file permissions
    if ($debug) {
        $r = -x "$dir/run" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: perms $dir/run", $r );
    }
    return 0 unless -x "$dir/run";

    # make sure the supervise/down file does not exist
    if ($debug) {
        $r = ! -f "$dir/down" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: !exist $dir/down", $r );
    }
    return 0 if -f "$dir/down";

    my $log = $conf->{ $prot . '_log_method' }
      || $conf->{ $prot . 'd_log_method' }
      || "multilog";

    return 1 if ( $log eq "syslog" || $log eq "disabled" );

    # make sure the log directory exists
    if ($debug) {
        $r = -d "$dir/log" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: exists $dir/log", $r );
    }
    return 0 unless ( -d "$dir/log" );

    # make sure the supervise/log/run file exists
    if ($debug) {
        $r = -f "$dir/log/run" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: exists $dir/log/run", $r );
    }
    return 0 unless -f "$dir/log/run";

    # check the log/run file permissions
    if ($debug) {
        $r = -x "$dir/log/run" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: perms  $dir/log/run", $r );
    }
    return 0 unless -x "$dir/log/run";

    # make sure the supervise/down file does not exist
    if ($debug) {
        $r = ! -f "$dir/log/down" ? "ok" : "FAILED";
        $util->_formatted( "svc_dir_test: !exist $dir/log/down", $r );
    }
    return 0 if -f "$dir/log/down";

    return 1;
}

sub test_processes {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug, $test_ok )
        = ( $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );
    
    print "checking for running processes\n" if $debug;

    my @processes = qw( svscan qmail-send );

    push @processes, "httpd"              if $conf->{'install_apache'};
    push @processes, "mysqld"             if $conf->{'install_mysql'};
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
        if ( $util->is_process_running($_) ) {
            $util->_formatted( "\t$_", "ok" ) if $debug;
        }
        else {
            $util->_formatted( "\t$_", "FAILED" );            
        };
    }
    
    return 1;
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

sub get_maildir_paths {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $fatal, $debug ) = ( $p{'fatal'}, $p{'debug'} );

    my @paths;
    my $vpdir = $conf->{'vpopmail_home_dir'};

    # this method requires a MySQL query for each email address
    #	foreach ( `$vpdir/bin/vpopbull -n -V` ) {}
    #		my $path = `$vpdir/bin/vuserinfo -d $_`;
    #		push @paths, $path;
    #	{};
    #	chomp @paths;
    #	return @paths;

    # this method requires a SQL query for each domain
    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    my $qmaildir = $conf->{'qmail_dir'} || "/var/qmail";

    my @all_domains = $qmail->get_domains_from_assign(
        assign => "$qmaildir/users/assign",
        debug  => $debug,
        fatal  => $fatal,
    );

    unless ( $all_domains[0] ) {
        print "No domains found in qmail/users/assign!\n";
        return 0;
    }

    my $count = @all_domains;
    print "get_maildir_paths: found $count domains.\n" if $debug;

    foreach (@all_domains) {
        
        my $domain_name = $_->{'dom'};

        print "get_maildir_paths: processing $domain_name mailboxes.\n" if $debug;

        my @list_of_maildirs = `$vpdir/bin/vuserinfo -d -D $domain_name`;
        chomp @list_of_maildirs;
        push @paths, @list_of_maildirs;
    }

    chomp @paths;

    $count = @paths;
    print "found $count mailboxes.\n";

    return @paths;
}

sub get_toaster_htdocs {

    my $self = shift;

    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
#            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $fatal, $debug, $test_ok )
        = ( $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    # if available, use the configured location
    if ( defined $conf && $conf->{'toaster_http_docs'} ) {
        return $conf->{'toaster_http_docs'};
    }

    my $dir;
    
    # otherwise, we make a best guess
    $dir = -d "/usr/local/www/data/mail"     ? "/usr/local/www/data/mail"     # toaster
         : -d "/usr/local/www/mail"          ? "/usr/local/www/mail"
         : -d "/Library/Webserver/Documents" ? "/Library/Webserver/Documents" # Mac OS X
         : -d "/var/www/html"                ? "/var/www/html"                # Linux
         : "/usr/local/www/data"                                              # FreeBSD
         ;

    return $dir;    
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

sub service_symlinks {

    my $self = shift;
    
    my %p = validate( @_, {
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my $debug = $p{'debug'};
    my $fatal = $p{'fatal'};

    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    my @active_services = ("smtp", "send");

    if ( $conf->{'pop3_daemon'} eq "qpop3d" ) 
    {
        push @active_services, "pop3";
    }
    else 
    {
        my $pop_service_dir =
        $qmail->service_dir_get( prot => "pop3", debug => $debug );

        my $pop_supervise_dir = $qmail->supervise_dir_get(
            prot  => "pop3",
            debug => $debug
        );

        if ( -e $pop_service_dir ) {
            print "Deleting $pop_service_dir because we aren't using qpop3d!\n"
              if $debug;
            unlink($pop_service_dir);
        }
        else {
            warn "NOTICE: qpop3d not enabled due to configuration settings.\n" if $debug;
        }
    }

    if ( $conf->{'submit_enable'} ) 
    {
        push @active_services, "submit";
    }
    else 
    {
        my $submit_service_dir =
        $qmail->service_dir_get( prot => "submit", debug => $debug );

        my $submit_supervise_dir = $qmail->supervise_dir_get(
            prot  => "submit",
            debug => $debug
        );
        if ( -e $submit_service_dir ) {
            print "Deleting $submit_service_dir because submit isn't enabled!\n"
              if $debug;
            unlink($submit_service_dir);
        }
        else {
            warn "NOTICE: submit not enabled due to configuration settings.\n" if $debug;
        }
    }

    foreach my $prot ( @active_services ) {

        my $svcdir = $qmail->service_dir_get( prot  => $prot, debug => $debug,);
        my $supdir = $qmail->supervise_dir_get( prot  => $prot, debug => $debug,);

        if ( -d $supdir ) {
            if ( -e $svcdir ) {
                print "service_symlinks: $svcdir already exists.\n" if $debug;
            }
            else {
                print
                "service_symlinks: creating symlink from $supdir to $svcdir\n";
                symlink( $supdir, $svcdir ) or croak "couldn't symlink $supdir: $!";
            }
        }
        else {
            print "service_symlinks: skipping symlink to $svcdir because target $supdir doesn't exist.\n";
        };
    }

    return 1;
}

sub supervised_do_not_edit_notice {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'vdir'    => { type=>SCALAR,  optional=>1, },
#            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $vdir, $debug ) = ( $p{'vdir'}, $p{'debug'} );

    if ($vdir) {
        $vdir = $conf->{'vpopmail_home_dir'};
        unless ($vdir) {
            print "Yikes! Why is vpopmail_home_dir not set!?\n";
            $vdir = "/usr/local/vpopmail";
        }
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

    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $prot, $fatal, $debug )
        = ( $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my $prot_val = $prot . "_hostname";

    if ( $conf->{$prot_val} eq "qmail" ) {
        print "build_${prot}_run: using qmail hostname.\n" if $debug;
        return "\"\$LOCAL\" ";
    }
    elsif ( $conf->{$prot_val} eq "system" ) {
        use Sys::Hostname;
        print "build_${prot}_run: using system hostname ("
          . hostname() . ")\n"
          if $debug;
        return hostname() . " ";
    }
    else {
        print "build_${prot}_run: using conf defined hostname ("
          . $conf->{$prot_val} . ").\n"
          if $debug;
        return "$conf->{$prot_val} ";
    }
}

sub supervised_multilog {

    my $self = shift;
    
    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $prot, $fatal, $debug )
        = ( $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    my $setuidgid = $util->find_the_bin( bin => "setuidgid", debug=>0, fatal=>$fatal );
    my $multilog  = $util->find_the_bin( bin => "multilog", debug=>0, fatal=>$fatal );

    unless ( -x $setuidgid && -x $multilog ) {
        print "supervised_multilog: missing daemontools components!\n";
        croak if $fatal;
        return 0;
    }

    my $loguser = $conf->{'qmail_log_user'} || "qmaill";

    my $log = $conf->{'qmail_log_base'} || $conf->{'log_base'};
    unless ($log) {
        print "NOTICE: qmail_log_base is not set in toaster-watcher.conf!\n";
        $log = "/var/log/mail";
    }

    my $runline = "exec $setuidgid $loguser $multilog t ";
    my $logprot = $prot;

    # fixup shim
    $logprot = "smtpd" if ( $prot eq "smtp" );

    if ( $conf->{ $logprot . '_log_postprocessor' } eq "maillogs" ) {
        print "supervised_multilog: using maillogs processing for $prot\n"
          if $debug;
        $runline .= "!./" . $prot . "log ";
    }

    my $maxbytes = $conf->{ $logprot . '_log_maxsize_bytes' } || "100000";

    my $method = $conf->{ $logprot . '_log_method' };
    
    if    ( $method eq "stats" )    { $runline .= "-* +stats s$maxbytes "; }
    elsif ( $method eq "disabled" ) { $runline .= "-* "; }
    else                            { $runline .= "s$maxbytes "; };

    print "supervised_multilog: log method for $prot is $method\n" if $debug;

    if ( $prot eq "send" && $conf->{'send_log_isoqlog'} ) {
        $runline .= "n288 ";    # keep a days worth of logs around
    }

    $runline .= "$log/$prot";

    return $runline;
}

sub supervised_log_method {

    my $self = shift;
    
    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $prot, $debug ) = ( $p{'prot'}, $p{'debug'} );

    my $prot_val = $prot . "_hostname";

    if ( $conf->{$prot_val} eq "syslog" ) {
        print "build_" . $prot . "_run: using syslog logging.\n" if $debug;
        return "\\\n\tsplogger qmail ";
    }
    else {
        print "build_" . $prot . "_run: using multilog logging.\n" if $debug;
        return "\\\n\t2>&1 ";
    }
}

sub supervise_restart {

    my ( $self, $dir ) = @_;

    my $svc  = $util->find_the_bin( bin => "svc", debug=>0 );
    my $svok = $util->find_the_bin( bin => "svok", debug=>0 );

    unless ( -x $svc ) {
        $util->_formatted(
            "supervise_restart: unable to find svc! Is daemontools installed?",
            "FAILED"
        );
        return 0;
    }

    unless ( -d $dir ) {
        $util->_formatted(
            "supervise_restart: unable to use $dir! as a supervised dir",
            "FAILED" );
        return 0;
    }

    if ( $util->syscmd( command => "$svok $dir", debug => 0 ) ) {

        # send qmail-send a TERM signal
        $util->syscmd( command => "$svc -t $dir", debug => 0 );
        return 1;
    }
    else {
        $util->_formatted(
            "supervise_restart: sorry, $dir isn't supervised!", "FAILED" );
        return 0;
    }
}

sub supervised_tcpserver {

    my $self = shift;

    # parameter validation
    my %p = validate( @_, {
            'prot'    => { type=>SCALAR,  },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $prot, $fatal, $debug ) = ( $p{'prot'}, $p{'fatal'}, $p{'debug'} );

    # get max memory, with a defafult value of 3MB if not set
    my $mem = $conf->{ $prot . '_max_memory_per_connection' };
    $mem ? $mem = "3000000" : $mem = $mem * 1024000;
    print "build_" . $prot . "_run: memory limited to $mem bytes\n" if $debug;

    my $softlimit =
      $util->find_the_bin( bin => "softlimit", debug => $debug );
    my $tcpserver =
      $util->find_the_bin( bin => "tcpserver", debug => $debug );

    my $exec = "exec\t$softlimit ";
    $exec .= "-m $mem " if $mem;
    $exec .= "\\\n\t$tcpserver ";

    if (   $conf->{ $prot . '_use_mysql_relay_table' }
        && $conf->{ $prot . '_use_mysql_relay_table' } == 1 )
    {
        # make sure tcpserver mysql patch is installed
        
        my $strings = $util->find_the_bin(bin=>'strings',debug=>0);

        if ( grep(/sql/, `$strings $tcpserver`) ) {
            $exec .= "-S ";
            print "build_" . $prot . "_run: using MySQL based relay table\n"
              if $debug;
        }
        else {
            print
                "The mysql relay table option is selected but the MySQL patch for ucspi-tcp (tcpserver) is not installed! Please re-install ucspi-tcp with the patch (toaster_setup.pl -s ucspi) or disable the "
                 . $prot . "_use_mysql_relay_table setting.\n";
            
        }
    }

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
            my $qmail = Mail::Toaster::Qmail->new();
            $qmail->_memory_explanation( $prot, $maxcon );
        }
    }
    $exec .= "-c$maxcon " if $maxcon != 40;

    $exec .= "-t$conf->{$prot.'_dns_lookup_timeout'} "
      if $conf->{ $prot . '_dns_lookup_timeout' } != 26;

    my $cdb = $conf->{ $prot . '_relay_database' };
    if ($cdb) {
        my $vdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
        print "build_" . $prot . "_run: relay db set to $cdb\n" if $debug;

        if ( $cdb =~ /^vpopmail_home_dir\/(.*)$/ ) {
            $cdb = "$vdir/$1";
            print "build_" . $prot . "_run: expanded to $cdb\n" if $debug;
        }

        if ( -r $cdb ) { $exec .= "-x $cdb " }
        else {
            carp "build_" . $prot . "_run: $cdb selected but not readable!\n";
            croak "FATAL error!\n" if $fatal;
            return 0;
        }
    }

    if ( $prot eq "smtpd" || $prot eq "submit" ) {

        my $uid = getpwnam( $conf->{ $prot . '_run_as_user' } );
        my $gid = getgrnam( $conf->{ $prot . '_run_as_group' } );

        unless ( $uid && $gid ) {
            print
"FAILURE: uid and gid not set!\n You need to edit toaster_watcher.conf 
and make sure " . $prot
              . "_run_as_user and "
              . $prot
              . "_run_as_group are set to valid usernames on your system.\n";
            return 0;
        }
        $exec .= "-u $uid -g $gid ";
    }

    # default to 0 (all) if not selected
    my $address = $conf->{ $prot . '_listen_on_address' } || 0;
    $exec .= $address eq "all" ? "0 " : "$address ";
    print "build_" . $prot . "_run: listening on ip $address.\n" if $debug;

    my $port = $conf->{ $prot . '_listen_on_port' };
    unless ($port) {

        $port = $prot eq "smtpd"      ? "smtp"
              : $prot eq "submission" ? "submission"
              : $prot eq "pop3"       ? "pop3"
              : croak "uh-oh, can't figure out what port $port should listen on!\n";

    }
    $exec .= "$port ";
    print "build_" . $prot . "_run: listening on port $port.\n" if $debug;

    return $exec;
}

1;
__END__


=head1 NAME

Mail::Toaster - turns a computer into a secure, full-featured, high-performance mail server.


=head1 VERSION
 
5.11


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
    $toaster->toaster_check();

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


=item toaster_check

  ############################################
  # Usage      : $toaster->toaster_check();
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


=item  maildir_learn_spam

  ############################################
  # Usage      : $toaster->maildir_learn_spam( 
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


=item maidir_clean_sent

  ############################################
  # Usage      : $toaster->maidir_clean_sent(
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



=item maildir_learn_ham


  ############################################
  # Usage      : $toaster->maildir_learn_ham(
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


=item test_processes

Tests to see if all the processes on your Mail::Toaster that should be running in fact are.

 usage:
    $toaster->test_processes();

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
    Mail::Toaster::Perl
    Mail::Toaster::Utility


=head1 BUGS AND LIMITATIONS
 
There are no known bugs in this module. 
Please report problems to author
Patches are welcome.


=head1 TODO

  Add support for Darwin (MacOS X) - done
  Add support for Linux - done
  Update openssl & courier ssl .cnf files  - done
  Install an optional stub DNS resolver (dnscache)


=head1 AUTHOR

Matt Simerson (matt@tnpi.net)


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2004-2008, The Network People, Inc. C<< <matt@tnpi.net> >>. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
