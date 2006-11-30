#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Setup.pm, matt Exp $
#

package Mail::Toaster::Setup;

use vars qw($VERSION $freebsd $darwin $err);
$VERSION = '5.04';

use Carp;
use Config;
use File::Copy;
use English qw( -no_match_vars );
use Params::Validate qw( :all );
#use Smart::Comments;

use lib "inc";
use lib "lib";

use Mail::Toaster          5.0; my $toaster = Mail::Toaster->new;
use Mail::Toaster::Utility 5.0; my $utility = Mail::Toaster::Utility->new;
use Mail::Toaster::Perl    5.0; my $perl    = Mail::Toaster::Perl->new;

if ( $OSNAME eq "freebsd" ) {
    require Mail::Toaster::FreeBSD;
    $freebsd = Mail::Toaster::FreeBSD->new;
}
elsif ( $OSNAME eq "darwin" ) {
    require Mail::Toaster::Darwin;
    $darwin = Mail::Toaster::Darwin->new;
}

sub new {
    my $class = shift;

    # validate, from Params::Validate will suck up @_ and make sure it
    # contains only the named parameter conf, with a HASHREF being passed in.
    # This hashref should consist of the settings from toaster-watcher.conf
    #
    # since nearly all the $setup functions require conf, we may as well have
    # it passed along in the new object. This does make creating a new Setup
    # object a little more expensive, but it saves having to validate conf in
    # each and every sub, which is quite a net savings.
    my %p = validate(@_, { 'conf' => HASHREF } );

    # create our $self object, which contains our class which was
    # passed to us, and the validated $conf HASHREF. 
    my $self = { 
        class => $class, 
        conf  => $p{'conf'}, 
        debug => $p{'conf'}->{'toaster_debug'},
    };

    if ( $p{'conf'}->{'toaster_debug'} ) {
        print "toaster_debug is set, prepare for lots of verbosity!\n";
    };
    bless( $self, $class );
    return $self;
}

sub apache {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation here
    my %p = validate( @_, {
            'ver'   => { type => SCALAR, optional => 1, },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my ( $ver, $fatal ) = ( $p{'ver'}, $p{'fatal'} );

    # we do not want to try installing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
    $ver ||= $conf->{'install_apache'};

    if ( !$ver ) {
        $utility->_formatted( "apache: installing", "skipping (disabled)" )
          if $debug;
        return;
    }

    use Mail::Toaster::Apache;
    my $apache = Mail::Toaster::Apache->new();

    require Cwd;
    my $old_directory = Cwd::cwd();

    if ( lc($ver) eq "apache" or lc($ver) eq "apache1" or $ver == 1 ) {

        $apache->install_apache1( $src, $conf );
    }
    elsif ( lc($ver) eq "ssl" ) {

        $apache->install_ssl_certs( conf=>$conf, type=>"rsa", debug=>$debug );
    }
    else {

        $apache->install_apache2( conf=>$conf, debug=>$debug );
        chdir($old_directory);
        return 1;
    }

    chdir($old_directory);
    $apache->startup( conf=>$conf, debug=>$debug );
}

sub apache_conf_fixup {
# makes a couple changes necessary for Apache to start while running in a jail

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my ( $fatal, $test_ok ) = ( $p{'fatal'}, $p{'test_ok'} );

    use Mail::Toaster::Apache;
    my $apache    = Mail::Toaster::Apache->new;
    my $httpdconf = $apache->conf_get_dir( conf=>$conf );

    unless ( -e $httpdconf ) {
        print "Could not find your httpd.conf file!  FAILED!\n";
        return 0;
    }

    unless ( `hostname` =~ /^jail/ ) {    # we're running in a jail
        return 0;
    }

    my @lines = $utility->file_read( file => $httpdconf, debug=>$debug );
    foreach my $line (@lines) {
        if ( $line =~ /^Listen 80/ ) {    # this is only tested on FreeBSD
            my @ips = $utility->get_my_ips(only=>"first", debug=>0);
           #my @ips = `ifconfig | grep inet | cut -d " " -f 2`;
            $line = "Listen $ips[0]:80";
        }
    }

    $utility->file_write( file => "/var/tmp/httpd.conf", lines => \@lines, debug=>$debug );

    return 0 unless $utility->install_if_changed(
        newfile  => "/var/tmp/httpd.conf",
        existing => $httpdconf,
        clean    => 1,
        notify   => 1,
        debug    => $debug,
    );

    return 1;
}

sub autorespond {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_autorespond'};

    unless ($ver) {
        $utility->_formatted( "autorespond: installing", "skipping (disabled)" )
          if $debug;
        return;
    }

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {
        $freebsd->port_install( port => "autorespond", base => "mail", debug=>$debug );
    }

    my $autorespond = $utility->find_the_bin(
                    program => "autorespond",
                    fatal   => 0,
                    debug   => 0,
                );

    # return success if it is installed.
    if ( $autorespond &&  -x $autorespond ) {
        $utility->_formatted( "autorespond: installing", "ok (exists)" )
          if $debug;
        return 1;
    }

    if ( $ver eq "port" ) {
        print
"autorespond: port install failed, attempting to install from source.\n";
        $ver = "2.0.5";
    }

    my @targets = ( 'make', 'make install' );

    if ( $OSNAME eq "darwin" || $OSNAME eq "freebsd" ) {
        print "autorespond: applying strcasestr patch.\n";
        my $sed = $utility->find_the_bin(bin=>"sed",debug=>0);
        my $prefix = $conf->{'toaster_prefix'} || "/usr/local";
        $prefix =~ s/\//\\\//g;
        @targets = (
            "$sed -i '' 's/strcasestr/strcasestr2/g' autorespond.c",
            "$sed -i '' 's/PREFIX=\$(DESTDIR)\/usr/PREFIX=\$(DESTDIR)$prefix/g' Makefile",
            'make', 'make install'
        );
    }

    $utility->install_from_source(
        conf           => $conf,
        package        => "autorespond-$ver",
        site           => 'http://www.inter7.com',
        url            => '/devel',
        targets        => \@targets,
        bintest        => 'autorespond',
        debug          => $debug,
        source_sub_dir => 'mail',
    );

    if ( -x $utility->find_the_bin(
            program => "autorespond",
            fatal   => 0,
            debug   => 0, )
      )
    {
        $utility->_formatted( "autorespond: installing", "ok" );
        return 1;
    }

    return 0;
}

sub clamav {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation here
    my %p = validate( @_, {
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal    = $p{'fatal'};
    my $prefix   = $conf->{'toaster_prefix'}      || "/usr/local";
    my $confdir  = $conf->{'system_config_dir'}   || "/usr/local/etc";
    my $share    = "$prefix/share/clamav";
    my $clamuser = $conf->{'install_clamav_user'} || "clamav";
    my $ver      = $conf->{'install_clamav'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    unless ($ver) {
        $utility->_formatted( "clamav: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    my $installed;    # once installed, we'll set this

    # install via ports if selected
    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {
        $freebsd->port_install(
            port  => "clamav",
            base  => "security",
            flags => "BATCH=yes WITHOUT_LDAP=1",
            debug => $debug,
        );

        $self->clamav_update(  debug=>$debug );
        $self->clamav_perms (  debug=>$debug );
        $self->clamav_start (  debug=>$debug );
        return 1;
    }

    # add the clamav user and group
    unless ( getpwuid($clamuser) ) {
        require Mail::Toaster::Passwd;
        my $passwd = Mail::Toaster::Passwd->new();
        $passwd->creategroup( "clamav", "90" );
        $passwd->user_add( user => $clamuser, uid => 90, debug => 1 );
    }

    unless ( getpwnam($clamuser) ) {
        print "User clamav user installation FAILED, I cannot continue!\n";
        return 0;
    }

    # install via ports if selected
    if ( $OSNAME eq "darwin" && $ver eq "port" ) {
        if ( $darwin->port_install( port_name => "clamav" ) ) {
            $utility->_formatted( "clamav: installing", "ok" );
        }
        $self->clamav_update( debug=>$debug );
        $self->clamav_perms ( debug=>$debug );
        $self->clamav_start ( debug=>$debug );
        return 1;
    }

    # port installs didn't work out, time to build from sources

    # set a default version of ClamAV if not provided
    if ( $ver eq "1" ) { $ver = "0.88"; }
    ;    # latest as of 7/2006

    # download the sources, build, and install ClamAV
    $utility->install_from_source(
        conf           => $conf,
        package        => 'clamav-' . $ver,
        site           => 'http://' . $conf->{'toaster_sf_mirror'},
        url            => '/clamav',
        targets        => [ './configure', 'make', 'make install' ],
        bintest        => 'clamdscan',
        source_sub_dir => 'mail',
        debug          => $debug,
    );

    if ( -x $utility->find_the_bin(
            bin   => "clamdscan",
            fatal => 0,
            debug => $debug
        )
      )
    {
        $utility->_formatted( "clamav: installing", "ok" );
    }
    else {
        $utility->_formatted( "clamav: installing", "FAILED" );
        return 0;
    }

    $self->clamav_update(  debug=>$debug );
    $self->clamav_perms (  debug=>$debug );
    $self->clamav_start (  debug=>$debug );
}

sub clamav_perms {
# fix up the permissions of several clamav directories and files

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my ($fatal,$test_ok ) = ( $p{'fatal'}, $p{'test_ok'} );
       $debug = $p{'debug'};

    my $prefix  = $conf->{'toaster_prefix'}      || "/usr/local";
    my $confdir = $conf->{'system_config_dir'}   || "/usr/local/etc";
    my $clamuid = $conf->{'install_clamav_user'} || "clamav";
    my $share   = "$prefix/share/clamav";

    foreach my $file ( $share, "$share/daily.cvd", "$share/main.cvd",
        "$share/viruses.db", "$share/viruses.db2", "/var/log/freshclam.log", )
    {

        #print "setting the ownership of $file to $clamuid.\n";
        if ( -e $file ) {
            $utility->file_chown(
                file  => $file,
                uid   => $clamuid,
                gid   => 'clamav',
                debug => $debug,
            );
        }
    }
}

sub clamav_run {
# create a FreeBSD rc.d startup file

    my $self = shift;
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'confdir' => { type => SCALAR,  optional => 0, },
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my ( $confdir, $fatal ) = ( $p{'confdir'}, $p{'fatal'} );

    my $RUN;
    my $run_f = "$confdir/rc.d/clamav.sh";

    unless ( -s $run_f ) {
        print "Creating $confdir/rc.d/clamav.sh startup file.\n";
        open( $RUN, ">", $run_f )
          or croak "clamav: couldn't open $run_f for write: $!";

        print $RUN <<EO_CLAM_RUN;
#!/bin/sh

case "\$1" in
    start)
        /usr/local/bin/freshclam -d -c 2 -l /var/log/freshclam.log
        echo -n " freshclam"
        ;;

    stop)
        /usr/bin/killall freshclam > /dev/null 2>&1
        echo -n " freshclam"
        ;;

    *)
        echo ""
        echo "Usage: `basename \$0` { start | stop }"
        echo ""
        exit 64
        ;;
esac
EO_CLAM_RUN

        close $RUN;

        $utility->file_chmod(
            file => "$confdir/rc.d/freshclam.sh",
            mode => '0755',
            debug=> $debug,
        );

        $utility->file_chmod(
            file => "$confdir/rc.d/clamav.sh",
            mode => '0755',
            debug=> $debug,
        );
    }
}

sub clamav_start {
    # get ClamAV running

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( $utility->is_process_running('clamd') ) {
        $utility->_formatted( "clamav: starting up", "ok (already running)" );
    }

    print "Starting up ClamAV...\n";

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->rc_dot_conf_check(
            check => "clamav_clamd_enable",
            line  => 'clamav_clamd_enable="YES"',
            debug => $debug,
        );

        $freebsd->rc_dot_conf_check(
            check => "clamav_freshclam_enable",
            line  => 'clamav_freshclam_enable="YES"',
            debug => $debug,
        );

        print "(Re)starting ClamAV's clamd...";
        my $start = "/usr/local/etc/rc.d/clamav-freshclam";
        $start = "$start.sh" unless ( -x $start );

        if ( -x $start ) {
            $utility->syscmd( command => "$start restart", debug=>0 );
            print "done.\n";
        }
        else {
            print
              "ERROR: I could not find the startup (rc.d) file for clamAV!\n";
        }

        print "(Re)starting ClamAV's freshclam...";
        $start = "/usr/local/etc/rc.d/clamav-clamd";
        $start = "$start.sh" unless ( -x $start );
        $utility->syscmd( command => "$start restart", debug=>0 );

        if ( $utility->is_process_running('clamd', debug=>0) ) {
            $utility->_formatted( "clamav: starting up", "ok" );
        }

        # These are no longer required as the FreeBSD ports now installs
        # startup files of its own.
        #clamav_run($confdir);
        if ( -e "/usr/local/etc/rc.d/clamav.sh" ) {
            unlink("/usr/local/etc/rc.d/clamav.sh");
        }

        if ( -e "/usr/local/etc/rc.d/freshclam.sh" ) {
            unlink("/usr/local/etc/rc.d/freshclam.sh");
        }
    }
    else {
        $utility->_incomplete_feature(
            {
                mess   => "start up ClamAV on $OSNAME",
                action =>
'You will need to start up ClamAV yourself and make sure it is configured to launch at boot time.',
            }
        );
    }

}

sub clamav_update {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # set up freshclam (keeps virus databases updated)
    my $logfile = "/var/log/freshclam.log";
    unless ( -e $logfile ) {
        $utility->syscmd( command => "touch $logfile", debug=>0 );
        $utility->file_chmod( file => $logfile, mode => '0644', debug=>0 );
        $self->clamav_perms(  debug=>0 );
    }

    my $freshclam = $utility->find_the_bin( bin => "freshclam", debug=>0 );

    if ( -x $freshclam ) {
        $utility->syscmd( command => "$freshclam", debug => 0, fatal => 0 );
    }
    else { print "couldn't find freshclam!\n"; }
}

sub config {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate(@_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # apply the platform specific changes to the config file
    $self->config_tweaks(debug=>$debug, fatal=>$fatal);

    my $tw_conf = "toaster-watcher.conf";

    my $file = $utility->find_config(
        file  => $tw_conf,
        debug => $debug,
        fatal => $fatal,
    );

    if ( -f $file ) {
        warn "found: $file \n" if $debug;
    };

    # refresh our $conf  (required for setup -s all) 
    $conf = $utility->parse_config(
        file  => $tw_conf,
        debug => $debug,
        fatal => $fatal,
    );

    if ( -f $file ) {
        warn "refreshed \$conf from: $file \n" if $debug;
    };

    if ( ! -e $file ) {
        $utility->_formatted( "config: $file is missing!", "FAILED" );
        return;
    }

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'} };

    # update hostname if necessary
    if ( $conf->{'toaster_hostname'} eq "mail.example.com" ) {
        my $system_hostname = `hostname`;
        chomp $system_hostname;
        $conf->{'toaster_hostname'} = $utility->answer(
            question => "the hostname of this mail server",
            default  => $system_hostname,
        );
        chomp $conf->{'toaster_hostname'};
    }
    $utility->_formatted(
        "toaster hostname set to " . $conf->{'toaster_hostname'}, "ok" )
      if $debug;

    # set postmaster email
    if ( $conf->{'toaster_admin_email'} eq "postmaster\@example.com" ) {
        $conf->{'toaster_admin_email'} = $utility->answer(
            q => "the email address for administrative emails and notices\n".
                " (probably yours!)",
            default => "postmaster",
        ) || 'root';
    }
    $utility->_formatted(
        "toaster admin emails sent to " . $conf->{'toaster_admin_email'}, "ok" )
      if $debug;

    # set test email account
    if ( $conf->{'toaster_test_email'} eq "test\@example.com" ) {

        $conf->{'toaster_test_email'} = $utility->answer(
            question => "an email account for running tests",
            default  => "postmaster\@" . $conf->{'toaster_hostname'}
        );
    }
    $utility->_formatted(
        "toaster test account set to " . $conf->{'toaster_test_email'}, "ok" )
      if $debug;

    # set test email password
    if ( !$conf->{'toaster_test_email_pass'}
        || $conf->{'toaster_test_email_pass'} eq "cHanGeMe" )
    {
        $conf->{'toaster_test_email_pass'} =
          $utility->answer( q => "the test email account password" );
    }
    $utility->_formatted(
        "toaster test password set to " . $conf->{'toaster_test_email_pass'},
        "ok" )
      if $debug;

    # set vpopmail MySQL password
    if ( $conf->{'vpopmail_mysql'} ) {
        if ( !$conf->{'vpopmail_mysql_repl_pass'}
            || $conf->{'vpopmail_mysql_repl_pass'} eq "supersecretword" )
        {
            $conf->{'vpopmail_mysql_repl_pass'} =
              $utility->answer( question => "the password for securing vpopmails "
                    . "database connection. You MUST enter a password here!",
              );
        }
        $utility->_formatted(
            "vpopmail MySQL password set to "
              . $conf->{'vpopmail_mysql_repl_pass'},
            "ok"
        ) if $debug;
    }

    # OpenSSL certificate settings

    # country
    if ( $conf->{'ssl_country'} eq "SU" ) {
        print "             SSL certificate defaults\n";
        $conf->{'ssl_country'} =
          uc(   $utility->answer( 
                    question => "your 2 digit country code (US)",
                    default  => "US",
                )
          );
    }
    $utility->_formatted( "config: ssl_country",
        "ok (" . $conf->{'ssl_country'} . ")" ) if $debug;

    # state
    if ( $conf->{'ssl_state'} eq "saxeT" ) {
        $conf->{'ssl_state'} =
          $utility->answer( question => "the name (non abbreviated) of your state" );
    }
    $utility->_formatted( "config: ssl_state",
        "ok (" . $conf->{'ssl_state'} . ")" ) if $debug;

    # locality (city)
    if ( $conf->{'ssl_locality'} eq "dnalraG" ) {
        $conf->{'ssl_locality'} =
          $utility->answer( q => "the name of your locality/city" );
    }
    $utility->_formatted( "config: ssl_locality",
        "ok (" . $conf->{'ssl_locality'} . ")" ) if $debug;

    # organization
    if ( $conf->{'ssl_organization'} eq "moc.elpmaxE" ) {
        $conf->{'ssl_organization'} =
          $utility->answer( q => "the name of your organization" );
    }
    $utility->_formatted( "config: ssl_organization",
        "ok (" . $conf->{'ssl_organization'} . ")" )
      if $debug;

    # insert selected values into the array.
    my @lines = $utility->file_read( file => $file, debug => 0 );
    foreach my $line (@lines) {

        if ( $line =~ /^toaster_hostname / ) {
            $line = sprintf( '%-34s = %s',
                'toaster_hostname', $conf->{'toaster_hostname'} );
        }
        elsif ( $line =~ /^toaster_admin_email / ) {
            $line = sprintf( '%-34s = %s',
                'toaster_admin_email', $conf->{'toaster_admin_email'} );
        }
        elsif ( $line =~ /^toaster_test_email / ) {
            $line = sprintf( '%-34s = %s',
                'toaster_test_email', $conf->{'toaster_test_email'} );
        }
        elsif ( $line =~ /^toaster_test_email_pass / ) {
            $line = sprintf( '%-34s = %s',
                'toaster_test_email_pass', $conf->{'toaster_test_email_pass'} );
        }
        elsif ($line =~ /^vpopmail_mysql_repl_pass /
            && $conf->{'vpopmail_mysql'} )
        {
            $line = sprintf( '%-34s = %s',
                'vpopmail_mysql_repl_pass',
                $conf->{'vpopmail_mysql_repl_pass'} );
        }
        elsif ( $line =~ /^ssl_country / ) {
            $line =
              sprintf( '%-34s = %s', 'ssl_country', $conf->{'ssl_country'} );
        }
        elsif ( $line =~ /^ssl_state / ) {
            $line = sprintf( '%-34s = %s', 'ssl_state', $conf->{'ssl_state'} );
        }
        elsif ( $line =~ /^ssl_locality / ) {
            $line =
              sprintf( '%-34s = %s', 'ssl_locality', $conf->{'ssl_locality'} );
        }
        elsif ( $line =~ /^ssl_organization / ) {
            $line = sprintf( '%-34s = %s',
                'ssl_organization', $conf->{'ssl_organization'} );
        }
    }

    # write all the new settings to disk.
    $utility->file_write(
        file  => "/tmp/toaster-watcher.conf",
        lines => \@lines,
        debug => 0,
    );

    # save the changes back to the current file
    my $r = $utility->install_if_changed(
            newfile  => "/tmp/toaster-watcher.conf",
            existing => $file,
            mode     => '0640',
            clean    => 1,
            notify   => -e $file ? 1 : 0,
            debug    => 0,
            fatal    => $fatal,
    );

    if ( ! $r ) {
        warn "installing /tmp/toaster-watcher.conf to $file failed!\n";
        croak if $fatal;
        return;
    };

    $r = $r == 1 ? "ok" : "ok (current)";
    $utility->_formatted( "config: updating $file", $r ) if $debug;

    # install $file in $prefix/etc/toaster-watcher.conf if it doesn't exist
    # already
    my $config_dir = $conf->{'system_config_dir'} || '/usr/local/etc';

    if ( ! -e "$config_dir/$tw_conf") {
        # we need to install $file
        ### install location: $config_dir/$tw_conf
        $utility->install_if_changed(
            newfile  => $file,
            existing => "$config_dir/$tw_conf",
            mode     => '0640',
            clean    => 0,
            notify   => 1,
            debug    => 0,
            fatal    => $fatal,
        );
    }

    # install a toaster-watcher.conf-dist file in $prefix/etc
    $utility->install_if_changed(
        newfile  => "contrib/pkgtools.conf",
        existing => "$config_dir/pkgtools.conf-mail-toaster",
        mode     => '0644',
        clean    => 0,
        notify   => 1,
        debug    => 0,
        fatal    => 0,
    );

    # install a toaster.conf file in $prefix/etc
    if ( ! -e "$config_dir/toaster.conf" ) {
        $utility->install_if_changed(
            newfile  => "toaster.conf-dist",
            existing => "$config_dir/toaster.conf",
            mode     => '0644',
            clean    => 0,
            notify   => 1,
            debug    => 0,
            fatal    => 0,
        );
    };

    # install a toaster.conf-dist file in $prefix/etc
    $utility->install_if_changed(
        newfile  => "toaster.conf-dist",
        existing => "$config_dir/toaster.conf-dist",
        mode     => '0644',
        clean    => 0,
        notify   => 1,
        debug    => 0,
        fatal    => 0,
    );
}

sub config_tweaks {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};
    
    my %p = validate(@_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $hostname = `hostname`; chomp $hostname;
    my $status = "ok";
    my %changes;

    my $file = $utility->find_config(
        file  => 'toaster-watcher.conf',
        debug => $debug,
        fatal => $fatal,
    );

    # verify that find_config worked and $file is readable
    if ( ! -r $file ) {
        $utility->_formatted( "config_tweaks: read test on $file", "FAILED" );
        carp "find_config returned $file: $!\n";
        croak if $fatal;
        return;
    };

    if ( $OSNAME eq "freebsd" ) {
        $utility->_formatted( "config_tweaks: apply FreeBSD tweaks", $status );

        $changes{'install_squirrelmail'} = 'port    # 0, ver, port';
        $changes{'install_autorespond'}  = 'port    # 0, ver, port';
        $changes{'install_isoqlog'}      = 'port    # 0, ver, port';
        $changes{'install_ezmlm'}        = 'port    # 0, ver, port';
        $changes{'install_courier_imap'} = 'port    # 0, ver, port';
        $changes{'install_sqwebmail'}    = 'port    # 0, ver, port';
        $changes{'install_clamav'}       = 'port    # 0, ver, port';
        $changes{'install_ripmime'}      = 'port    # 0, ver, port';
        $changes{'install_cronolog'}     = 'port    # ver, port';
        $changes{'install_daemontools'}  = 'port    # ver, port';
        $changes{'install_qmailadmin'}   = 'port    # 0, ver, port';
    }
    elsif ( $OSNAME eq "darwin" ) {

        $utility->_formatted( "config_tweaks: apply Darwin tweaks", $status );

        $changes{'toaster_os_release'}  = 'darwin';
        $changes{'toaster_http_base'} = '/Library/WebServer';
        $changes{'toaster_http_docs'} = '/Library/WebServer/Documents';
        $changes{'toaster_cgi_bin'}   = '/Library/WebServer/CGI-Executables';
        $changes{'toaster_prefix'}    = '/opt/local';
        $changes{'toaster_src_dir'}   = '/opt/local/src';
        $changes{'system_config_dir'} = '/opt/local/etc';
        $changes{'install_mysql'}     = '0      # 0, 1, 2, 3, 40, 41, 5';
        $changes{'install_portupgrade'}            = '0';
        $changes{'filtering_maildrop_filter_file'} =
          '/opt/local/etc/mail/mailfilter';
        $changes{'qmail_mysql_include'} =
          '/opt/local/lib/mysql/libmysqlclient.a';
        $changes{'vpopmail_home_dir'}           = '/opt/local/vpopmail';
        $changes{'vpopmail_mysql'}              = '0';
        $changes{'smtpd_use_mysql_relay_table'} = '0';
        $changes{'qmailadmin_spam_command'}     =
          '| /opt/local/bin/maildrop /opt/local/etc/mail/mailfilter';
        $changes{'qmailadmin_http_images'} =
          '/Library/WebServer/Documents/images';
        $changes{'apache_suexec_docroot'}  = '/Library/WebServer/Documents';
        $changes{'apache_suexec_safepath'} = '/opt/local/bin:/usr/bin:/bin';
    }
    elsif ( $OSNAME eq "linux" ) {
        $utility->_formatted( "config_tweaks: apply Linux tweaks", $status );
    }

    if ( $hostname && $hostname =~ /mt-test/ ) {
        $utility->_formatted( "config_tweaks: apply MT testing tweaks",
            $status );

        $changes{'toaster_hostname'}      = 'jail10.cadillac.net';
        $changes{'toaster_admin_email'}   = 'postmaster@jail10.cadillac.net';
        $changes{'toaster_test_email'}    = 'test@jail10.cadillac.net';
        $changes{'toaster_test_email_pass'}   = 'cHanGeMed';
        $changes{'install_squirrelmail_sql'}  = '1';
        $changes{'install_apache2_modperl'}   = '1';
        $changes{'install_apache_suexec'}     = '1';
        $changes{'install_phpmyadmin'}        = '1';
        $changes{'install_vqadmin'}           = '1';
        $changes{'install_openldap_client'}   = '1';
        $changes{'install_ezmlm_cgi'}         = '1';
        $changes{'install_dspam'}             = '1';
        $changes{'install_qmailscanner'}      = '1.25';
        $changes{'install_pyzor'}             = '1'; 
        $changes{'install_bogofilter'}        = '1';
        $changes{'install_dcc'}               = '1';
        $changes{'vpopmail_default_domain'}       = 'jail10.cadillac.net';
        $changes{'pop3_ssl_daemon'}               = 'qpop3d';
    }

    # foreach key of %changes, apply to $conf
    my @lines = $utility->file_read( file => $file );

    foreach my $line (@lines) {
        next if ( $line =~ /^#/ );  # comment lines
        next if ( $line !~ /=/ );   # not a key = value

        my ( $key, $val ) = $utility->parse_line( line => $line, strip => 0 );

        if ( defined $changes{$key} && $changes{$key} ne $val ) {
            $status = "changed";

            #print "\t setting $key to ". $changes{$key} . "\n" if $debug;

            $line = sprintf( '%-34s = %s', $key, $changes{$key} );

            print "\t$line\n";
        }
    }

    # all done unless changes are required
    return 1 unless ( $status && $status eq "changed" );

    # ask the user for permission to install
    return 1
      unless $utility->yes_or_no(
        question =>
'config_tweaks: The changes shown above are recommended for use on your system.
May I apply the changes for you?',
        timeout => 10,
      );

    # write $conf to temp file
    $utility->file_write(
        file  => "/tmp/toaster-watcher.conf",
        lines => \@lines,
        debug => 0,
    );

    # if the file ends with -dist, then save it back with out the -dist suffix
    # the find_config sub will automatically prefer the newer non-suffixed one
    if ( $file =~ m/(.*)-dist\z/ ) {
        $file = $1;
    };

    # update the file if there are changes
    my $r = $utility->install_if_changed(
        newfile  => "/tmp/toaster-watcher.conf",
        existing => $file,
        clean    => 1,
        notify   => 0,
        debug    => 0,
    );

    return 0 unless $r;
    $r == 1 ? $r = "ok" : $r = "ok (current)";
    $utility->_formatted( "config_tweaks: updated $file", $r );
}

sub courier_imap {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation here
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_courier_imap'};

    unless ($ver) {
        $utility->_formatted( "courier: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {
        $self->courier_authlib(
            debug => $debug,
            fatal => $fatal,
        );

#        my @defs = "WITH_VPOPMAIL=1";
#        push @defs, "WITHOUT_AUTHDAEMON=1";
#        push @defs, "WITH_CRAM=1";
#        push @defs, "AUTHMOD=authvchkpw";
        #push @defs, "BATCH=yes";  # if only this worked <sigh>

        $freebsd->port_install(
            port    => "courier-imap",
            base    => "mail",
            # we have overrode this via the port/options file above
            #flags  => join( ",", @defs ),
            debug   => $debug,
            options => "#
# This file was generated by mail-toaster
# No user-servicable parts inside!
# Options for courier-imap-4.1.1,1
_OPTIONS_READ=courier-imap-4.1.1,1
WITH_OPENSSL=true
WITHOUT_FAM=true
WITHOUT_DRAC=true
WITHOUT_TRASHQUOTA=true
WITHOUT_GDBM=true
WITHOUT_IPV6=true
WITHOUT_AUTH_LDAP=true
WITHOUT_AUTH_MYSQL=true
WITHOUT_AUTH_PGSQL=true
WITHOUT_AUTH_USERDB=true
WITH_AUTH_VCHKPW=true",
        );
        $self->courier_startup(  debug=>$debug );
    }

    if ( $OSNAME eq "darwin" ) {
        $darwin->port_install( port_name => "courier-imap", debug=>$debug );
        return 1;
    }

    if ( -e "/usr/local/etc/pkgtools.conf" ) {
        unless (`grep courier /usr/local/etc/pkgtools.conf`) {
            print
"\n\nYou should add this line to MAKE_ARGS in /usr/local/etc/pkgtools.conf:\n\n
	'mail/courier-imap' => 'WITHOUT_AUTHDAEMON=1 WITH_CRAM=1 WITH_VPOPMAIL=1 AUTHMOD=authvchkpw',\n\n";
            sleep 3;
        }
    }

    if (   $OSNAME eq "freebsd"
        && $ver eq "port"
        && $freebsd->is_port_installed( port => "courier-imap", debug=>$debug ) )
    {
        $self->courier_startup(  debug=>$debug );
        return 1;
    }

    # if a specific version has been requested, install it from sources
    # but first, a default for lazy folks who didn't edit toaster-watcher.conf
    $ver = "3.0.8" if ( $ver eq "port" );

    my $site    = "http://" . $conf->{'toaster_sf_mirror'};
    my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";
    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";

    $ENV{"HAVE_OPEN_SMTP_RELAY"} = 1;    # circumvent bug in courier

    my $conf_args =
"--prefix=$prefix --exec-prefix=$prefix --without-authldap --without-authshadow --with-authvchkpw --sysconfdir=/usr/local/etc/courier-imap --datadir=$prefix/share/courier-imap --libexecdir=$prefix/libexec/courier-imap --enable-workarounds-for-imap-client-bugs --disable-root-check --without-authdaemon";

    print "./configure $conf_args\n";
    my $make = $utility->find_the_bin( bin => "gmake", debug=>$debug );
    $make ||= $utility->find_the_bin( bin => "make", debug=>$debug );
    my @targets = ( "./configure " . $conf_args, $make, "$make install" );
    my @patches = 0;                     # "$package-patch.txt";

    $utility->install_from_source(
        conf           => $conf,
        package        => "courier-imap-$ver",
        site           => $site,
        url            => "/courier",
        targets        => \@targets,
        patches        => \@patches,
        bintest        => "imapd",
        source_sub_dir => 'mail',
        debug          => $debug
    );

    $self->courier_startup(  debug=>$debug );
}

sub courier_authlib {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $prefix  = $conf->{'toaster_prefix'}    || "/usr/local";
    my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";

    if ( $OSNAME ne "freebsd" ) {
        print
          "courier-authlib build support is not available for $OSNAME yet.\n";
        return 0;
    };

    $freebsd->port_install(
        port  => "libltdl15",
        base  => "devel",
        check => "libltdl",
        debug => $debug,
        fatal => 0,
    );

    $freebsd->port_install( 
        port => "sysconftool", 
        base => "devel", 
        debug => $debug,
        fatal => 0,
    );

    if ( ! $freebsd->is_port_installed( port => "courier-authlib", debug=>$debug ) ) {

        #it's not installed, clean up any previous attempts
        if ( -d "/var/db/ports/courier-authlib" ) {    
            $utility->syscmd(
                command => "rm -rf /var/db/ports/courier-authlib", 
                debug  => $debug,
            );
        };

#        print "\n You may be prompted to select authentication types. " .
#            "If so, select only vpopmail (AUTH_VCHKPW)\n\n";
#        sleep 5;
#        print "\n";

        if ( -d "/usr/ports/security/courier-authlib" ) {

            # they moved the port!
            $freebsd->port_install(
                port  => "courier-authlib",
                base  => "security",
                # the port does not honor these settings anyway, so we
                # cheat and precreate the options file. 
                #flags => "AUTHMOD=authvchkpw,WITH_AUTH_VCHKPW",
                debug => $debug,
                options => "
# This file was generated by mail-toaster
# No user-servicable parts inside!
# Options for courier-authlib-0.58_2
_OPTIONS_READ=courier-authlib-0.58_2
WITHOUT_GDBM=true
WITHOUT_AUTH_LDAP=true
WITHOUT_AUTH_MYSQL=true
WITHOUT_AUTH_PGSQL=true
WITHOUT_AUTH_USERDB=true
WITH_AUTH_VCHKPW=true",
            );
        }

        if ( -d "/usr/ports/mail/courier-authlib-vchkpw" ) {
            $freebsd->port_install(
                port  => "courier-authlib-vchkpw",
                base  => "mail",
                flags => "AUTHMOD=authvchkpw",
                debug => $debug,
            );
        }

        # just in case their ports tree hasn't been udpated in ages
        if ( -d "/usr/ports/mail/courier-authlib" ) {
            $freebsd->port_install(
                port  => "courier-authlib",
                base  => "mail",
                flags => "WITH_VPOPMAIL=1,WITHOUT_PAM=1,USE_RC_SUBR=no",
                debug => $debug,
            );
        }
    }

    # install a default authdaemonrc
    my $authrc = "$confdir/authlib/authdaemonrc";

    unless ( -e $authrc ) {
        if ( -e "$authrc.dist" ) {
            print "installing default authdaemonrc.\n";
            copy("$authrc.dist", $authrc);
        }

        if ( -e $authrc ) {

            # remove the extra authentication types
            my @lines = $utility->file_read( file => $authrc, debug=>$debug );
            foreach my $line (@lines) {
                if ( $line =~ /^authmodulelist=\"authuserdb/ ) {
                    $utility->_formatted( "courier_authlib: fixed up $authrc",
                        "ok" );
                    $line = 'authmodulelist="authvchkpw"';
                }
            }
            $utility->file_write( file => $authrc, lines => \@lines, debug=>$debug );
        }
    }

    $freebsd->rc_dot_conf_check(
        check => "courier_authdaemond_enable",
        line  => "courier_authdaemond_enable=\"YES\"",
        debug => $debug,
    );

    my $start = "$prefix/etc/rc.d/courier-authdaemond";

    if ( -x $start ) { 
        $utility->syscmd( command => "$start start", debug=>$debug );
    };

    if ( -x "$start.sh" ) {
        $utility->syscmd( command => "$start.sh start", debug=>$debug );
    }
}

sub courier_startup {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation here
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";
    my $ver     = $conf->{'install_courier_imap'};
    my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";
    my $libe    = "$prefix/libexec/courier-imap";
    my $share   = "$prefix/share/courier-imap";

    if ( !chdir("$confdir/courier-imap") ) {
        print "could not chdir $confdir/courier-imap.\n" if $debug;
        die ""                                           if $fatal;
        return 0;
    }

    copy( "pop3d.cnf.dist",       "pop3d.cnf" )    if ( !-e "pop3d.cnf" );
    copy( "pop3d.dist",           "pop3d" )        if ( !-e "pop3d" );
    copy( "pop3d-ssl.dist",       "pop3d-ssl" )    if ( !-e "pop3d-ssl" );
    copy( "imapd.cnf.dist",       "imapd.cnf" )    if ( !-e "imapd.cnf" );
    copy( "imapd.dist",           "imapd" )        if ( !-e "imapd" );
    copy( "imapd-ssl.dist",       "imapd-ssl" )    if ( !-e "imapd-ssl" );
    copy( "quotawarnmsg.example", "quotawarnmsg" ) if ( !-e "quotawarnmsg" );

    if ( $ver ne "port" ) {

        #   The courier port *finally* has working startup files installed
        #         this stuff is no longer necessary

        unless ( -e "$confdir/rc.d/imapd.sh" ) {
            copy( "$libe/imapd.rc", "$confdir/rc.d/imapd.sh" );
            $utility->file_chmod(
                file => "$confdir/rc.d/imapd.sh",
                mode => '0755',
                debug => $debug,
            );

            if ( $conf->{'pop3_daemon'} eq "courier" ) {
                copy( "$libe/pop3d.rc", "$confdir/rc.d/pop3d.sh" );
                $utility->file_chmod(
                    file => "$confdir/rc.d/pop3d.sh",
                    mode => '0755',
                    debug => $debug,
                );
            }
        }

        copy( "$libe/imapd-ssl.rc", "$confdir/rc.d/imapd-ssl.sh" );
        $utility->file_chmod(
            file => "$confdir/rc.d/imapd-ssl.sh",
            mode => '0755',
            debug => $debug,
        );
        copy( "$libe/pop3d-ssl.rc", "$confdir/rc.d/pop3d-ssl.sh" );
        $utility->file_chmod(
            file => "$confdir/rc.d/pop3d-ssl.sh",
            mode => '0755',
            debug => $debug,
        );
    }

    # apply ssl_ values from t-w.conf to courier's .cnf files
    if ( ! -e "$share/pop3d.pem" || ! -e "$share/imapd.pem" ) {
        my $pop3d_ssl_conf = "$confdir/courier-imap/pop3d.cnf";
        my $imapd_ssl_conf = "$confdir/courier-imap/imapd.cnf";

        my $common_name = $conf->{'ssl_common_name'} || $conf->{'toaster_hostname'};
        my $org      = $conf->{'ssl_organization'};
        my $locality = $conf->{'ssl_locality'};
        my $state    = $conf->{'ssl_state'};
        my $country  = $conf->{'ssl_country'};

        my $sed_command = "sed -i .bak -e 's/US/$country/' ";
        $sed_command .= "-e 's/NY/$state/' ";
        $sed_command .= "-e 's/New York/$locality/' ";
        $sed_command .= "-e 's/Courier Mail Server/$org/' ";
        $sed_command .= "-e 's/localhost/$common_name/' ";

        warn "running $sed_command\n" if $debug;

        system "$sed_command $pop3d_ssl_conf $imapd_ssl_conf";
    };

    # generate the SSL certificates for pop3/imap
    if ( !-e "$share/pop3d.pem" ) {
        chdir $share;
        $utility->syscmd( command => "./mkpop3dcert", debug => 0 );
    }

    unless ( -e "$share/imapd.pem" ) {
        chdir $share;
        $utility->syscmd( command => "./mkimapdcert", debug => 0 );
    }

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {

        unless ( -e "$prefix/sbin/imap" ) {
            symlink( "$confdir/rc.d/courier-imap-imapd.sh",
                "$prefix/sbin/imap" );
            symlink( "$confdir/rc.d/courier-imap-pop3d.sh",
                "$prefix/sbin/pop3" );
            symlink( "$confdir/rc.d/courier-imap-imapd-ssl.sh",
                "$prefix/sbin/imapssl" );
            symlink( "$confdir/rc.d/courier-imap-pop3d-ssl.sh",
                "$prefix/sbin/pop3ssl" );
        }

        $freebsd->rc_dot_conf_check(
            check => "courier_imap_imapd_enable",
            line  => q{courier_imap_imapd_enable="YES"},
            debug => $debug,
        );

        $freebsd->rc_dot_conf_check(
            check => "courier_imap_imapdssl_enable",
            line  => "courier_imap_imapdssl_enable=\"YES\"",
            debug => $debug,
        );

        $freebsd->rc_dot_conf_check(
            check => "courier_imap_imapd_ssl_enable",
            line  => "courier_imap_imapd_ssl_enable=\"YES\"",
            debug => $debug,
        );

        if ( $conf->{'pop3_daemon'} eq "courier" ) {
            $freebsd->rc_dot_conf_check(
                check => "courier_imap_pop3d_enable",
                line  => "courier_imap_pop3d_enable=\"YES\"",
                debug => $debug,
            );
        }

        $freebsd->rc_dot_conf_check(
            check => "courier_imap_pop3dssl_enable",
            line  => "courier_imap_pop3dssl_enable=\"YES\"",
            debug => $debug,
        );

        $freebsd->rc_dot_conf_check(
            check => "courier_imap_pop3d_ssl_enable",
            line  => "courier_imap_pop3d_ssl_enable=\"YES\"",
            debug => $debug,
        );
    }
    else {

        if ( -e "$libe/imapd.rc" ) {

            print "creating symlinks in /usr/local/sbin for courier daemons\n";

            symlink( "$libe/imapd.rc",     "$prefix/sbin/imap" );
            symlink( "$libe/pop3d.rc",     "$prefix/sbin/pop3" );
            symlink( "$libe/imapd-ssl.rc", "$prefix/sbin/imapssl" );
            symlink( "$libe/pop3d-ssl.rc", "$prefix/sbin/pop3ssl" );
        }
        else {
            print
              "FAILURE: sorry, I can't find the courier rc files on $OSNAME.\n";
        }
    }

    unless ( -e "/var/run/imapd-ssl.pid" ) {
        $utility->syscmd( command => "$prefix/sbin/imapssl start", debug=>$debug )
          if ( -x "$prefix/sbin/imapssl" );
    }

    unless ( -e "/var/run/imapd.pid" ) {
        $utility->syscmd( command => "$prefix/sbin/imap start", debug=>$debug )
          if ( -x "$prefix/sbin/imapssl" );
    }

    unless ( -e "/var/run/pop3d-ssl.pid" ) {
        $utility->syscmd( command => "$prefix/sbin/pop3ssl start", debug=>$debug )
          if ( -x "$prefix/sbin/pop3ssl" );
    }

    if ( $conf->{'pop3_daemon'} eq "courier" ) {

        unless ( -e "/var/run/pop3d.pid" ) {

            $utility->syscmd( command => "$prefix/sbin/pop3 start", debug=>$debug )
              if ( -x "$prefix/sbin/pop3" );
        }
    }

    my $authrc = "$confdir/authlib/authdaemonrc";

    if ( -e $authrc ) {

        # remove the extra authentication types
        my @lines = $utility->file_read( file => $authrc, debug=>$debug );
        foreach my $line (@lines) {
            if ( $line =~ /^authmodulelist=\"authuserdb/ ) {
                $utility->_formatted( "courier_startup: fixed up $authrc",
                    "ok" );

                $line = 'authmodulelist="authvchkpw"';
            }
        }
        $utility->file_write( file => $authrc, lines => \@lines, debug=>$debug );
    }
}

sub cpan {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( $OSNAME eq "freebsd" ) {

        $freebsd->port_install( 
            port => "p5-Net-DNS",    
            base => "dns",
            options => "#
# This file was generated by mail-toaster
# Options for p5-Net-DNS-0.58
_OPTIONS_READ=p5-Net-DNS-0.58
WITHOUT_IPV6=true",
            debug => $debug,
        );

        $freebsd->port_install( 
            port => "p5-Params-Validate",
            base => "devel",
            debug => $debug,
        );
    }
    elsif ( $OSNAME eq "darwin" ) {
        if ( $utility->find_the_bin( bin => "port", debug=>$debug ) ) {
            my @dports = qw(
              p5-net-dns   p5-html-template   p5-compress-zlib
              p5-timedate  p5-params-validate
            );

            # p5-mail-tools
            foreach (@dports) {
                $darwin->port_install( port_name => $_, debug=>$debug );
            }
        }
    }
    else {
        print "no ports for $OSNAME, installing from CPAN.\n";
    }

    # the module_load function will attempt to load the module. If it succeeds
    # then it will return success. If it fails, it will attempt to install it
    # using CPAN. If running on FreeBSD and port_ settings are provided, it
    # will install from ports. If we were really wild and crazy, we could also
    # send along a site and URL to download the sources from manually.

    $perl->module_load( 
        module     => "Params::Validate",
        port_name  => "p5-Params-Validate",
        port_group => "devel",
        auto       => 1,
        debug      => $debug,
    );

    $perl->module_load( 
        module => "Compress::Zlib",
        port_name => "p5-Compress-Zlib",
        port_group => "archivers",
        auto       => 1,
        debug      => $debug,
    );

    $perl->module_load( 
        module     => "Crypt::PasswdMD5",
        port_name  => "p5-Crypt-PasswdMD5",
        port_group => "security",
        auto       => 1,
        debug      => $debug,
    );

    $perl->module_load( 
        module     => "HTML::Template",
        port_name  => "p5-HTML-Template", 
        port_group => "www",
        auto       => 1,
        debug      => $debug,
    ) if ( $conf->{'toaster_old_index_cgi'} );

    $perl->module_load( module => "Net::DNS" );

    $perl->module_load( 
        module     => "Quota",
        port_name  => "p5-Quota",
        port_group => "sysutils",
        fatal      => 0,
        auto       => 1,
        debug      => $debug,
    ) if $conf->{'install_quota_tools'};

    $perl->module_load( 
        module => "Date::Format",
        port_name => "p5-TimeDate",
        port_group => "devel",
        auto       => 1,
        debug  => $debug,
    );

    $perl->module_load( module => "Date::Parse", debug=>$debug, auto=>1 );

    $perl->module_load( 
        module     => "Mail::Send",
        port_name  => "p5-Mail-Tools",
        port_group => "mail",
        auto       => 1,
        debug      => $debug,
    );
}

sub cronolog {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_cronolog'};
    unless ($ver) {
        $utility->_formatted( "cronolog: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {

        if ( $freebsd->is_port_installed( port => "cronolog", debug=>$debug ) ) {
            $utility->_formatted( "cronolog: install cronolog", "ok (exists)" )
              if $debug;
            return 2;
        }

        $freebsd->port_install(
            port  => "cronolog",
            base  => "sysutils",
            fatal => 0,
        );

        if ( $freebsd->is_port_installed( port => "cronolog", debug=>$debug ) ) {
            $utility->_formatted( "cronlog: install cronolog", "ok" ) if $debug;
            return 1;
        }

        print "NOTICE: port install of cronolog failed!\n";
    }

    if ( $utility->find_the_bin( bin => "cronolog", debug => 0, fatal => 0 ) ) {
        $utility->_formatted( "cronolog: install cronolog", "ok (exists)" )
          if $debug;
        return 2;
    }

    print "attempting to install cronolog from sources!\n";

    if ( $ver eq "port" ) { $ver = "1.6.2" }
    ;    # a fallback version

    $utility->install_from_source(
        conf    => $conf,
        package => "cronolog-$ver",
        site    => 'http://www.cronolog.org',
        url     => '/download',
        targets => [ './configure', 'make', 'make install' ],
        bintest => 'cronolog',
        debug   => $debug,
    );

    if ( $utility->find_the_bin( bin => "cronolog" ) ) {
        $utility->_formatted( "cronolog: install cronolog", "ok" );
        return 1;
    }

    return 0;
}

sub daemontools {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_daemontools'};

    unless ($ver) {
        $utility->_formatted( "daemontools: installing", "skipping (disabled)" )
          if $debug;
        return;
    }

    # used for 'make test' testing.
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # if we should install the port version, see if it is already installed
    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {
        $freebsd->port_install(
            port  => "daemontools",
            base  => "sysutils",
            debug => $debug,
            fatal => 0,
        );

        return 1
          if $freebsd->is_port_installed( port => "daemontools", debug => 0, fatal=>0 );

        print "NOTICE: port install of daemontools failed!\n";
    }

    if ( $OSNAME eq "darwin" && $ver eq "port" ) {
        $darwin->port_install( port_name => "daemontools" );

        print
"\a\n\nWARNING: there is a bug in the OS 10.4 kernel that requires daemontools to be built with a special tweak. This must be done once. You will be prompted to install daemontools now. If you haven't already allowed this script to build daemontools from source, please do so now!\n\n";
        sleep 2;
    }

    # see if the svscan binary is already installed
    if ( -x $utility->find_the_bin( bin => "svscan", fatal => 0, debug => 0 ) )
    {
        $utility->_formatted( "daemontools: installing", "ok (exists)" )
          if $debug;
        return 1;
    }

    if ( $ver eq "port" ) { $ver = "0.76" }

    my $package = "daemontools-$ver";
    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";

    my @targets = ('package/install');
    my @patches;
    my $patch_args = "";    # cannot be undef

    if ( $OSNAME eq "darwin" ) {
        print "daemontools: applying fixups for Darwin.\n";
        @targets = (
            "echo cc -Wl,-x > src/conf-ld",
            "echo $prefix/bin > src/home",
            "echo x >> src/trypoll.c",
            "cd src",
            "make",
        );
    }
    elsif ( $OSNAME eq "linux" ) {
        print "daemontools: applying fixups for Linux.\n";
        @patches    = ('daemontools-0.76.errno.patch');
        $patch_args = "-p0";
    }
    elsif ( $OSNAME eq "freebsd" ) {
        @targets = (
            'echo "' . $conf->{'toaster_prefix'} . '" > src/home',
            "cd src", "make",
        );
    }

    $utility->install_from_source(
        conf       => $conf,
        package    => $package,
        site       => 'http://cr.yp.to',
        url        => '/daemontools',
        targets    => \@targets,
        patches    => \@patches,
        patch_args => $patch_args,
        bintest    => 'svscan',
        debug      => $debug,
    );

    if ( $OSNAME eq "darwin" or $OSNAME eq "freebsd" ) {

        # manually install the daemontools binaries in $prefix/local/bin
        chdir "$conf->{'toaster_src_dir'}/admin/$package";

        foreach ( $utility->file_read( file => "package/commands",debug=>0 ) ) {
            my $install =
              $utility->find_the_bin( bin => 'install', debug => 0 );
            $utility->syscmd( command => "$install src/$_ $prefix/bin", debug=>0 );
        }
    }

    return 1;
}

sub daemontools_test {

    my ($self) = shift;
    shift;
    my ($debug) = shift;

    print "checking daemontools binaries...\n";
    foreach my $bin_test ( qw{ multilog softlimit setuidgid supervise svok svscan tai64nlocal } )
    {
        my $bin = $utility->find_the_bin( bin => $bin_test, fatal => 0, debug=>$debug );

        -x $bin ? $utility->_formatted( "\t$bin_test", "ok" )
                : $utility->_formatted( "\t$bin_test", "FAILED" );
    };

    return;
}

sub dependencies {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation here
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # we do not want to try installing anything during "make test"
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # install the prereq perl modules
    $self->cpan(  debug => $debug );

    if ( $OSNAME eq "freebsd" ) {

        my $package = $conf->{'package_install_method'} || "packages";

        # check for perl suid (if required)
        $self->perl_suid_check( );

        # create /etc/periodic.conf if it does not exist.
        $self->periodic_conf();

        # if package method is selected, try it
        if ( $package eq "packages" ) {
            $freebsd->package_install( debug => $debug, port => "openssl" )
              if $conf->{'install_openssl'};
            $freebsd->package_install( debug => $debug, port => "ispell" )
              if $conf->{'install_ispell'};
            $freebsd->package_install( debug => $debug, port => "gdbm" );
            $freebsd->package_install( debug => $debug, port => "setquota" )
              if $conf->{'install_quota_tools'};
            $freebsd->package_install( debug => $debug, port => "gmake" );
            $freebsd->package_install( debug => $debug, port => "cronolog" );
        }


        my @ports_to_install = { port  => "gettext",
                base  => "devel",
                flags => "BATCH=yes WITHOUT_GETTEXT_OPTIONS=1",
                options => "#
# This file was generated by mail-toaster
# Options for gettext-0.14.5_2
_OPTIONS_READ=gettext-0.14.5_2
WITHOUT_EXAMPLES=true
WITHOUT_HTMLMAN=true\n",
            };

        push @ports_to_install, (
            { port => "gmake", base => "devel"     },
            { port => "gdbm",  base => "databases" },
            { port => "p5-Params-Validate",  base => "devel" },
        );

        push @ports_to_install, { port => "openssl", base => "security" }
          if $conf->{'install_openssl'};

        push @ports_to_install, { port => "ispell", base => "textproc" }
          if $conf->{'install_ispell'};

        push @ports_to_install, { port => "setquota", base => "sysutils" }
          if $conf->{'install_quota_tools'};

        push @ports_to_install, {
            port  => "openldap23-client",
            base  => "net",
            check => "openldap-client",
          } if $conf->{'install_openldap_client'};

        push @ports_to_install, { port => "portaudit", base => "security" }
          if $conf->{'install_portaudit'};

        push @ports_to_install, { 
            port => "stunnel", 
            base => "security",
            options => "#
# This file was generated by mail-toaster
# No user-servicable parts inside!
# Options for stunnel-4.15
_OPTIONS_READ=stunnel-4.15
WITHOUT_FORK=true
WITH_PTHREAD=true
WITHOUT_UCONTEXT=true
WITHOUT_IPV6=true",
        } if ( ! $conf->{'pop3_ssl_daemon'} eq "courier" );

        push @ports_to_install, {
            port    => "ucspi-tcp",
            base    => "sysutils",
            options => "#
# This file is auto-generated by 'make config'.
# No user-servicable parts inside!
# Options for ucspi-tcp-0.88_2
_OPTIONS_READ=ucspi-tcp-0.88_2
WITHOUT_MAN=true
WITHOUT_RSS_DIFF=true
WITHOUT_SSL=true
WITHOUT_RBL2SMTPD=true",
        };

        push @ports_to_install, { 
            port   => "cronolog",
            base    => "sysutils",
            options => "#
# This file is auto-generated by 'make config'.
# No user-servicable parts inside!
# Options for cronolog-1.6.2_1
_OPTIONS_READ=cronolog-1.6.2_1
WITHOUT_SETUID_PATCH=true",
        };

        push @ports_to_install, { 
            port => "qmail", 
            base => "mail", 
            flags => "BATCH=yes",
            options => "#
# Installed by Mail::Toaster 5.0
_OPTIONS_READ=qmail-1.03_5
WITHOUT_SMTP_AUTH_PATCH=true
WITHOUT_QMAILQUEUE_PATCH=true
WITHOUT_BIG_TODO_PATCH=true
WITHOUT_BIG_CONCURRENCY_PATCH=true
WITHOUT_OUTGOINGIP_PATCH=true
WITHOUT_LOCALTIME_PATCH=true
WITHOUT_QMTPC_PATCH=true
WITHOUT_MAILDIRQUOTA_PATCH=true
WITHOUT_BLOCKEXEC_PATCH=true
WITHOUT_DISCBOUNCES_PATCH=true
WITHOUT_SPF_PATCH=true
WITHOUT_TARPIT_PATCH=true
WITHOUT_RCDLINK=true
WITHOUT_SETUID_PATCH=true",
        };

        push @ports_to_install, { port => "qmailanalog", base => "mail", fatal => 0 };

        push @ports_to_install, { port => "qmail-notify", base => "mail", fatal => 0 }
          if $conf->{'install_qmail_notify'};


        foreach my $port (@ports_to_install) {

            my $fatal_l = defined $port->{'fatal'}  ? $port->{'fatal'}  : $fatal;
            my $flags   = defined $port->{'flags'}  ? $port->{'flags'}  : q{};
            my $options = defined $port->{'options'}? $port->{'options'}: q{};
            my $check   = defined $port->{'check'}  ? $port->{'check'}  : q{};

            $freebsd->port_install(
                port    => $port->{'port'},
                base    => $port->{'base'},
                flags   => $flags,
                options => $options,
                check   => $check,
                debug   => $debug,
                fatal   => $fatal_l,
            );
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        my @dports =
          qw( cronolog gdbm gmake gnupg ucspi-tcp daemontools DarwinPortsStartup );

        push @dports, qw/aspell aspell-dict-en/ if $conf->{'install_aspell'};
        push @dports, "ispell"   if $conf->{'install_ispell'};
        push @dports, "maildrop" if $conf->{'install_maildrop'};
        push @dports, "openldap" if $conf->{'install_openldap_client'};

        foreach (@dports) { $darwin->port_install( port_name => $_ ) }
    }
    else {
        print "no ports for $OSNAME, installing from sources.\n";

        if ( $OSNAME eq "linux" ) {
            my $qmaildir = $conf->{'qmail_dir'} || "/var/qmail";
            my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

            $utility->syscmd( command => "groupadd qnofiles", debug=>0 );
            $utility->syscmd( command => "groupadd qmail", debug=>0 );
            $utility->syscmd( command => "groupadd -g 89 vchkpw", debug=>0 );
            $utility->syscmd(
                command => "useradd -g vchkpw -d $vpopdir vpopmail", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qnofiles -d $qmaildir/alias alias", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qnofiles -d $qmaildir qmaild", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qnofiles -d $qmaildir qmaill", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qnofiles -d $qmaildir qmailp", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qmail    -d $qmaildir qmailq", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qmail    -d $qmaildir qmailr", debug=>0 );
            $utility->syscmd(
                command => "useradd -g qmail    -d $qmaildir qmails", debug=>0 );
            $utility->syscmd( command => "groupadd clamav", debug=>0 );
            $utility->syscmd( command => "useradd -g clamav clamav", debug=>0 );
        }

        my @progs = qw(gmake expect gnupg cronolog autorespond );
        push @progs, "setquota" if $conf->{'install_quota_tools'};
        push @progs, "ispell" if $conf->{'install_ispell'};

        foreach (@progs) {
            if ( $utility->find_the_bin( bin => $_, debug=>0 ) ) {
                $utility->formatted( "checking for $_", "ok" );
            }
            else {
                print "$_ not installed. FAILED, please install manually.\n";
            }
        }
    }

    unless ( -x "/var/qmail/bin/qmail-queue" ) {
        $conf->{'qmail_chk_usr_patch'} = 0;
        require Mail::Toaster::Qmail;
        my $qmail   = Mail::Toaster::Qmail->new();
        $qmail->netqmail_virgin( conf => $conf, debug=>0 );
    }

    $self->daemontools(  debug => $debug );
    $self->autorespond(  debug => $debug );
}

sub djbdns {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $tinydns;

    if ( !$conf->{'install_djbdns'} ) {
        $utility->_formatted( "djbdns: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    $self->daemontools(  debug=>$debug );
    $self->ucspi_tcp(  debug=>$debug );

    # test to see if it is installed.
    if ( -x $utility->find_the_bin( bin => 'tinydns', fatal => 0, debug=>$debug ) ) {
        $utility->_formatted( "djbdns: installing djbdns",
            "ok (already installed)" );
        return 1;
    }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "djbdns", base => "dns", debug=>$debug );

        # test to see if it installed.
        if ( -x $utility->find_the_bin( bin => 'tinydns', fatal => 0, debug=>$debug ) ) {
            $utility->_formatted( "djbdns: installing djbdns", "ok" );
            return 1;
        }
    }

    my @targets = ( 'make', 'make setup check' );

    if ( $OSNAME eq "linux" ) {
        unshift @targets,
          'echo gcc -O2 -include /usr/include/errno.h > conf-cc';
    }

    $utility->install_from_source(
        conf    => $conf,
        package => "djbdns-1.05",
        site    => 'http://cr.yp.to',
        url     => '/djbdns',
        targets => \@targets,
        bintest => 'tinydns',
        debug   => $debug,
    );
}

sub docs {

    my $cmd;
    my $debug = 1;

    if ( !-f "README" && !-f "lib/toaster.conf.pod" ) {
        print <<"EO_NOT_IN_DIST_ERR";

   ERROR: This setup target can only be run in the Mail::Toaster distibution directory!

    Try switching into there and trying again.
EO_NOT_IN_DIST_ERR

        return;
    };

    # convert pod to text files
    my $pod2text = $utility->find_the_bin(bin=>"pod2text", debug=>0);

    $utility->syscmd(cmd=>"$pod2text bin/toaster_setup.pl       > README", debug=>0);
    $utility->syscmd(cmd=>"$pod2text lib/toaster.conf.pod          > doc/toaster.conf", debug=>0);
    $utility->syscmd(cmd=>"$pod2text lib/toaster-watcher.conf.pod  > doc/toaster-watcher.conf", debug=>0);


    # convert pod docs to HTML pages for the web site

    my $pod2html = $utility->find_the_bin(bin=>"pod2html", debug=>0);

    $utility->syscmd(
        cmd=>"$pod2html --title='toaster.conf' lib/toaster.conf.pod > doc/toaster.conf.html", 
        debug=>0, );
    $utility->syscmd(
        cmd=>"$pod2html --title='watcher.conf' lib/toaster-watcher.conf.pod  > doc/toaster-watcher.conf.html", 
        debug=>0, );
    $utility->syscmd(
        cmd=>"$pod2html --title='mailadmin' bin/mailadmin > doc/mailadmin.html", 
        debug=>0, );

    my @modules = qw/ Toaster   Apache  CGI     Darwin   DNS 
            Ezmlm     FreeBSD   Logs    Mysql   Passwd   Perl 
            Provision Qmail     Setup   Utility /;

    MODULE:
    foreach my $module (@modules ) {
        if ( $module =~ m/\AToaster\z/ ) {
            $cmd = "$pod2html --title='Mail::Toaster' lib/Mail/$module.pm > doc/modules/$module.html";
            print "$cmd\n" if $debug;
            next MODULE;
            $utility->syscmd( command=>$cmd, debug=>0 );
        };

        $cmd = "$pod2html --title='Mail::Toaster::$module' lib/Mail/Toaster/$module.pm > doc/modules/$module.html";
        warn "$cmd\n" if $debug;
        $utility->syscmd( command=>$cmd, debug=>0 );
    };

    unlink <pod2htm*>;
    #$utility->syscmd(cmd=>"rm pod2html*");
};

sub enable_all_spam {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my $qmail_dir = $conf->{'qmail_dir'} || "/var/qmail";
    my $spam_cmd  = $conf->{'qmailadmin_spam_command'} || 
        '| /usr/local/bin/maildrop /usr/local/etc/mail/mailfilter';

    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    my @domains = $qmail->get_domains_from_assign(
            assign => "$qmail_dir/users/assign",
            debug  => $debug
        );

    my $number_of_domains = @domains;
    print "enable_all_spam: found $number_of_domains domains.\n" if $debug;

    for (my $i = 0; $i < $number_of_domains; $i++) {

        my $domain = $domains[$i]{'dom'};
        print "Enabling spam processing for $domain mailboxes...\n" if $debug;

        my @paths = `~vpopmail/bin/vuserinfo -d -D $domain`;

        PATH:
        foreach my $path (@paths) {
            chomp($path);
            if ( ! $path || ! -d $path) {
                print "$path does not exist!\n";
                next PATH;
            };

            my $qpath = "$path/.qmail";
            if (-f $qpath) {
                print ".qmail already exists in $path.\n";
            } else {
                print ".qmail created in $path.\n";
                system "echo $spam_cmd >> $path/.qmail";
            }
        }
    }

    return 1;
}

sub expat {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( !$conf->{'install_expat'} ) {
        $utility->_formatted( "expat: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    if ( $OSNAME eq "freebsd" ) {
        if ( -d "/usr/ports/textproc/expat" ) {
            $freebsd->port_install( port => "expat", base => "textproc" );
        }
        else {
            $freebsd->port_install(
                port => "expat",
                base => "textproc",
                dir  => 'expat2'
            );
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        $darwin->port_install( port_name => "expat" );
    }
    else {
        print "Sorry, build support for expat on $OSNAME is incomplete.\n";
    }
}

sub expect {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install(
            port  => "expect",
            base  => "lang",
            flags => "WITHOUT_X11=yes",
            debug => $debug,
            fatal => $fatal,
        );
    }
}

sub ezmlm {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver     = $conf->{'install_ezmlm'};
    my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";

    if ( !$ver ) {
        $utility->_formatted( "installing Ezmlm-Idx", "skipping (disabled)" )
          if $debug;
        return;
    }

    my $ezmlm = $utility->find_the_bin(
        bin   => 'ezmlm-sub',
        dir   => '/usr/local/bin/ezmlm',
        debug => $debug,
        fatal => 0
    );

    # if it is already installed
    if ( $ezmlm && -x $ezmlm ) {
        $utility->_formatted( "installing Ezmlm-Idx",
            "ok (already installed)" );

        return $self->ezmlm_cgi(  debug=>$debug );
    }

    if (   $OSNAME eq "freebsd"
        && $ver eq "port"
        && !$freebsd->is_port_installed( port => "ezmlm", debug=>$debug, fatal=>0 ) )
    {
        $self->ezmlm_makefile_fixup( );

        my $defs = "";
        $defs .= "WITH_MYSQL=yes" if ( $conf->{'install_ezmlm_mysql'} );

        if ( $freebsd->port_install(
                port  => "ezmlm-idx",
                base  => "mail",
                flags => $defs,
                debug => $debug,
            )
          )
        {
            chdir("$confdir/ezmlm");
            copy( "ezmlmglrc.sample", "ezmlmglrc" )
              or croak "ezmlm: copy ezmlmglrc failed: $!";

            copy( "ezmlmrc.sample", "ezmlmrc" )
              or croak "ezmlm: copy ezmlmrc failed: $!";

            copy( "ezmlmsubrc.sample", "ezmlmsubrc" )
              or croak "ezmlm: copy ezmlmsubrc failed: $!";

            return $self->ezmlm_cgi(  debug=>$debug );
        }

        print "\n\nFAILURE: ezmlm-idx install failed!\n\n";
        return;
    }

    print "ezmlm: attemping to install ezmlm from sources.\n";

    my $ezmlm_dist = "ezmlm-0.53";
    my $idx     = "ezmlm-idx-$ver";
    my $site    = "http://www.ezmlm.org";
    my $src     = $conf->{'toaster_src_dir'} || "/usr/local/src/mail";
    my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";
    my $cgi     = $conf->{'qmailadmin_cgi-bin_dir'};

    $cgi =
      -d $cgi
      ? $cgi
      : $toaster->get_toaster_cgibin( conf => $conf );

    # try to figure out where to install the CGI

    $utility->chdir_source_dir( dir => "$src/mail" );

    if ( -d $ezmlm_dist ) {
        unless (
            $utility->source_warning( package => $ezmlm_dist, src => "$src/mail" ) )
        {
            carp "\nezmlm: OK then, skipping install.\n";
            return 0;
        }
        else {
            print "ezmlm: removing any previous build sources.\n";
            $utility->syscmd( command => "rm -rf $ezmlm_dist" )
              ;    # nuke any old versions
        }
    }

    unless ( -e "$ezmlm_dist.tar.gz" ) {
        $utility->file_get( url => "$site/archive/$ezmlm_dist.tar.gz", debug=>$debug );
    }

    unless ( -e "$idx.tar.gz" ) {
        $utility->file_get( url => "$site/archive/$ver/$idx.tar.gz", debug=>$debug );
    }

    $utility->archive_expand( archive => "$ezmlm_dist.tar.gz", debug => $debug )
      or croak "Couldn't expand $ezmlm_dist.tar.gz: $!\n";

    $utility->archive_expand( archive => "$idx.tar.gz", debug => $debug )
      or croak "Couldn't expand $idx.tar.gz: $!\n";

    $utility->syscmd( command => "mv $idx/* $ezmlm_dist/", debug=>$debug );
    $utility->syscmd( command => "rm -rf $idx", debug=>$debug );

    chdir($ezmlm_dist);

    $utility->syscmd( command => "patch < idx.patch", debug=>$debug );

    if ( $OSNAME eq "darwin" ) {
        my $local_include = "/usr/local/mysql/include";
        my $local_lib     = "/usr/local/mysql/lib";

        if ( !-d $local_include ) {
            $local_include = "/opt/local/include/mysql";
            $local_lib     = "/opt/local/lib/mysql";
        }

        $utility->file_write(
            file  => "sub_mysql/conf-sqlcc",
            lines => ["-I$local_include"],
            debug => $debug,
        );

        $utility->file_write(
            file  => "sub_mysql/conf-sqlld",
            lines => ["-L$local_lib -lmysqlclient -lm"],
            debug => $debug,
        );
    }
    elsif ( $OSNAME eq "freebsd" ) {
        $utility->file_write(
            file  => "sub_mysql/conf-sqlcc",
            lines => ["-I/usr/local/include/mysql"],
            debug => $debug,
        );

        $utility->file_write(
            file  => "sub_mysql/conf-sqlld",
            lines => ["-L/usr/local/lib/mysql -lmysqlclient -lnsl -lm"],
            debug => $debug,
        );
    }

    $utility->file_write( file => "conf-bin", lines => ["/usr/local/bin"], debug=>$debug );
    $utility->file_write( file => "conf-man", lines => ["/usr/local/man"], debug=>$debug );
    $utility->file_write( file => "conf-etc", lines => ["/usr/local/etc"], debug=>$debug );

    $utility->syscmd( command => "make", debug=>$debug );

    $utility->syscmd( command => "chmod 775 makelang", debug=>$debug );

#$utility->syscmd( command=>"make mysql" );  # haven't figured this out yet (compile problems)
    $utility->syscmd( command => "make man", debug=>$debug );
    $utility->syscmd( command => "make setup", debug=>$debug );

    $self->ezmlm_cgi(  debug=>$debug );
    return 1;
}

sub ezmlm_cgi {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    return unless ( $conf->{'install_ezmlm_cgi'} );

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( 
            port => "p5-Archive-Tar", 
            base => "archivers", 
            debug=>0, 
            options=>"#
# This file was generated by Mail::Toaster
# No user-servicable parts inside!
# Options for p5-Archive-Tar-1.30
_OPTIONS_READ=p5-Archive-Tar-1.30
WITHOUT_TEXT_DIFF=true", 
        );
    }

    $perl->module_load( 
        module     => "Email::Valid", 
        port_name  => "p5-Email-Valid",
        port_group => "mail",
        auto       => 1,
        debug      => 0,
    );

    $perl->module_load( 
        module     => "Mail::Ezmlm", 
        port_name  => "p5-Mail-Ezmlm",
        port_group => "mail",
        auto       => 1,
        debug      => 0,
    );

    return 1;
}

sub ezmlm_makefile_fixup {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $file = "/usr/ports/mail/ezmlm-idx/Makefile";

    # fix a problem in the ports Makefile (no longer necessary as of 7/21/06)
    my $mysql = $conf->{'install_ezmlm_mysql'};

    return 1 if ( $mysql == 323 || $mysql == 3 );
    return 1 if ( ! `grep mysql323 $file`);

    my @lines = $utility->file_read( file => $file, debug=>0 );
    foreach (@lines) {
        if ( $_ =~ /^LIB_DEPENDS\+\=\s+mysqlclient.10/ ) {
            $_ = "LIB_DEPENDS+=  mysqlclient.12:\${PORTSDIR}/databases/mysql40-client";
        }
    }
    $utility->file_write( file => $file, lines => \@lines, debug=>0 );
}

sub filtering {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) {

        $self->maildrop(debug=>$debug) if ( $conf->{'install_maildrop'} );

        $freebsd->port_install( 
            port   => "p5-Archive-Tar", 
            base   => "archivers", 
            debug  => $debug,
			options=> "# This file was generated by mail-toaster
# No user-servicable parts inside!
# Options for p5-Archive-Tar-1.30
_OPTIONS_READ=p5-Archive-Tar-1.30
WITHOUT_TEXT_DIFF=true",
        );

        $freebsd->port_install( 
            port => "p5-Mail-Audit", 
            base => "mail", 
            debug=>$debug,
        );

        $freebsd->port_install( port => "unzip", base => "archivers", debug=>$debug );

        $self->razor(  debug=>$debug );

        $freebsd->port_install( port => "pyzor", base => "mail", debug=>$debug )
          if $conf->{'install_pyzor'};

        $freebsd->port_install( port => "bogofilter", base => "mail", debug=>$debug )
          if $conf->{'install_bogofilter'};

        $freebsd->port_install(
            port  => "dcc-dccd",
            base  => "mail",
            flags => "WITHOUT_SENDMAIL=1", 
            debug => $debug,
        ) if $conf->{'install_dcc'};

        $freebsd->port_install( port => "procmail", base => "mail", debug=>$debug )
          if $conf->{'install_procmail'};

        $freebsd->port_install( port => "p5-Email-Valid", base => "mail", debug=>$debug );
    }

    $self->spamassassin ( debug=>$debug );
    $self->razor        ( debug=>$debug );
    $self->clamav       ( debug=>$debug );
    $self->qmail_scanner( debug=>$debug );
    $self->simscan      ( debug=>$debug );
}

sub filtering_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    $self->qmail_scanner_test( );
    $self->simscan_test( );

    print "\n\nFor more ways to test your Virus scanner, go here: 
\n\t http://www.testvirus.org/\n\n";
}

sub horde {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

}

sub imap_test_auth {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    print "imap_test_auth: checking Mail::IMAPClient ........................ ";
    $perl->module_load(
        module     => "Mail::IMAPClient",
        port_name  => 'p5-Mail-IMAPClient',
        port_group => 'mail',
        auto       => 1,
        debug      => 0,
    );
    print "ok\n";

    my $user = $conf->{'toaster_test_email'}      || 'test2@example.com';
    my $pass = $conf->{'toaster_test_email_pass'} || 'cHanGeMe';

    # test a plain password auth
    my $mess = "imap_test_auth: authenticate IMAP user with plain passwords";
    my $imap = Mail::IMAPClient->new(
        User     => $user,
        Password => $pass,
        Server   => 'localhost'
    );
    if ( !defined $imap ) {
        $utility->_formatted( $mess, "FAILED" );
    }
    else {
        $imap->IsAuthenticated()
          ? $utility->_formatted( $mess, "ok" )
          : $utility->_formatted( $mess, "FAILED" );

        my @features = $imap->capability
          or warn "Couldn't determine capability: $@\n";
        print "Your IMAP server supports: " . join( ",", @features ) . "\n\n"
          if $debug;
        $imap->logout;
    }

    # an authentication that should fail
    $mess = "testing an authentication that should fail";
    $imap = Mail::IMAPClient->new(
        Server => 'localhost',
        User   => 'no_such_user',
        Pass   => 'hi_there_log_watcher'
    );
    $imap->IsConnected() or warn "couldn't connect!\n";
    $imap->IsAuthenticated()
      ? $utility->_formatted( $mess, "FAILED" )
      : $utility->_formatted( $mess, "ok" );
    $imap->logout;

    print "imap_test_auth: checking IO::Socket::SSL ......................... ";
    $perl->module_load(
        module     => "IO::Socket::SSL",
        port_name  => 'p5-IO-Socket-SSL',
        port_group => 'security',
        auto       => 1,
        debug      => 0,
    );
    print "ok\n";

    $mess = "imap_test_auth: auth IMAP SSL with plain password...";
    require IO::Socket::SSL;
    my $socket = IO::Socket::SSL->new(
        PeerAddr => 'localhost',
        PeerPort => 993,
        Proto    => 'tcp'
    ) or warn "couldn't connect.\n";

    if ( defined $socket ) {
        print $socket->get_cipher() . "...";
        print $socket ". login $user $pass\n";
        my $r = $socket->peek;
        print "server returned: $r\n";
        $r =~ /OK/
          ? $utility->_formatted( $mess, "ok" )
          : $utility->_formatted( $mess, "FAILED" );
        print $socket ". logout\n";
        close $socket;
    }

#  no idea why this doesn't work, so I just forge an authentication by printing directly to the socket
#			my $imapssl = Mail::IMAPClient->new( Socket=>$socket, User=>$user, Password=>$pass) or warn "new IMAP failed: ($@)\n";
#			$imapssl->IsAuthenticated() ? print "ok\n" : print "FAILED.\n";

# doesn't work yet because courier doesn't support CRAM-MD5 via the vchkpw auth module
#	print "authenticating IMAP user with CRAM-MD5...";
#	$imap->connect;
#	$imap->authenticate();
#	$imap->IsAuthenticated() ? print "ok\n" : print "FAILED.\n";
#
#	print "logging out...";
#	$imap->logout;
#	$imap->IsAuthenticated() ? print "FAILED.\n" : print "ok.\n";
#	$imap->IsConnected() ? print "connection open.\n" : print "connection closed.\n";

}

sub is_newer {

    my $self  = shift;
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'min'   => { type => SCALAR },
            'cur'   => { type => SCALAR },
            'debug' => { type => SCALAR, optional => 1, default => $debug },
        },
    );

    my ( $min, $cur ) = ( $p{'min'}, $p{'cur'} );

    $debug = $p{'debug'};

    my @mins = split( q{\.}, $min );
    my @curs = split( q{\.}, $cur );

    #use Data::Dumper;
    #print Dumper(@mins, @curs);

    if ( $curs[0] > $mins[0] ) { return 1; }    # major version num
    if ( $curs[1] > $mins[1] ) { return 1; }    # minor version num
    if ( $curs[2] && $mins[2] && $curs[2] > $mins[2] ) { return 1; }    # revision level
    if ( $curs[3] && $mins[3] && $curs[3] > $mins[3] ) { return 1; }    # just in case

    return 0;
}

sub isoqlog {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => 1 },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_isoqlog'};

    unless ($ver) {
        $utility->_formatted( "isoqlog: ERROR: install_isoqlog is not set!",
            "FAILED" );
        return 0;
    }

    my $return = 0;

    if ( $ver eq "port" ) {
        if ( $OSNAME eq "freebsd" ) {
            if ( $freebsd->is_port_installed( port => "isoqlog", debug=>$debug ) ) {
                $utility->_formatted( "isoqlog: installing.", "ok (exists)" );
                $return = 2;
            }
            else {
                $freebsd->port_install( port => "isoqlog", base => "mail", debug=>$debug );
                if ( $freebsd->is_port_installed( port => "isoqlog", debug=>$debug ) ) {
                    $utility->_formatted( "isoqlog: installing.", "ok" );
                    $return = 1;
                }
            }
        }
        else {
            $utility->_formatted(
                "isoqlog: install_isoqlog = port is not valid for $OSNAME!",
                "FAILED" );
            return 0;
        }
    }
    else {
        if ( -x $utility->find_the_bin( bin => "isoqlog", fatal => 0, debug=>$debug ) ) {
            $utility->_formatted( "isoqlog: installing.", "ok (exists)" );
            $return = 2;
        }
    }

    unless ( -x $utility->find_the_bin( bin => "isoqlog", fatal => 0, debug=>$debug ) ) {
        print
"\nIsoqlog not found. Trying to install v$ver from sources for $OSNAME!\n\n";

        if ( $ver eq "port" || $ver == 1 ) { $ver = 2.2; }

        my $configure = "./configure ";

        if ( $conf->{'toaster_prefix'} ) {
            $configure .= "--prefix=" . $conf->{'toaster_prefix'} . " ";
            $configure .= "--exec-prefix=" . $conf->{'toaster_prefix'} . " ";
        }

        if ( $conf->{'system_config_dir'} ) {
            $configure .= "--sysconfdir=" . $conf->{'system_config_dir'} . " ";
        }

        print "isoqlog: building with $configure.\n";

        $utility->install_from_source(
            conf    => $conf,
            package => "isoqlog-$ver",
            site    => 'http://www.enderunix.org',
            url     => '/isoqlog',
            targets => [ $configure, 'make', 'make install', 'make clean' ],
            patches => '',
            bintest => 'isoqlog',
            debug   => $debug,
            source_sub_dir => 'mail',
        );
    }

    if ( $conf->{'toaster_prefix'} ne "/usr/local" ) {
        symlink( "/usr/local/share/isoqlog",
            $conf->{'toaster_prefix'} . "/share/isoqlog" );
    }
    $return = 1
      if ( -x $utility->find_the_bin( bin => "isoqlog", fatal => 0, debug=>$debug ) );

    $self->isoqlog_conf(  debug=>$debug );
    return $return;
}

sub isoqlog_conf {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # isoqlog doesn't honor --sysconfdir yet
    #my $etc = $conf->{'system_config_dir'} || "/usr/local/etc";
    my $etc  = "/usr/local/etc";
    my $file = "$etc/isoqlog.conf";

    if ( -e $file ) {
        $utility->_formatted( "isoqlog_conf: creating $file", "ok (exists)" );
        return 2;
    }

    my @lines;

    my $htdocs = $conf->{'toaster_http_docs'} || "/usr/local/www/data";
    my $hostn  = $conf->{'toaster_hostname'}  || `hostname`;
    my $logdir = $conf->{'qmail_log_base'}    || "/var/log/mail";
    my $qmaild = $conf->{'qmail_dir'}         || "/var/qmail";
    my $prefix = $conf->{'toaster_prefix'}    || "/usr/local";

    push @lines, <<EO_ISOQLOG;
#isoqlog Configuration file

logtype     = "qmail-multilog"
logstore    = "$logdir/send"
domainsfile = "$qmaild/control/rcpthosts"
outputdir   = "$htdocs/isoqlog"
htmldir     = "$prefix/share/isoqlog/htmltemp"
langfile    = "$prefix/share/isoqlog/lang/english"
hostname    = "$hostn"

maxsender   = 100
maxreceiver = 100
maxtotal    = 100
maxbyte     = 100
EO_ISOQLOG

    $utility->file_write( file => $file, lines => \@lines, debug=>$debug )
      or croak "couldn't write $file: $!\n";
    $utility->_formatted( "isoqlog_conf: creating $file", "ok" );

    $utility->syscmd(
        command => "isoqlog",
        fatal   => 0,
        debug   => $debug,
    );

    unless ( -e "$htdocs/isoqlog" ) {
        mkdir oct('0755'), "$htdocs/isoqlog";
    }

    # what follows is one way to fix the missing images problem. The better
    # way is with an apache alias directive such as:
    # Alias /isoqlog/images/ "/usr/local/share/isoqlog/htmltemp/images/"
    # that is now included in the Apache 2.0 patch

    unless ( -e "$htdocs/isoqlog/images" ) {
        $utility->syscmd( 
            command =>"cp -r /usr/local/share/isoqlog/htmltemp/images $htdocs/isoqlog/images",
            debug=>$debug,
        );
    }
}

sub logmonster {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $perlbin = $utility->find_the_bin( bin => "perl", debug => $debug );

    my @targets = ( "$perlbin Makefile.PL", "make", "make install" );
    push @targets, "make test" if $debug;

    $perl->module_install(
        module  => 'Apache-Logmonster',
        archive => 'Logmonster.tar.gz',
        url     => '/internet/www/logmonster',
        targets => \@targets,
        debug   => $debug,
    );
}

sub maildrop {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_maildrop'};

    unless ($ver) {
        print "skipping maildrop install because it's not enabled!\n";
        return 0;
    }

    my $prefix = $conf->{'toaster_prefix'} || "/usr/local";

    if ( $ver eq "port" || $ver eq "1" ) {
        if ( $OSNAME eq "freebsd" ) {
            $freebsd->port_install(
                port  => "maildrop",
                base  => "mail",
                flags => "WITH_MAILDIRQUOTA=1",
                debug => $debug,
            );
        }
        elsif ( $OSNAME eq "darwin" ) {
            $darwin->port_install( port_name => "maildrop", debug=>$debug );
        }
        $ver = "2.0.2";
    }

    if ( !-x $utility->find_the_bin( bin => "maildrop", fatal => 0, debug=>$debug ) ) {

        $utility->install_from_source(
            conf    => $conf,
            package => 'maildrop-' . $ver,
            site    => 'http://' . $conf->{'toaster_sf_mirror'},
            url     => '/courier',
            targets => [
                './configure --prefix=' . $prefix . ' --exec-prefix=' . $prefix,
                'make',
                'make install-strip',
                'make install-man'
            ],
            source_sub_dir => 'mail',
            debug   => $debug,
        );
    }

    # make sure vpopmail user is set up (owner of mailfilter file)
    my $uid = getpwnam("vpopmail");
    my $gid = getgrnam("vchkpw");

    croak "maildrop: didn't get uid or gid for vpopmail:vchkpw!"
      unless ( $uid && $gid );

    my $etcmail = "$prefix/etc/mail";
    unless ( -d $etcmail ) {
        mkdir( $etcmail, oct('0755') )
          or $utility->mkdir_system( dir => $etcmail, mode=>'0755', debug=>$debug );
    }

    $self->maildrop_filter();

    my $imap = "$prefix/sbin/subscribeIMAP.sh";
    unless ( -e $imap ) {

        my $chown = $utility->find_the_bin( bin => "chown", debug => 0 );
        my $chmod = $utility->find_the_bin( bin => "chmod", debug => 0 );

        my @lines;
        push @lines, '#!/bin/sh
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

        $utility->file_write( file => $imap, lines => \@lines, debug=>$debug )
          or croak "maildrop: FAILED: couldn't write $imap: $!\n";

        $utility->file_chmod(
            file_or_dir => $imap,
            mode        => '0555',
            sudo        => $UID == 0 ? 0 : 1,
            debug       => $debug,
        );
    }

    my $log = $conf->{'qmail_log_base'} || "/var/log/mail";

    unless ( -d $log ) {

        $utility->mkdir_system( dir => $log, debug => 0 );

        # set its ownership to be that of the qmail log user
        $utility->file_chown(
            dir   => $log,
            uid   => $conf->{'qmail_log_user'},
            gid   => $conf->{'qmail_log_group'},
            sudo  => $UID == 0 ? 0 : 1,
            debug => $debug,
        );

        #or croak "maildrop: chown $log failed!";
    }

    my $logf = "$log/maildrop.log";

    unless ( -e $logf ) {

        $utility->file_write( file => $logf, lines => ["begin"], debug=>$debug );

        # set the ownership of the maildrop log to the vpopmail user
        $utility->file_chown(
            file  => $logf,
            uid   => $uid,
            gid   => $gid,
            sudo  => 1,
            debug => $debug,
        );

        #chown($uid, $gid, $logf) or croak "maildrop: chown $logf failed!";
    }
}

sub maildrop_filter {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    warn "maildrop_filter: debugging enabled.\n" if $debug;

    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";
    my $logbase = $conf->{'qmail_log_base'};

    # if any of these are set
    #$debug ||= $conf->{'toaster_debug'};

    unless ($logbase) {
        $logbase = -d "/var/log/qmail" ? "/var/log/qmail"
                 : "/var/log/mail";
    }

    my $filterfile = $conf->{'filtering_maildrop_filter_file'}
      || "$prefix/etc/mail/mailfilter";

    my ( $path, $file ) = $utility->path_parse($filterfile);

    unless ( -d $path ) { $utility->mkdir_system( dir => $path, debug=>$debug ) }

    unless ( -d $path ) {
        carp "Sorry, $path doesn't exist and I couldn't create it.\n";
        return 0;
    }

    my @lines = $self->maildrop_filter_file(
        logbase => $logbase,
        debug   => $debug,
    );

    my $user  = $conf->{'vpopmail_user'}  || "vpopmail";
    my $group = $conf->{'vpopmail_group'} || "vchkpw";

    # if the mailfilter file doesn't exist, create it
    if ( !-e $filterfile ) {
        $utility->file_write( 
            file  => $filterfile, 
            lines => \@lines, 
            mode  => '0600', 
            debug => $debug,
        );

        $utility->file_chown(
            file  => $filterfile,
            uid   => $user,
            gid   => $group,
            debug => $debug,
        );

        $utility->_formatted("installed new $filterfile", "ok");
    }

    # write out filter to a new file
    $utility->file_write( 
        file  => "$filterfile.new", 
        lines => \@lines, 
        mode  =>'0600', 
        debug => $debug,
    );

    $utility->file_chown(
        file => "$filterfile.new",
        uid  => $user,
        gid  => $group,
        debug => $debug,
    );

    $utility->install_if_changed(
        newfile  => "$filterfile.new",
        existing => $filterfile,
        uid      => $user,
        gid      => $group,
        mode     => '0600',
        clean    => 0,
        debug    => $debug,
        notify   => 1,
        archive  => 1,
    );

    $file = "/etc/newsyslog.conf";
    if ( -e $file ) {
        unless (`grep maildrop $file`) {
            $utility->file_write(
                file  => $file,
                lines =>
                  ["/var/log/mail/maildrop.log $user:$group 644	3	1000 *	Z"],
                append => 1,
                debug  => $debug,
            );
        }
    }
}

sub maildrop_filter_file {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'logbase' => { type => SCALAR, },
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
        },
    );

    my $logbase = $p{'logbase'};
    my $fatal   = $p{'fatal'};
       $debug   = $p{'debug'};

    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";
    my $filterfile = $conf->{'filtering_maildrop_filter_file'}
      || "$prefix/etc/mail/mailfilter";

    my @lines = 'SHELL="/bin/sh"';
    push @lines, <<"EOMAILDROP";
import EXT
import HOST
VHOME=`pwd`
TIMESTAMP=`date "+\%b \%d \%H:\%M:\%S"`
MAILDROP_OLD_REGEXP="1"

##
#  title:  mailfilter-site
#  author: Matt Simerson
#  version 2.12
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

    $conf->{'filtering_debug'} ? push @lines, qq{logfile "$logbase/maildrop.log"}
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
        log "  FAILURE: EXT is not a valid value ($EXT)"
        log "=== END ===  $EXT@$HOST failure (EXT variable not imported)"
        EXITCODE=111
        exit
}

if ( $HOST eq "" )
{ 
        log "  FAILURE: HOST is not a valid value ($HOST)"
        log "=== END ===  $EXT@$HOST failure (HOST variable not imported)"
        EXITCODE=111
        exit
}

EOMAILDROP2

    my $spamass_method = $conf->{'filtering_spamassassin_method'};

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
				log "   running message through spamc"
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

    push @lines, <<'EOMAILDROP5';
##
# Set MAILDIRQUOTA. If this is not set, maildrop and deliverquota
# will not enforce quotas for message delivery.
#
# I find this much easier than creating yet another config file
# to store this in. This way, any time the quota is changed in
# vpopmail, it will get noticed by maildrop immediately.
##

`test -e $VHOME/Maildir/maildirsize`
if( $RETURNCODE == 0)
{
	MAILDIRQUOTA=`/usr/bin/head -n1 $VHOME/Maildir/maildirsize`
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
# variable $MATCH2 to the spam score.

if ( /X-Spam-Status: Yes, (hits|score)=![0-9]+\.[0-9]+! /:h)
{
EOMAILDROP5

    my $score     = $conf->{'filtering_spama_discard_score'};
    my $pyzor     = $conf->{'filtering_report_spam_pyzor'};
    my $sa_report = $conf->{'filtering_report_spam_spamassassin'};

    if ($score) {

        push @lines, <<"EOMAILDROP6";
	# if the message scored a $score or higher, then there is no point in
	# keeping it around. SpamAssassin already knows it as spam, and
	# has already "autolearned" from it if you have that enabled. The
	# end user likely does not want it. If you wanted to cc it, or
	# deliver it elsewhere for inclusion in a spam corpus, you could
	# easily do so with a cc or xfilter command

	if ( \$MATCH2 >= $score )   # from Adam Senuik post to mail-toasters
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
		log "   SPAM: score \$MATCH2 exceeds $score: nuking message!"
		log "=== END === \$EXT\@\$HOST success (discarded)"
		EXITCODE=0
		exit
	}
EOMAILDROP9
    }

    push @lines, <<"EOMAILDROP10";
	# if the user does not have a Spam folder, we create it.

	`test -d \$VHOME/Maildir/.Spam`
	if( \$RETURNCODE == 1 )
	{
		log "   creating \$VHOME/Maildir/.Spam "
		`maildirmake -f Spam \$VHOME/Maildir`
		`$prefix/sbin/subscribeIMAP.sh Spam \$VHOME`
	}

	log "   SPAM: score \$MATCH2: delivering to \$VHOME/Maildir/.Spam"

	# make sure the deliverquota binary exists and is executable
	# if not, then we cannot enforce quotas. If you do not check
	# for this, and the binary is missing, maildrop silently
	# discards mail. Do not ask how I know this.

	`test -x $prefix/bin/deliverquota`
	if ( \$RETURNCODE == 1 )
	{
		log "   WARNING: no deliverquota!"
		log "=== END ===  \$EXT\@\$HOST success"
		exception {
			to "\$VHOME/Maildir/.Spam"
		}
	}
	else
	{
		exception {
			xfilter "$prefix/bin/deliverquota -w 90 \$VHOME/Maildir/.Spam"
		}

		if ( \$RETURNCODE == 0 )
		{
			log "=== END ===  \$EXT\@\$HOST  success (quota)"
			EXITCODE=0
			exit
		}
		else
		{
			if( \$RETURNCODE == 77)
			{
				log "=== END ===  \$EXT\@\$HOST  bounced (quota)"
				to "|/var/qmail/bin/bouncesaying '\$EXT\@\$HOST is over quota'"
			}
			else
			{
				log "=== END ===  \$EXT\@\$HOST failure (unknown deliverquota error)"
				to "\$VHOME/Maildir/.Spam"
			}
		}
	}
}

if ( /^X-Spam-Status: No, hits=![\\-]*[0-9]+\\.[0-9]+! /:h)
{
	log "   message is clean (\$MATCH2)"
}

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

log "   delivering to \$VHOME/Maildir"

`test -x $prefix/bin/deliverquota`
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
		xfilter "$prefix/bin/deliverquota -w 90 \$VHOME/Maildir"
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
EOMAILDROP10

    return @lines;
}

sub maillogs {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $user  = $conf->{'qmail_log_user'}  || "qmaill";
    my $group = $conf->{'qmail_log_group'} || "qnofiles";

    my $uid = getpwnam($user);
    my $gid = getgrnam($group);

    unless ( $uid && $gid ) {
        print "\nFAILED! The user $user or group $group does not exist.\n";
        return 0;
    }

    $toaster->supervise_dirs_create( conf => $conf, debug => $debug );

    # if it exists, make sure it's owned by qmail:qnofiles
    my $log = $conf->{'qmail_log_base'} || "/var/log/mail";
    if ( -w $log ) {
        chown( $uid, $gid, $log ) or carp "Couldn't chown $log to $uid: $!\n";
        $utility->_formatted( "maillogs: setting ownership of $log", "ok" );
    }

    unless ( -d $log ) {
        mkdir( $log, oct('0755') )
          or croak "maillogs: couldn't create $log: $!";
        chown( $uid, $gid, $log ) or croak "maillogs: couldn't chown $log: $!";
        $utility->_formatted( "maillogs: creating $log", "ok" );
    }

    foreach my $prot (qw/ send smtp pop3 submit /) {

        unless ( -d "$log/$prot" ) {

            $utility->_formatted( "maillogs: creating $log/$prot", "ok" );
            mkdir( "$log/$prot", oct('0755') )
              or croak "maillogs: couldn't create: $!";
        }
        else {
            $utility->_formatted( "maillogs: create $log/$prot",
                "ok (exists)" );
        }
        chown( $uid, $gid, "$log/$prot" )
          or croak "maillogs: chown $log/$prot failed: $!";
    }

    my $maillogs = "/usr/local/sbin/maillogs";

    croak "maillogs FAILED: couldn't find maillogs!\n" unless ( -e $maillogs );

    my $r = $utility->install_if_changed(
        newfile  => $maillogs,
        existing => "$log/send/sendlog",
        uid      => $uid,
        gid      => $gid,
        mode     => '0755',
        clean    => 0,
        debug    => $debug,
    );

    return 0 unless $r;
    $r == 1 ? $r = "ok" : $r = "ok (current)";
    $utility->_formatted( "maillogs: update $log/send/sendlog", $r );

    $r = $utility->install_if_changed(
        newfile  => $maillogs,
        existing => "$log/smtp/smtplog",
        uid      => $uid,
        gid      => $gid,
        mode     => '0755',
        clean    => 0,
        debug    => $debug,
    );

    $r == 1
      ? $r = "ok"
      : $r = "ok (current)";

    $utility->_formatted( "maillogs: update $log/smtp/smtplog", $r );

    $r = $utility->install_if_changed(
        newfile  => $maillogs,
        existing => "$log/pop3/pop3log",
        uid      => $uid,
        gid      => $gid,
        mode     => '0755',
        clean    => 0,
        debug    => $debug,
    );

    $r == 1
      ? $r = "ok"
      : $r = "ok (current)";

    $utility->_formatted( "maillogs: update $log/pop3/pop3log", $r );

    $self->cronolog(  debug=>$debug );
    $self->isoqlog(  debug=>$debug );

    require Mail::Toaster::Logs;
    my $logs = Mail::Toaster::Logs->new(conf=>$conf);
    $logs->verify_settings();
}

sub mattbundle {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $perlbin = $utility->find_the_bin( bin => "perl", debug => $debug );

    my @targets = ( "$perlbin Makefile.PL", "make", "make install" );
    push @targets, "make test" if $debug;

    $perl->module_install(
        module  => 'MATT-Bundle',
        archive => 'MATT-Bundle.tar.gz',
        url     => '/computing/perl/MATT-Bundle',
        targets => \@targets,
        debug   => $debug,
    );
}

sub mrm {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $perlbin = $utility->find_the_bin( bin => "perl" );

    my @targets = ( "$perlbin Makefile.PL", "make", "make install" );
    push @targets, "make test" if $debug;

    $perl->module_install(
        module  => 'Mysql-Replication',
        archive => 'Mysql-Replication.tar.gz',
        url     => '/internet/sql/mrm',
        targets => \@targets,
    );
}

sub mysql {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $version = $conf->{'install_mysql'};

    if ( ! $version ) {
        $utility->_formatted( "mysql: install not selected!",
            "skipping (disabled)" )
          if $debug;
        return 0;
    }

    require Mail::Toaster::Mysql;
    my $mysql = Mail::Toaster::Mysql->new();
    $mysql->install(
        conf  => $conf,
        ver   => $version,
        debug => $debug,
    );
}

sub nictool {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    $conf->{'install_expat'} = 1;    # this must be set for expat to install

    $self->expat(  debug=>$debug );
    $self->rsync(  debug=>$debug );
    $self->djbdns(  debug=>$debug );
    $self->mysqld(  debug=>$debug );

    # make sure these perl modules are installed
    $perl->module_load(
        module     => "LWP::UserAgent",
        port_name  => 'p5-libwww',
        port_group => 'www',
        auto       => 1,
        debug      => $debug,
    );
    $perl->module_load(
        module     => "SOAP::Lite",
        port_name  => 'p5-SOAP-Lite',
        port_group => 'net',
        auto       => 1,
        debug      => $debug,
    );
    $perl->module_load(
        module     => "RPC::XML",
        port_name  => 'p5-RPC-XML',
        port_group => 'net',
        auto       => 1,
        debug      => $debug,
    );
    $perl->module_load(
        module     => "DBI",
        port_name  => 'p5-DBI',
        port_group => 'databases',
        auto       => 1,
        debug      => $debug,
    );
    $perl->module_load(
        module     => "DBD::mysql",
        port_name  => 'p5-DBD-mysql',
        port_group => 'databases',
        auto       => 1,
        debug      => $debug,
    );

    if ( $OSNAME eq "freebsd" ) {
        if ( $conf->{'install_apache'} == 2 ) {
            $freebsd->port_install(
                port  => "p5-Apache-DBI",
                base  => "www",
                flags => "WITH_MODPERL2=yes",
                debug => $debug,
            );
        }
    }

    $perl->module_load( 
        module     => "Apache::DBI",
        port_name  => "p5-Apache-DBI", 
        port_group => "www",
        auto       => 1,
        debug      => $debug,
    );
    $perl->module_load( 
        module => "Apache2::SOAP", 
        auto   => 1, 
        debug  => $debug,
    );

    # install NicTool Server
    my $perlbin   = $utility->find_the_bin( bin => "perl", fatal => 0 );
    my $version   = "NicToolServer-2.03";
    my $http_base = $conf->{'toaster_http_base'};

    my @targets = ( "$perlbin Makefile.PL", "make", "make install" );

    push @targets, "make test" if $debug;

    push @targets, "mv ../$version $http_base"
      unless ( -d "$http_base/$version" );

    push @targets, "ln -s $http_base/$version $http_base/NicToolServer"
      unless ( -l "$http_base/NicToolServer" );

    $perl->module_install(
        module  => $version,
        archive => "$version.tar.gz",
        site    => 'http://www.nictool.com',
        url     => '/download/',
        targets => \@targets,
        auto   => 1, 
        debug  => $debug,
    );

    # install NicTool Client
    $version = "NicToolClient-2.03";
    @targets = ( "$perlbin Makefile.PL", "make", "make install" );
    push @targets, "make test" if $debug;

    push @targets, "mv ../$version $http_base" if ( !-d "$http_base/$version" );
    push @targets, "ln -s $http_base/$version $http_base/NicToolClient"
      if ( !-l "$http_base/NicToolClient" );

    $perl->module_install(
        module  => $version,
        archive => "$version.tar.gz",
        targets => \@targets,
        auto   => 1, 
        debug  => $debug,
    );
}

sub openssl_conf {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # this is only for testing, see t/Setup.pm
    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $sslconf = "/etc/ssl/openssl.cnf";

    if ( !$conf->{'install_openssl'} ) {
        $utility->_formatted( "openssl: configuring", "skipping (disabled)" )
          if $debug;
        return;
    }

    # for testing only
    if ( defined $conf->{'install_openssl_conf'} && !$conf->{'install_openssl_conf'} )
    {
        return;
    }

    # if FreeBSD, check for ports version of openssl
    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install ( 
            port => "openssl", 
            base => "security",
            debug=> 0,
        );
    };

    # make sure openssl libraries are available

    # figure out where openssl.cnf is
    if ( $OSNAME eq "freebsd" ) { 
        $sslconf = "/etc/ssl/openssl.cnf"; 
    }
    elsif ( $OSNAME eq "darwin" ) {
        $sslconf = "/System/Library/OpenSSL/openssl.cnf";
    }
    elsif ( $OSNAME eq "linux" ) { 
        $sslconf = "/etc/ssl/openssl.cnf"; 
    }

    unless ( -e $sslconf ) {
        $err = "openssl: could not find your openssl.cnf file!";
        $utility->_formatted( $err, "FAILED" );
        croak $err if $fatal;
        return;
    }

    unless ( -w $sslconf ) {
        $err = "openssl: no write permission to $sslconf!";
        $utility->_formatted( $err, "FAILED" );
        croak $err if $fatal;
        return 0;
    }

    $utility->_formatted( "openssl: found $sslconf", "ok" );

    # get/set the settings to alter
    my $country  = $conf->{'ssl_country'}      || "US";
    my $state    = $conf->{'ssl_state'}        || "Texas";
    my $org      = $conf->{'ssl_organization'} || "DisOrganism, Inc.";
    my $locality = $conf->{'ssl_locality'}     || "Dallas";
    my $name     = $conf->{'ssl_common_name'}  || $conf->{'toaster_hostname'}
      || "mail.example.com";
    my $email = $conf->{'ssl_email_address'}   || $conf->{'toaster_admin_email'}
      || "postmaster\@example.com";

    # update openssl.cnf with our settings
    my $inside;
    my $discard;
    my @lines = $utility->file_read( file => $sslconf, debug=>0 );
    foreach my $line (@lines) {

        next if $line =~ /^#/;    # comment lines
        $inside++ if ( $line =~ /req_distinguished_name/ );
        next unless $inside;
        $discard++ if ( $line =~ /emailAddress_default/ );

        if ( $line =~ /^countryName_default/ ) {
            $line = "countryName_default\t\t= $country";
        }

        if ( $line =~ /^stateOrProvinceName_default/ ) {
            $line = "stateOrProvinceName_default\t= $state";
        }

        if ( $line =~ /^localityName\s+/ ) {
            $line = "localityName\t\t\t= Locality Name (eg, city)
localityName_default\t\t= $locality";
        }

        if ( $line =~ /^0.organizationName_default/ ) {
            $line = "0.organizationName_default\t= $org";
        }

        if ( $line =~ /^commonName_max/ ) {
            $line = "commonName_max\t\t\t= 64
commonName_default\t\t= $name";
        }

        if ( $line =~ /^emailAddress_max/ ) {
            $line = "emailAddress_max\t\t= 64
emailAddress_default\t\t= $email";
        }
    }

    if ( $OSNAME eq "freebsd" && ! -e "/usr/local/openssl/openssl.cnf" ) {
        symlink($sslconf, "/usr/local/openssl/openssl.cnf") 
            or carp "could not create symlink in /usr/local/openssl for openssl.cnf: $!\n";
    };

    if ($discard) {
        $utility->_formatted( "openssl: updating $sslconf", "ok (no change)" );
        return 2;
    }

    my $tmpfile = "/tmp/openssl.cnf";
    $utility->file_write( file => $tmpfile, lines => \@lines, debug => 0 );
    $utility->install_if_changed(
        newfile  => $tmpfile,
        existing => $sslconf,
        debug    => 0,
    );

    return 1;
}

sub periodic_conf {

    return 0 if ( -e "/etc/periodic.conf" );

    open( my $PERIODIC, ">", "/etc/periodic.conf" );
    print $PERIODIC '
#--periodic.conf--
# 210.backup-aliases
daily_backup_aliases_enable="NO"                       # Backup mail aliases

# 440.status-mailq
daily_status_mailq_enable="YES"                         # Check mail status
daily_status_mailq_shorten="NO"                         # Shorten output
daily_status_include_submit_mailq="NO"                 # Also submit queue

# 460.status-mail-rejects
daily_status_mail_rejects_enable="NO"                  # Check mail rejects
daily_status_mail_rejects_logs=3                        # How many logs to check
#-- end --
';
    close $PERIODIC;
}

sub perl_suid_check {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $conf->{'install_qmailscanner'} ) {
        unless ( $Config{d_dosuid} ) {
            print "\nYou have chosen to install qmail-scanner but the version of "
                . "perl you have installed does not have setuid enabled. Since Qmail-Scanner "
                . "requires it, must use the qmail-scanner C wrapper.\n";
            sleep 3;
        }
    }
}

sub pop3_test_auth {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my @features;

    $OUTPUT_AUTOFLUSH = 1;

    print "pop3_test_auth: checking Mail::POP3Client ........................ ";
    $perl->module_load(
        module     => "Mail::POP3Client",
        port_name  => 'p5-Mail-POP3Client',
        port_group => 'mail',
        debug      => 0,
        auto       => 1, 
    );
    print "ok\n";

    my %auths;

    my $user = $conf->{'toaster_test_email'}        || 'test2@example.com';
    my $pass = $conf->{'toaster_test_email_pass'}   || 'cHanGeMe';
    my $host = $conf->{'pop3_ip_address_listen_on'} || 'localhost';
    if ( $host eq "system" || $host eq "qmail" || $host eq "all" ) {
        $host = "localhost";
    }

    $auths{'POP3'}          = { type => 'PASS',     descr => 'plain text' };
    $auths{'POP3-APOP'}     = { type => 'APOP',     descr => 'APOP' };
    $auths{'POP3-CRAM-MD5'} = { type => 'CRAM-MD5', descr => 'CRAM-MD5' };
    $auths{'POP3-SSL'} = { type => 'PASS', descr => 'plain text', ssl => 1 };
    $auths{'POP3-SSL-APOP'} = { type => 'APOP', descr => 'APOP', ssl => 1 };
    $auths{'POP3-SSL-CRAM-MD5'} =
      { type => 'CRAM-MD5', descr => 'CRAM-MD5', ssl => 1 };

    foreach ( keys %auths ) {
        pop3_auth( $auths{$_}, $host, $user, $pass, $debug );
    }

    sub pop3_auth {

        my ( $vals, $host, $user, $pass, $debug ) = @_;

        my $type  = $vals->{'type'};
        my $descr = $vals->{'descr'};

        my ( $pop, $mess );

        if ( defined $vals->{'ssl'} && $vals->{'ssl'} ) {
            $mess = "pop3_auth: POP3 SSL server with $descr passwords";
        }
        else {
            $mess = "pop3_auth: POP3 server with $descr passwords";
            $vals->{'ssl'} = 0;
        }

        $pop = Mail::POP3Client->new(
            HOST      => $host,
            AUTH_MODE => $type,
            USESSL    => $vals->{'ssl'},
        );

        $pop->User($user);
        $pop->Pass($pass);
        $pop->Connect() >= 0 || warn $pop->Message();
        $pop->State() eq "TRANSACTION"
          ? $utility->_formatted( $mess, "ok" )
          : $utility->_formatted( $mess, "FAILED" );

        if ( my @features = $pop->Capa() ) {
            print "\nYour POP3 server supports: "
              . join( ",", @features ) . "\n"
              if $debug;
        }
        $pop->Close;
    }

    return 1;
}

sub phpmyadmin {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    unless ( $conf->{'install_phpmyadmin'} ) {
        print
"phpMyAdmin install disabled. Set install_phpmyadmin in toaster-watcher.conf if you want to install it.\n";
        return 0;
    }

    # prevent t1lib from installing X11
    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install(
            port  => "t1lib",
            base  => "devel",
            flags => "WITHOUT_X11=yes"
        );
        if (
            $utility->yes_or_no(
                question =>
"php-gd requires x11 libraries. Shall I try installing the xorg-libraries package?"
            )
          )
        {
            $freebsd->package_install("xorg-libraries")
              unless $freebsd->is_port_installed( port => "xorg-libraries", debug=>$debug );
        }

        if (    !$freebsd->is_port_installed( port => "xorg-libraries", debug=>$debug )
            and !$freebsd->is_port_installed( port => "XFree86-Libraries", debug=>$debug ) )
        {
            if (
                $utility->yes_or_no(
                    question =>
"php-gd requires x11 libraries. Shall I try installing the xorg-libraries package?"
                )
              )
            {
                $freebsd->package_install( port => "XFree86-Libraries" );
            }
        }
        if ( $conf->{'install_php'} eq "4" ) {
            $freebsd->port_install( port => "php4-gd", base => "graphics" );
        } elsif ( $conf->{'install_php'} eq "5" ) {
            $freebsd->port_install( port => "php5-gd", base => "graphics" );
        };
    }

    require Mail::Toaster::Mysql;
    my $mysql = Mail::Toaster::Mysql->new();
    $mysql->phpmyadmin_install($conf);
}

sub ports {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->ports_update(conf=>$conf, debug=>$debug);
    }
    elsif ( $OSNAME eq "darwin" ) {
        $darwin->ports_update();
    }
    else {
        print "Sorry, no ports support for $OSNAME yet.\n";
    }
}

sub qmailadmin {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_qmailadmin'};

    unless ($ver) {
        print "skipping qmailadmin install, it's not selected!\n";
        return 0;
    }

    my $package = "qmailadmin-$ver";
    my $site    = "http://" . $conf->{'toaster_sf_mirror'};
    my $url     = "/qmailadmin";

    my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
    $toaster ||= "http://mail-toaster.org";

    my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";

    my $cgi = $conf->{'qmailadmin_cgi-bin_dir'};
    unless ( $cgi && -e $cgi ) {
        $cgi = $conf->{'toaster_cgi_bin'};
        unless ( $cgi && -e $cgi ) {
            -d "/usr/local/www/cgi-bin.mail"
              ? $cgi = "/usr/local/www/cgi-bin.mail"
              : $cgi = "/usr/local/www/cgi-bin";
        }
    }

    my $docroot = $conf->{'qmailadmin_http_docroot'};
    unless ( $docroot && -e $docroot ) {
        $docroot = $conf->{'toaster_http_docs'};
        unless ( $docroot && -e $docroot ) {
            if ( -d "/usr/local/www/mail" ) {
                $docroot = "/usr/local/www/mail";
            }
            elsif ( -d "/usr/local/www/data/mail" ) {
                $docroot = "/usr/local/www/data/mail";
            }
            else { $docroot = "/usr/local/www/data"; }
        }
    }

    my ($help);
    $help++ if $conf->{'qmailadmin_help_links'};

    if ( $ver eq "port" ) {
        if ( $OSNAME ne "freebsd" ) {
            print
              "FAILURE: Sorry, no port install of qmailadmin (yet). Please edit
toaster-watcher.conf and select a version of qmailadmin to install.\n";
            return 0;
        }

        port_install_qma( $conf, $cgi, $docroot, $debug );
        qma_help($conf, $docroot, $debug) if $help;
        return 1;
    }

    my $conf_args;

    if ( -x "$cgi/qmailadmin" ) {
        return 0
          unless $utility->yes_or_no(
            question => "qmailadmin is installed, do you want to reinstall?",
            timeout  => 60,
          );
    }

    if ( defined $conf->{'qmailadmin_domain_autofill'}
        && $conf->{'qmailadmin_domain_autofill'} )
    {
        $conf_args = " --enable-domain-autofill=Y";
        print "domain autofill: yes\n";
    }

    if ( defined $conf->{'qmailadmin_spam_option'} ) {
        if ( $conf->{'qmailadmin_spam_option'} ) {
            $conf_args .=
                " --enable-modify-spam=Y"
              . " --enable-spam-command=\""
              . $conf->{'qmailadmin_spam_command'} . "\"";
            print "modify spam: yes\n";
        }
    }
    else {
        if ( $utility->yes_or_no( question => "\nDo you want spam options? " ) ) {
            $conf_args .=
                " --enable-modify-spam=Y"
              . " --enable-spam-command=\""
              . $conf->{'qmailadmin_spam_command'} . "\"";
        }
    }

    unless ( defined $conf->{'qmailadmin_modify_quotas'} ) {
        if (
            $utility->yes_or_no(
                question => "\nDo you want user quotas to be modifiable? "
            )
          )
        {
            $conf_args .= " --enable-modify-quota=y";
        }
    }
    else {
        if ( $conf->{'qmailadmin_modify_quotas'} ) {
            $conf_args .= " --enable-modify-quota=y";
            print "modify quotas: yes\n";
        }
    }

    unless ( defined $conf->{'qmailadmin_install_as_root'} ) {

        if (
            $utility->yes_or_no(
                question => "\nShould qmailadmin be installed as root? "
            )
          )
        {
            $conf_args .= " --enable-vpopuser=root";
        }
    }
    else {
        if ( $conf->{'qmailadmin_install_as_root'} ) {
            $conf_args .= " --enable-vpopuser=root";
            print "install as root: yes\n";
        }
    }

    $conf_args .= " --enable-htmldir=" . $docroot . "/qmailadmin";
    $conf_args .= " --enable-imagedir=" . $docroot . "/qmailadmin/images";
    $conf_args .= " --enable-imageurl=/qmailadmin/images";
    $conf_args .= " --enable-cgibindir=" . $cgi;

    if ( !defined $conf->{'qmailadmin_help_links'} ) {
        $help =
          $utility->yes_or_no( question =>
              "Would you like help links on the qmailadmin login page?" );
        $conf_args .= " --enable-help=y" if $help;
    }
    else {
        if ( $conf->{'qmailadmin_help_links'} ) {
            $conf_args .= " --enable-help=y";
            $help = 1;
        }
    }

    if ( $OSNAME eq "darwin" ) {
        $conf_args .= " --build=ppc";
        my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
        $utility->syscmd(
            command => "ranlib $vpopdir/lib/libvpopmail.a",
            debug   => 0,
        );
    }

    my $make = $utility->find_the_bin( bin => "gmake", fatal => 0 );
    unless ( -x $make ) { $make = $utility->find_the_bin( bin => "make" ); }

    $utility->install_from_source(
        conf      => $conf,
        package   => $package,
        site      => $site,
        url       => $url,
        targets   =>
          [ "./configure " . $conf_args, "$make", "$make install-strip" ],
        debug          => $debug,
        source_sub_dir => 'mail',
    );

    qma_help( $conf, $docroot, $debug ) if ($help);

    if ( $conf->{'qmailadmin_return_to_mailhome'} ) {
        my $file = "/usr/local/share/qmailadmin/html/show_login.html";

        return unless ( -e $file );

        print "qmailadmin: Adjusting login to return to Mail Center page\n";

        my $tmp = "/tmp/show_login.html";
        $utility->file_write(
            file  => $tmp,
            lines => [
                '<META http-equiv="refresh" content="0;URL=https://'
                  . $conf->{'toaster_hostname'} . '/">'
            ],
            debug => $debug,
        );

        return unless ( -e $tmp );

        $utility->syscmd( command => "cat $file >> $tmp", debug=>$debug );
        unless ( move( $tmp, $file ) ) {
            carp "qmailadmin: FAILURE: couldn't move $tmp to $file: $!";
            return 0;
        }

# here's another way:
#  <body onload="redirect();">
#  <script language="Javascript" type="text/javascript">
#    <!--
#      function redirect () { setTimeout("go_now()",1); }
#      function go_now () { window.location.href = "https://jail10.cadillac.net/"; }
#    //-->
#  </script>

    }

    return 1;

    sub qma_help {

        my ( $conf, $docroot, $debug ) = @_;

        my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
        $src .= "/mail";

        my $helpdir = $docroot . "/qmailadmin/images/help";

        if ( -d $helpdir ) {
            $utility->_formatted( "qmailadmin: installing help files",
                "ok (exists)" );
            return 1;
        }

        print "qmailadmin: Installing help files in $helpdir\n";
        $utility->chdir_source_dir( dir => $src, debug=>$debug );

        my $helpfile = "qmailadmin-help-" . $conf->{'qmailadmin_help_links'};
        unless ( -e "$helpfile.tar.gz" ) {
            print "qmailadmin: fetching helpfile tarball.\n";
            my $site = "http://" . $conf->{'toaster_sf_mirror'};
            $utility->file_get( url => "$site/qmailadmin/$helpfile.tar.gz", debug=>$debug );
        }

        if ( !-e "$helpfile.tar.gz" ) {
            carp "qmailadmin: FAILED: help files couldn't be downloaded!\n";
            return 0;
        }

        $utility->archive_expand(
            archive => "$helpfile.tar.gz",
            debug   => $debug,
        );

        if ( move( $helpfile, $helpdir ) ) {
            $utility->_formatted( "qmailadmin: installed help files", "ok" );
        }
        else {
            carp "FAILED: Couldn't move $helpfile to $helpdir";
        }
    }

    # install via FreeBSD ports
    sub port_install_qma {

        my ( $conf, $cgi, $docroot, $debug ) = @_;

        my ( @args, $cgi_sub, $docroot_sub );

        push @args, "WITH_DOMAIN_AUTOFILL=yes"
          if ( $conf->{'qmailadmin_domain_autofill'} );
        push @args, "WITH_MODIFY_QUOTA=yes"
          if ( $conf->{'qmailadmin_modify_quotas'} );
        push @args, "WITH_HELP=yes" if $conf->{'qmailadmin_help_links'};
        push @args, 'CGIBINSUBDIR=""';

        if ( $cgi =~ /\/usr\/local\/(.*)$/ ) { $cgi_sub = $1; }
        push @args, 'CGIBINDIR="' . $cgi_sub . '"';

        if ( $docroot =~ /\/usr\/local\/(.*)$/ ) {
            $docroot_sub = $1;
        }
        push @args, 'WEBDATADIR="' . $docroot_sub . '"';

        #	push @args, 'WEBDATASUBDIR=""';
        #	push @args, 'IMAGEDIR="' . $docroot . '/images/qmailadmin"';

        if ( $conf->{'qmail_dir'} ne "/var/qmail" ) {
            push @args, 'QMAIL_DIR="' . $conf->{'qmail_dir'} . '"';
        }

        if ( $conf->{'qmailadmin_spam_option'} ) {
            push @args, "WITH_SPAM_DETECTION=yes";
            if ( $conf->{'qmailadmin_spam_command'} ) {
                push @args,
                  'SPAM_COMMAND="' . $conf->{'qmailadmin_spam_command'} . '"';
            }
        }

        $freebsd->port_install(
            port  => "qmailadmin",
            base  => "mail",
            flags => join( ",", @args ),
            debug => $debug,
        );

        if ( $conf->{'qmailadmin_install_as_root'} ) {
            my $gid = getgrnam("vchkpw");
            chown( 0, $gid, "/usr/local/$cgi_sub/qmailadmin" );
        }
    }
}

sub qmail_scanner {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_qmailscanner'};

    if ( !$ver or defined $conf->{'install_qmail_scanner'} ) {
        $utility->_formatted( "qmailscanner: installing", "skipping (disabled)" )
          if $debug;
        print "\n\nFATAL: qmail_scanner is disabled in toaster-watcher.conf.\n";
        return;
    }

    if ( !$Config{d_dosuid} && !$conf->{'qmail_scanner_suid_wrapper'} ) {
        croak
"qmail_scanner requires that perl be installed with setuid enabled or with the suid C wrapper. Please enable one or the other.\n";
    }

    my $src     = $conf->{'toaster_src_dir'} || "/usr/local/src";
    my $package = "qmail-scanner-$ver";
    my $site    = "http://" . $conf->{'toaster_sf_mirror'} . "/qmail-scanner";

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "p5-Time-HiRes", base => "devel", debug=>$debug );
        $freebsd->port_install( port => "tnef",          base => "converters", debug=>$debug );
        $freebsd->port_install( port => "maildrop",      base => "mail", debug=>$debug );

        #  should we be using this?
        #  $freebsd->port_install( port=>"qmail-scanner", base=>"mail" );
    }

    # verify that setuid perl is installed
    # add 'lang/perl5.8'		=> 'ENABLE_SUIDPERL=yes',
    # to /usr/local/etc/pkgtools.conf (MAKE_ARGS)
    # or make port with -DENABLE_SUIDPERL

    if ( -e "/var/qmail/bin/qmail-scanner-queue.pl" ) {
        print "QmailScanner is already Installed!\n";
        return
          unless (
            $utility->yes_or_no(
                question => "Would you like to reinstall it?",
                timeout  => 60,
            )
          );
    }

    if ( -d "$src/mail/filter" ) {
        $utility->chdir_source_dir( dir => "$src/mail/filter" );
    }
    else {
        $utility->syscmd( command => "mkdir -p $src/mail/filter", debug=>$debug );
        $utility->chdir_source_dir( dir => "$src/mail/filter" );
    }

    unless ( -e "$package.tgz" ) {
        $utility->file_get( url => "$site/$package.tgz" );
        unless ( -e "$package.tgz" ) {
            croak "qmail_scanner FAILED: couldn't fetch $package.tgz\n";
        }
    }

    if ( -d $package ) {
        unless ( $utility->source_warning( package => $package, src => $src ) )
        {
            carp "qmail_scanner: OK, skipping install.\n";
            return 0;
        }
    }

    $utility->archive_expand( archive => "$package.tgz", debug => $debug );
    chdir($package) or croak "qmail_scanner: couldn't chdir $package.\n";

    my $user = $conf->{'qmail_scanner_user'} || "qscand";

    unless ( getpwuid($user) ) {
        require Mail::Toaster::Passwd;
        my $passwd = Mail::Toaster::Passwd->new();

        $passwd->creategroup($user);
        $passwd->user_add( user => $user, debug => 1 );
    }

    my $confcmd = "./configure ";

    $confcmd .= "--qs-user $user " if ( $user ne "qscand" );

    unless ( defined $conf->{'qmail_scanner_logging'} ) {
        if (
            $utility->yes_or_no(
                question => "Do you want QS logging enabled?"
            )
          )
        {
            $confcmd .= "--log-details syslog ";
        }
    }
    else {
        if ( $conf->{'qmail_scanner_logging'} ) {
            $confcmd .= "--log-details syslog ";
            print "logging: yes\n";
        }
    }

    unless ( defined $conf->{'qmail_scanner_debugging'} ) {
        unless (
            $utility->yes_or_no(
                question => "Do you want QS debugging enabled?"
            )
          )
        {
            $confcmd .= "--debug no ";
        }
    }
    else {
        unless ( $conf->{'qmail_scanner_debugging'} ) {
            $confcmd .= "--debug no ";
            print "debugging: no\n";
        }
    }

    my $email = $conf->{'qmail_scanner_postmaster'};
    unless ($email) {
        $email = $conf->{'toaster_admin_email'};
        unless ($email) {
            $email =
              $utility->answer(
                q => "What is the email address for postmaster mail?" );
        }
    }
    else {
        if ( $email eq "postmaster\@example.com" ) {
            if ( $conf->{'toaster_admin_email'} ne "postmaster\@example.com" ) {
                $email = $conf->{'toaster_admin_email'};
            }
            else {
                $email =
                  $utility->answer(
                    q => "What is the email address for postmaster mail?" );
            }
        }
    }

    my ( $u, $d ) = $email =~ /^(.*)@(.*)$/;
    $confcmd .= "--admin $u --domain $d ";

    if ( $conf->{'qmail_scanner_notify'} ) {
        $confcmd .= '--notify "' . $conf->{'qmail_scanner_notify'} . '" ';
    }

    if ( $conf->{'qmail_scanner_localdomains'} ) {
        $confcmd .=
          '--local-domains "' . $conf->{'qmail_scanner_localdomains'} . '" ';
    }

    if ( $ver gt 1.20 ) {
        if ( $conf->{'qmail_scanner_block_pass_zips'} ) {
            $confcmd .= '--block-password-protected yes ';
        }
    }

    if ( $ver gt 1.21 ) {
        if ( $conf->{'qmail_scanner_eol_disable'} ) {
            $confcmd .= '--ignore-eol-check ';
        }
    }

    if ( $conf->{'qmail_scanner_fix_mime'} ) {
        $confcmd .= '--fix-mime ' . $conf->{'qmail_scanner_fix_mime'} . ' ';
    }

    if ( $conf->{'qmail_dir'} && $conf->{'qmail_dir'} ne "/var/qmail" ) {
        $confcmd .= "--qmaildir " . $conf->{'qmail_dir'} . " ";
        $confcmd .= "--bindir " . $conf->{'qmail_dir'} . "/bin ";
    }

    my $tmp;

    unless ( $conf->{'qmail_scanner_scanners'} ) {
        $tmp = qmail_scanner_old_method(  ver => $ver );
        print "Using Scanners: $tmp\n";
        $confcmd .= "$tmp ";
    }
    else {

        # remove any spaces
        print "Checking Scanners: " . $conf->{'qmail_scanner_scanners'} . "\n";
        $tmp = $conf->{'qmail_scanner_scanners'};    # get the list of scanners
        $tmp =~ s/\s+//;                             # clean out any spaces
        print "Using Scanners: $tmp\n";
        $confcmd .= "--scanners $tmp ";
    }

    print "OK, running qmail-scanner configure to test options.\n";
    $utility->syscmd( command => $confcmd, debug=>$debug );

    if ( $utility->yes_or_no( question => "OK, ready to install it now?" ) ) {
        $utility->syscmd( command => $confcmd . " --install", debug=>$debug );
    }

    my $c_file = "/var/qmail/bin/qmail-scanner-queue";

    if ( $conf->{'qmail_scanner_suid_wrapper'} ) {
        chdir("contrib");
        $utility->syscmd( command => "make", debug=>$debug );
        copy( "qmail-scanner-queue", $c_file );
        chmod oct('04755'), $c_file;
        my $uid = getpwnam($user);
        my $gid = getgrnam($user);
        chown( $uid, $gid, $c_file );
        chmod oct('0755'), "$c_file.pl";
    }
    else {
        chmod oct('04755'), "$c_file.pl";
    }

    $self->qmail_scanner_config( );

    if ( $conf->{'install_qmailscanner_stats'} ) {
        $self->qs_stats( );
    }
}

sub qmail_scanner_config {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    #	my $service = $conf->{'qmail_service'};

  # We want qmail-scanner to process emails so we add an ENV to the SMTP server:
    print "To enable qmail-scanner, see the instructions on the filtering page
of the web site: http://www.tnpi.biz/internet/mail/toaster/

";

}

sub qmail_scanner_old_method {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validation( @_, {
            'ver'   => { type => SCALAR, },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $p{'ver'};

    my ( $verb, $clam, $spam, $fprot, $uvscan );

    my $confcmd = "--scanners ";

    if ( defined $conf->{'qmail_scanner_clamav'} ) {
        $clam = $conf->{'qmail_scanner_clamav'};
    }
    else {
        $clam =
          $utility->yes_or_no( question => "Do you want ClamAV enabled?" );
    }

    if ( defined $conf->{'qmail_scanner_spamassassin'} ) {
        $spam = $conf->{'qmail_scanner_spamassassin'};
    }
    else {
        $spam =
          $utility->yes_or_no(
            question => "Do you want SpamAssassin enabled?" );
    }

    if ( defined $conf->{'qmail_scanner_fprot'} ) {
        $fprot = $conf->{'qmail_scanner_fprot'};
    }

    if ( defined $conf->{'qmail_scanner_uvscan'} ) {
        $uvscan = $conf->{'qmail_scanner_uvscan'};
    }

    if ($spam) {
        if ( defined $conf->{'qmail_scanner_spamass_verbose'} ) {
            $verb = $conf->{'qmail_scanner_spamass_verbose'};
        }
        else {
            $verb =
              $utility->yes_or_no(
                question => "Do you want SA verbose logging (n)?" );
        }
    }

    if ( $clam || $spam || $verb || $fprot || $uvscan ) {

        my $first = 0;

        if ($clam) {
            if ( $ver eq "1.20" ) {
                $confcmd .= "clamscan,clamuko";
                $first++;
            }
            elsif ( $ver eq "1.21" ) {
                $confcmd .= "clamdscan,clamscan";
                $first++;
            }
            else {
                $confcmd .= "clamscan";
                $first++;
            }
        }

        if ($fprot) {
            if ($first) { $confcmd .= "," }
            $confcmd .= "fprot";
            $first++;
        }

        if ($uvscan) {
            if ($first) { $confcmd .= "," }
            $confcmd .= "uvscan";
            $first++;
        }

        if ( $spam && $verb ) {
            if ($first) { $confcmd .= "," }
            $confcmd .= "verbose_spamassassin";
        }
        elsif ($spam) {
            if ($first) { $confcmd .= "," }
            $confcmd .= "fast_spamassassin";
        }
    }
    else { croak "qmail_scanner: No scanners?"; }

    return $confcmd;
}

sub qmail_scanner_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    # test Qmail-Scanner
    if ( !$conf->{'install_qmailscanner'} ) {
        print "qmail-scanner disabled, skipping test.\n";
        return 0;
    }

    print "testing qmail-scanner...";
    my $qdir = $conf->{'qmail_dir'} || "/var/qmail";

    my $scan = "$qdir/bin/qmail-scanner-queue";
    if ( -x $scan ) {
        print "Qmail Scanner C wrapper was found at $scan, testing... \n";
    }
    else {
        $scan = "$qdir/bin/qmail-scanner-queue.pl";
        unless ( -x $scan ) {
            print "FAILURE: Qmail Scanner could not be found at $scan!\n";
            return 0;
        }
        print "Qmail Scanner was found at $scan, testing... \n";
    }

    $ENV{"QMAILQUEUE"} = $scan;
    $toaster->email_send( conf => $conf, type => "clean" );
    $toaster->email_send( conf => $conf, type => "attach" );
    $toaster->email_send( conf => $conf, type => "virus" );
    $toaster->email_send( conf => $conf, type => "clam" );
    $toaster->email_send( conf => $conf, type => "spam" );
}

sub qs_stats {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my @lines;

    my $ver     = $conf->{'install_qmailscanner_stats'} || "2.0.2";
    my $package = "qss-$ver";
    my $site    = "http://" . $conf->{'toaster_sf_mirror'} . "/qss";
    my $htdocs  = $conf->{'toaster_http_docs'} || "/usr/local/www/data";

    if ( -e "$htdocs/qss/index.php" ) {
        print "qs_stats: already installed, skipping.\n";
        return 1;
    }

    unless ( -d "$htdocs/qss" ) {
        mkdir( "$htdocs/qss", oct('0755') )
          or croak "qs_stats: couldn't create $htdocs/qss: $!\n";
    }

    chdir "$htdocs/qss";
    unless ( -e "$package.tar.gz" ) {
        $utility->file_get( url => "$site/$package.tar.gz" );
        unless ( -e "$package.tar.gz" ) {
            croak "qs_stats: FAILED: couldn't fetch $package.tar.gz\n";
        }
    }
    else {
        print "qs_stats: sources already downloaded!\n";
    }

    my $quarantinelog = "/var/spool/qmailscan/quarantine.log";

    $utility->archive_expand( archive => "$package.tar.gz", debug => $debug );

    if ( -d "/var/spool/qmailscan" ) {
        chmod oct('0771'), "/var/spool/qmailscan";
    }
    else { croak "I can't find qmail-scanner's quarantine!\n"; }

    if ( -e $quarantinelog ) {
        chmod oct('0664'), $quarantinelog;
    }
    else {
        @lines =
'Fri, 12 Jan 2004 15:09:00 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Advice  Worm.Gibe.F       clamuko: 0.67.';
        push @lines,
'Fri, 12 Feb 2004 10:34:16 -0500	yykk62\@hotmail.com	mike\@example.net	Re: Your product	Worm.SomeFool.I	clamuko: 0.67. ';
        push @lines,
'Fri, 12 Mar 2004 15:06:04 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Last Microsoft Critical Patch	Worm.Gibe.F	clamuko: 0.67.';
        $utility->file_write( file => $quarantinelog, lines => \@lines );
        chmod oct('0664'), $quarantinelog;
    }

    my $dos2unix = $utility->find_the_bin( bin => "dos2unix", fatal => 0, debug=>$debug );
    unless ($dos2unix) {
        $freebsd->port_install( port => "unix2dos", base => "converters", debug=>$debug );
        $dos2unix = $utility->find_the_bin( bin => "dos2unix", fatal=>0, debug=>$debug );
    }

    chdir "$htdocs/qss";
    $utility->syscmd( command => "$dos2unix \*.php", debug=>$debug );

    my $file = "config.php";
    @lines = $utility->file_read( file => $file, debug=>$debug );

    foreach my $line (@lines) {
        if ( $line =~ /logFile/ ) {
            $line =
              '$config["logFile"] = "/var/spool/qmailscan/quarantine.log";';
        }
        if ( $line =~ /startYear/ ) {
            $line = '$config["startYear"]  = 2004;';
        }
    }
    $utility->file_write( file => $file, lines => \@lines, debug=>$debug );

    $file = "getGraph.php";
    @lines = $utility->file_read( file => $file );
    foreach my $line (@lines) {
        if ( $line =~ /^\$data = explode/ ) {
            $line = '$data = explode(",",rawurldecode($_GET[\'data\']));';
        }
        if ( $line =~ /^\$t = explode/ ) {
            $line = '$t = explode(",",rawurldecode($_GET[\'t\']));';
        }
    }
    $utility->file_write( file => $file, lines => \@lines, debug=>$debug );

    $file = "getGraph1.php";
    @lines = $utility->file_read( file => $file, debug=>$debug );
    foreach my $line (@lines) {
        if ( $line =~ /^\$points = explode/ ) {
            $line = '$points = explode(",",$_GET[\'data\']);';
        }
        if ( $line =~ /^\$config = array/ ) {
            $line =
'$config = array("startHGrad" => $_GET[\'s\'], "minInter" => 2, "maxInter" => 20, "minColsWidth" => 15, "imageHeight" => 200, "imageWidth" => 500, "startCount" => 0, "stopCount" => $stopCount, "maxGrad" => 10);';
        }
        if ( $line =~ /^"imageWidth/ ) { $line = ""; }
    }
    $utility->file_write( file => $file, lines => \@lines, debug=>$debug );

    $file = "index.php";
    @lines = $utility->file_read( file => $file, debug=>$debug );
    foreach my $line (@lines) {
        if ( $line =~ /^\s+\$date = strtotime/ ) {
            $line =
'if ( eregi("(^[0-9]+)", $val[0]) ) { $date = explode("/",$val[0]); $dateT = $date[0]; $date[0] = $date[1]; $date[1] = $dateT; $date = strtotime(implode("/",$date)); } else { $date = strtotime ($val[0]); }; ';
        }
        if ( $line =~ /^\s+\$date/ ) {
            $line = '';
        }
    }
    $utility->file_write( file => $file, lines => \@lines, debug=>$debug );

    unless ( -s $quarantinelog ) {
        @lines =
'Fri, 12 Jan 2004 15:09:00 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Advice  Worm.Gibe.F	clamuko: 0.67.';
        push @lines,
'Fri, 12 Feb 2004 10:34:16 -0500	yykk62\@hotmail.com	mike\@example.net	Re: Your product	Worm.SomeFool.I	clamuko: 0.67. ';
        push @lines,
'Fri, 12 Mar 2004 15:06:04 -0500	w.diep\@hetnet.nl	matt\@tnpi.biz	Last Microsoft Critical Patch	Worm.Gibe.F	clamuko: 0.67.';
        $utility->file_write( file => $quarantinelog, lines => \@lines, debug=>$debug );
    }
}

sub razor {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_razor'};

    unless ( $ver ) {
        $utility->_formatted( "razor: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    $perl->module_load( 
        module     => "Digest::Nilsimsa", 
        port_name  => "p5-Digest-Nilsimsa",
        port_group => "security",
        debug      => $debug,
        auto       => 1, 
    );

    $perl->module_load( 
        module     => "Digest::SHA1", 
        port_name  => "p5-Digest-SHA1", 
        port_group => "security",
        debug      => $debug,
        auto       => 1, 
    );

    if ( $ver eq "port" ) {
        if ( $OSNAME eq "freebsd" ) {
            $freebsd->port_install( port => "razor-agents", base => "mail", debug=>$debug );
        }
        elsif ( $OSNAME eq "darwin" ) {
            # old ports tree, deprecated
            $darwin->port_install( port_name => "razor", debug=>$debug );    
            # this one should work
            $darwin->port_install( port_name => "p5-razor-agents", debug=>$debug );
        }
    }

    if ( $utility->find_the_bin( bin => "razor-client", fatal => 0, debug=>$debug ) ) {
        print "It appears you have razor installed, skipping manual build.\n";
        $self->razor_config($debug);
        return 1;
    }

    $ver = "2.80" if ( $ver == 1 || $ver eq "port" );

    $perl->module_install(
        module  => 'razor-agents-' . $ver,
        archive => 'razor-agents-' . $ver . '.tar.gz',
        site    => 'http://umn.dl.sourceforge.net/sourceforge',
        url     => '/razor',
        conf    => $conf,
        debug   => $debug,
    );

    $self->razor_config($debug);
    return 1;
}

sub razor_config {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    print "razor: beginning configuration.\n";

    if ( -d "/etc/razor" ) {
        print "razor_config: it appears you have razor configured, skipping.\n";
        return 1;
    }

    my $client = $utility->find_the_bin( bin => "razor-client", fatal => 0, debug=>$debug );
    my $admin  = $utility->find_the_bin( bin => "razor-admin",  fatal => 0, debug=>$debug );

    # for old versions of razor
    if ( -x $client && !-x $admin ) {
        $utility->syscmd( command => $client, debug=>0 );
    }

    unless ( -x $admin ) {
        print "FAILED: couldn't find $admin!\n";
        return 0;
    }

    $utility->syscmd( command => "$admin -home=/etc/razor -create -d", debug=>0 );
    $utility->syscmd( command => "$admin -home=/etc/razor -register -d", debug=>0 );

    my $file = "/etc/razor/razor-agent.conf";
    if ( -e $file ) {
        my @lines = $utility->file_read( file => $file );
        foreach my $line (@lines) {
            if ( $line =~ /^logfile/ ) {
                $line = 'logfile                = /var/log/razor-agent.log';
            }
        }
        $utility->file_write( file => $file, lines => \@lines, debug=>0 );
    }

    $file = "/etc/newsyslog.conf";
    if ( -e $file ) {
        if ( !`grep razor-agent $file` ) {
            $utility->file_write(
                file   => $file,
                lines  => ["/var/log/razor-agent.log	600	5	1000 *	Z"],
                append => 1,
                debug  => 0,
            );
        }
    }

    print "razor: configuration completed.\n";
    return 1;
}

sub ripmime {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_ripmime'};

    if ( !$ver ) {
        print "ripmime install not selected.\n";
        return 0;
    }

    print "rimime: installing...\n";

    if ( $ver eq "port" || $ver eq "1" ) {

        if ( $utility->find_the_bin( bin => "ripmime", fatal => 0 ) ) {
            print "ripmime: is already installed...done.\n\n";
            return 1;
        }

        if ( $OSNAME eq "freebsd" ) {
            if ( $freebsd->port_install( port => "ripmime", base => "mail" ) ) {
                return 1;
            }
        }
        elsif ( $OSNAME eq "darwin" ) {
            if ( $darwin->port_install( port_name => "ripmime" ) ) {
                return 1;
            }
        }

        if ( $utility->find_the_bin( bin => "ripmime", fatal => 0 ) ) {
            print "ripmime: ripmime has been installed successfully.\n";
            return 1;
        }

        $ver = "1.4.0.6";
    }

    my $ripmime = $utility->find_the_bin( bin => "ripmime", fatal => 0 );
    if ( -x $ripmime ) {
        my $installed = `$ripmime -V`;
        ($installed) = $installed =~ /v(.*) - /;

        if ( $ver eq $installed ) {
            print
              "ripmime: the selected version ($ver) is already installed!\n";
            return 1;
        }
    }

    $utility->install_from_source(
        conf           => $conf,
        package        => "ripmime-$ver",
        site           => 'http://www.pldaniels.com',
        url            => '/ripmime',
        targets        => [ 'make', 'make install' ],
        patches        => '',
        bintest        => 'ripmime',
        debug          => 1,
        source_sub_dir => 'mail',
    );
}

sub rrdtool {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install(
            port  => "rrdtool",
            base  => "net",
            fatal => $fatal
        );

#$freebsd->port_install( port=>"rrdtool10", base=>"net", check=>"rrdtool-1.0", fatal=>$fatal );
        return $freebsd->is_port_installed( port => "rrdtool", debug=>$debug );
    }
    elsif ( $OSNAME eq "darwin" ) {
        $darwin->port_install( port_name => "rrdtool" );
    }

    return 1 if ( -x $utility->find_the_bin( bin => "rrdtool", fatal => 0 ) );

    my $ver = "1.2.15";

    unless ( $conf->{'install_rrdutil'} ) {
        print
"install_rrdutil is not set in toaster-watcher.conf! Skipping install.\n";
        return 0;
    }

    $utility->install_from_source(
        conf    => $conf,
        package => "rrdtool-$ver",
        site    => 'http://people.ee.ethz.ch',
        url     => '/~oetiker/webtools/rrdtool/pub',
        targets => [ './configure', 'make', 'make install' ],
        patches => '',
        bintest => 'rrdtool',
        debug   => 1,
    );
}

sub rrdutil {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal'   => { type => BOOLEAN, optional => 1, default => 1 },
            'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_net_snmpd'} || 4;

    # start by installing rrdtool
    my $rrdtool = $utility->find_the_bin( bin => "rrdtool", fatal => 0, debug=>$debug );
    $self->rrdtool(  debug=>$debug ) unless -x $rrdtool;
    $rrdtool = $utility->find_the_bin( bin => "rrdtool", fatal => 0, debug=>$debug );

    unless ( -x $rrdtool ) {
        print "FAILED rrdtool install.\n";
        croak if $fatal;
        exit 0;
    }

    my $snmpdir;
    if ( $OSNAME eq "darwin" ) { $snmpdir = "/usr/share/snmp" }
    else { $snmpdir = "/usr/local/share/snmp" }

# a file is getting installed here causing an error. This'll check for and fix it.
    if ( -e $snmpdir ) {
        unlink $snmpdir unless ( -d $snmpdir );
    }

    if ( $OSNAME eq "freebsd" ) {

        # if their ports tree is ancient, they might not have net-mgmt
        my $snmp_port_base =
            -d "/usr/ports/net-mgmt"     ? "net-mgmt"
          : -d "/usr/ports/net/net-snmp" ? "net"
          : "";

        unless ( -d "/usr/ports/$snmp_port_base" ) {
            carp
"FAILURE: the port directory ($snmp_port_base) for net-snmp4 is missing. If your ports tree is up to date, you might want to check your ports supfile and make sure net-mgmt is listed there!";
            return;
        }

        if ( $ver == 4 ) {
            if ( $conf->{'package_install_method'} eq "packages" ) {
                $freebsd->package_install(
                    port  => "net-snmp",
                    alt   => "ucd-snmp-4",
                    debug => $debug,
                );
            };

            $freebsd->port_install(
                port  => "net-snmp4",
                base  => $snmp_port_base,
                check => "ucd-snmp-4",
                debug => $debug,
            );
        }
        elsif ( $ver == 5 ) {

            if ( $conf->{'package_install_method'} eq "packages" ) {
                $freebsd->package_install( port => "net-snmp", debug=>$debug );
            }

            $freebsd->port_install(
                port => "net-snmp",
                base => $snmp_port_base,
                debug => $debug,
            );
        }
        else {
            print
"\n\nrrdutil: WARNING: not installing snmpd because version $ver is not valid! RRDutil isn't going to work very well without an SNMP agent!\n\n";
            sleep 5;
        }

        $freebsd->port_install(
            port => "p5-Net-SNMP",
            base => $snmp_port_base,
            debug => $debug,
        );

        $freebsd->port_install( 
            port  => "p5-TimeDate", 
            base  => "devel",
            debug => $debug,
        );
    }
    elsif ( $OSNAME eq "darwin" ) {
        $darwin->port_install( port_name => "net-snmp" ,
        debug => $debug,);
    }

    my $perlbin = $utility->find_the_bin( bin=>"perl", fatal=>0, debug =>0);

    my @targets =
      ( "$perlbin Makefile.PL", "make", "make install", "make cgi" );
    push @targets, "make test" if $debug;

    if ( -e "/usr/local/etc/rrdutil.conf" ) {
        push @targets, "make conf";
    }
    else { 
        push @targets, "make newconf";
    };

    my $snmpconf = "$snmpdir/snmpd.conf";
    unless ( -e $snmpconf ) { push @targets, "make snmp"; }

    require Mail::Toaster::Perl;
    my $perl = Mail::Toaster::Perl->new;

    $perl->module_install(
        module  => 'RRDutil',
        archive => 'RRDutil.tar.gz',
        site    => 'http://www.tnpi.biz',
        url     => '/internet/manage/rrdutil',
        targets => \@targets,
        debug   => $debug,
    );

    if ( $OSNAME eq "freebsd" ) {
        if (
            $freebsd->rc_dot_conf_check(
                check => "snmpd_enable",
                line  => 'snmpd_enable="YES"',
                debug => $debug,
            )
          )
        {
            $utility->_formatted( "configured to launch upon system boot",
                "ok" );
        }

        my $start = "start";
        if ( $ver == 5 ) { $start = "restart"; }
        $utility->syscmd( command => "/usr/local/etc/rc.d/snmpd.sh $start", debug=>$debug );
    }
}

sub rrdutil_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $snmpdir;
    if ( $OSNAME eq "darwin" ) { $snmpdir = "/usr/share/snmp" }
    else { $snmpdir = "/usr/local/share/snmp" }

    unless ( $conf->{'install_net_snmpd'} ) {
        $utility->_formatted( "rrdutil_test: SNMP is not selected, skipping",
            "FAILED" );
        return 0;
    }

    unless ( $conf->{'install_rrdutil'} ) {
        $utility->_formatted( "rrdutil_test: rrdutil not selected, skipping",
            "FAILED" );
        return 0;
    }

    if ( -e "$snmpdir/snmpd.conf" ) {
        $utility->_formatted( "rrdutil_test: checking snmpd.conf", "ok" );
    }
    else {
        $utility->_formatted( "rrdutil_test: checking snmpd.conf", "FAILED" );
        print
"\n\nYou need to install snmpd.conf. You can do this in one of three ways:

  1. run \"make snmp\" in the rrdutil source directory
  2. copy the snmpd.conf file from the rrdutil/contrib to /usr/local/share/snmp/snmpd.conf
  3. run snmpconf and manually configure.

The latter should only be done by those quite familiar with SNMP, and then you should reference the contrib/snmpd.conf file to see the OIDs that need to be defined for RRDutil to work properly.";
    }

    if ( -e "/usr/local/etc/rrdutil.conf" ) {
        $utility->_formatted( "rrdutil_test: checking rrdutil.conf", "ok" );
    }
    else {
        $utility->_formatted( "rrdutil_test: checking rrdutil.conf", "FAILED" );
        print "\nWhere's your rrdutil.conf file? It should be in /usr/local/etc. You can install one by running 'make newconf' in the RRD util source directory.\n";
    }
}

sub rsync {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "rsync", base => "net", debug=>$debug );
    }
    elsif ( $OSNAME eq "darwin" ) { $darwin->port_install( port_name => "rsync", debug=>$debug ) }
    else {
        print
"please install rsync manually. Support for $OSNAME isn't vailable yet.\n";
        exit;
    }

    return 1;
}

sub simscan {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    unless ( $conf->{'install_simscan'} ) {
        $utility->_formatted( "vqadmin: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    my $user    = $conf->{'simscan_user'} || "clamav";
    my $reje    = $conf->{'simscan_spam_hits_reject'};
    my $quarant = $conf->{'simscan_quarantine'};
    my $qdir    = $conf->{'qmail_dir'};
    my $ver     = $conf->{'install_simscan'};
    my $args    = $conf->{'simscan_spamc_args'};
    my $custom  = $conf->{'simscan_custom_smtp_reject'};

    if ( -x "$qdir/bin/simscan" ) {
        return 0
          unless $utility->yes_or_no(
            question =>
              "simscan is already installed, do you want to reinstall?",
            timeout => 60,
          );
    }

    $self->ripmime(  debug=>$debug ) if $conf->{'simscan_ripmime'};

    my $bin;
    my $confcmd = "./configure ";
    $confcmd .= "--enable-user=$user ";
    if ( $self->is_newer( min => "1.0.7", cur => $ver ) ) {

        # ripmime feature added in simscan 1.0.8
        if ( $conf->{'simscan_ripmime'} ) {
            $bin = $utility->find_the_bin( bin => "ripmime", fatal => 0, debug=>$debug );
            unless ( -x $bin ) {
                croak "couldn't find $bin, install ripmime!\n";
            }
            $confcmd .= "--enable-ripmime=$bin ";
        }
        else {
            $confcmd .= "--disable-ripmime ";
        }
    }
    else {
        print
"simscan: ripmime doesn't work with simcan 1.0.7 and older and you have selected $ver!\n";
    }

    if ( $conf->{'simscan_clamav'} ) {
        $bin = $utility->find_the_bin( bin => "clamdscan", fatal => 0, debug=>$debug );
        if ( !-x $bin ) { croak "couldn't find $bin, install ClamAV!\n" }
        $confcmd .= "--enable-clamdscan=$bin ";

        $confcmd .= "--enable-clamavdb-path=";

            -d "/var/db/clamav" ? $confcmd .= "/var/db/clamav "
          : -d "/usr/local/share/clamav" ? $confcmd .= "/usr/local/share/clamav "
          : -d "/opt/local/share/clamav" ? $confcmd .= "/opt/local/share/clamav "
          : croak
          "clamav support is specified but I can't find the ClamAV db path!";

        $bin = $utility->find_the_bin( bin => "sigtool", fatal => 0 );
        unless ( -x $bin ) { croak "couldn't find $bin, install ClamAV!\n" }

        $confcmd .= "--enable-sigtool-path=$bin ";
    }

    if ( $conf->{'simscan_spamassassin'} ) {
        my $spamc = $utility->find_the_bin( bin => "spamc", fatal => 0, debug=>$debug );
        $confcmd .=
          "--enable-spam=y --enable-spamc-user=y --enable-spamc=$spamc ";
        if ( $conf->{'simscan_received'} ) {
            $bin = $utility->find_the_bin( bin => "spamassassin", fatal => 0, debug=>$debug );
            if ( !-x $bin ) {
                croak "couldn't find $bin, install SpamAssassin!\n";
            }
            $confcmd .= "--enable-spamassassin-path=$bin ";
        }
    }

    $confcmd .= "--enable-received=y "       if $conf->{'simscan_received'};
    $confcmd .= "--enable-spam-hits=$reje "  if ($reje);
    $confcmd .= "--enable-spamc-args=$args " if ($args);
    $confcmd .= "--enable-attach=y " if $conf->{'simscan_block_attachments'};
    $confcmd .= "--enable-qmaildir=$qdir " if $qdir;
    $confcmd .= "--enable-qmail-queue=$qdir/bin/qmail-queue " if $qdir;
    $confcmd .= "--enable-per-domain=y " if $conf->{'simscan_per_domain'};
    $confcmd .= "--enable-custom-smtp-reject=y " if ($custom);
    $confcmd .= "--enable-spam-passthru=y "
      if ( $conf->{'simscan_spam_passthru'} );

    if ( $conf->{'simscan_regex_scanner'} ) {
        if ( $OSNAME eq "freebsd" ) {
            $freebsd->port_install( port => "pcre", base => "devel", debug=>$debug );
        }
        else {
            print "\n\nNOTICE: Be sure to install pcre!!\n\n";
        }
        $confcmd .= "--enable-regex=y ";
    }

    if ( $quarant && -d $quarant ) {
        $confcmd .= "--enable-quarantinedir=$quarant ";
    }

    print "configure: $confcmd\n";

    $utility->install_from_source(
        conf           => $conf,
        package        => "simscan-$ver",
        site           => 'http://www.inter7.com',
        url            => '/simscan',
        targets        => [ $confcmd, 'make', 'make install-strip' ],
        bintest        => "$qdir/bin/simscan",
        debug          => $debug,
        source_sub_dir => 'mail',
    );

    $self->simscan_conf(  debug=>$debug );
}

sub simscan_conf {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my ( $file, @lines );

    my $user  = $conf->{'simscan_user'}       || "clamav";
    my $group = $conf->{'smtpd_run_as_group'} || "vchkpw";
    my $reje = $conf->{'simscan_spam_hits_reject'};

    my $uid = getpwnam($user);
    my $gid = getgrnam($group);
    chown( $uid, $gid, "/var/qmail/simscan" )
      or carp "ERROR: chown /var/qmail/simscan: $!\n";

    #	if ( $conf->{'simscan_per_domain'} ) { #
    #		$file = "/var/qmail/control/simcontrol";

    my @attach;
    if ( $conf->{'simscan_block_attachments'} ) {

        $file = "/var/qmail/control/ssattach";
        foreach ( split( /,/, $conf->{'simscan_block_types'} ) ) {
            push @attach, ".$_";
        }
        $utility->file_write( file => $file, lines => \@attach, debug=>$debug );
    }

    $file = "/var/qmail/control/simcontrol";
    if ( !-e $file ) {
        my @opts;
        $conf->{'simscan_clamav'}
          ? push @opts, "clam=yes"
          : push @opts, "clam=no";

        $conf->{'simscan_spamassassin'}
          ? push @opts, "spam=yes"
          : push @opts, "spam=no";

        $conf->{'simscan_trophie'}
          ? push @opts, "trophie=yes"
          : push @opts, "trophie=no";

        $reje
          ? push @opts, "spam_hits=$reje"
          : print "no reject.\n";

        if ( @attach > 0 ) {
            my $line  = "attach=";
            my $first = shift @attach;
            $line .= "$first";
            foreach (@attach) { $line .= ":$_"; }
            push @opts, $line;
        }

        @lines = "#postmaster\@example.com:" . join( ",", @opts );
        push @lines, "#example.com:" . join( ",", @opts );
        push @lines, "#";
        push @lines, ":" . join( ",",             @opts );

        if ( -e $file ) {
            $utility->file_write( file => "$file.new", lines => \@lines, debug=>$debug );
            print
"\nNOTICE: simcontrol written to $file.new. You need to review and install it!\n";
        }
        else {
            $utility->file_write( file => $file, lines => \@lines, debug=>$debug );
        }
    }

    if ( -x "/var/qmail/bin/simscanmk" ) {
        $utility->syscmd( command => "/var/qmail/bin/simscanmk", debug=>$debug );
        $utility->syscmd( command => "/var/qmail/bin/simscanmk -g", debug=>$debug );
    }
}

sub simscan_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $qdir = $conf->{'qmail_dir'};

    if ( ! $conf->{'install_simscan'} ) {
        print "simscan installation disabled, skipping test!\n";
        return;
    }

    print "testing simscan...";
    my $scan = "$qdir/bin/simscan";
    unless ( -x $scan ) {
        print "FAILURE: Simscan could not be found at $scan!\n";
        return;
    }

    $ENV{"QMAILQUEUE"} = $scan;
    $toaster->email_send( conf => $conf, type => "clean" );
    $toaster->email_send( conf => $conf, type => "attach" );
    $toaster->email_send( conf => $conf, type => "virus" );
    $toaster->email_send( conf => $conf, type => "clam" );
    $toaster->email_send( conf => $conf, type => "spam" );
}

sub spamassassin {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( !$conf->{'install_spamassassin'} ) {
        $utility->_formatted( "spamassassin: installing",
            "skipping (disabled)" )
          if $debug;
        return 0;
    }

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }


    if ( $OSNAME eq "freebsd" ) {

        $freebsd->port_install( port => "p5-Mail-SPF-Query", base => "mail", debug=>$debug );
        $freebsd->port_install(
            port  => "p5-Mail-SpamAssassin",
            base  => "mail",
            flags => "WITHOUT_SSL=1 BATCH=yes",
            debug => $debug,
        );

        # the old port didn't install the spamd.sh file
        # new versions install sa-spamd.sh and require the rc.conf flag

        my $start = -f "/usr/local/etc/rc.d/spamd.sh" ? "/usr/local/etc/rc.d/spamd.sh"
                  : -f "/usr/local/etc/rc.d/spamd"    ? "/usr/local/etc/rc.d/spamd"
                  : "/usr/local/etc/rc.d/sa-spamd";   # current location (9/23/06)

        if ( !-e $start && -e "$start-dist" ) {
            $utility->syscmd( command => "cp $start-dist $start", debug=>$debug );
        }

        my $flags = $conf->{'install_spamassassin_flags'} || "-v -q -x";

        $freebsd->rc_dot_conf_check(
            check => "spamd_enable",
            line  => 'spamd_enable="YES"',
            debug => $debug,
        );
        $freebsd->rc_dot_conf_check(
            check => "spamd_flags",
            line  => qq{spamd_flags="$flags"},
            debug => $debug,
        );

        unless ( $utility->is_process_running("spamd") ) {
            if ( -x $start ) {
                print "Starting SpamAssassin...";
                $utility->syscmd( command => "$start restart", debug=>$debug );
                print "done.\n";
            }
            else { print "WARN: couldn't start SpamAssassin's spamd.\n"; }
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        $darwin->port_install( port_name => "procmail", debug=>$debug ) 
            if $conf->{'install_procmail'};
        $darwin->port_install( port_name => "unzip", debug=>$debug );
        $darwin->port_install( port_name => "p5-mail-audit", debug=>$debug );
        $darwin->port_install( port_name => "p5-mail-spamassassin", debug=>$debug );
        $darwin->port_install( port_name => "bogofilter", debug=>$debug )
          if $conf->{'install_bogofilter'};
    }

    $perl->module_load( module => "Time::HiRes", debug=>$debug, auto=>1 );
    $perl->module_load( module => "Mail::Audit", debug=>$debug, auto=>1 );
    $perl->module_load( module => "Mail::SpamAssassin", debug=>$debug, auto=>1 );
    $self->maildrop(  debug=>$debug );

    $self->spamassassin_sql(  debug=>$debug );
}

sub spamassassin_sql {

    # set up the mysql database for use with SpamAssassin
    # http://svn.apache.org/repos/asf/spamassassin/branches/3.0/sql/README

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    unless ( $conf->{'install_spamassassin_sql'} ) {
        print "SpamAssasin MySQL integration not selected. skipping.\n";
        return 0;
    }

    if ( $OSNAME eq "freebsd" ) {

        # is SpamAssassin installed
        if ( $freebsd->is_port_installed( port => "p5-Mail-SpamAssassin", debug=>$debug ) ) {
            print
"skipping MySQL SpamAssassin database setup, as SpamAssassin doesn't appear to be installed.\n";
            return 0;
        }

        print "SpamAssassin is installed, setting up MySQL databases\n";

        my $user = $conf->{'install_spamassassin_dbuser'};
        my $pass = $conf->{'install_spamassassin_dbpass'};

        require Mail::Toaster::Mysql;
        my $mysql = Mail::Toaster::Mysql->new();

        my $dot = $mysql->parse_dot_file( ".my.cnf", "[mysql]", 0 );
        my ( $dbh, $dsn, $drh ) = $mysql->connect( $dot, 1 );

        if ($dbh) {
            my $query = "use spamassassin";
            my $sth = $mysql->query( $dbh, $query, 1 );
            if ( $sth->errstr ) {
                print "vpopmail: oops, no spamassassin database.\n";
                print "vpopmail: creating MySQL spamassassin database.\n";
                $query = "CREATE DATABASE spamassassin";
                $sth   = $mysql->query( $dbh, $query );
                $query =
"GRANT ALL PRIVILEGES ON spamassassin.* TO $user\@'localhost' IDENTIFIED BY '$pass'";
                $sth = $mysql->query( $dbh, $query );
                $sth = $mysql->query( $dbh, "flush privileges" );
                $sth->finish;
            }
            else {
                print "spamassassin: spamassassin database exists!\n";
                $sth->finish;
            }
        }

        my $mysqlbin = $utility->find_the_bin( bin => "mysql", fatal => 0, debug=>$debug );
        my $sqldir = "/usr/local/share/doc/p5-Mail-SpamAssassin/sql";
        foreach (qw/bayes_mysql.sql awl_mysql.sql userpref_mysql.sql/) {
            $utility->syscmd( command => "$mysqlbin spamassassin < $sqldir/$_", debug=>$debug )
              if ( -f "$sqldir/$_" );
        }

        my $file = "/usr/local/etc/mail/spamassassin/sql.cf";
        unless ( -f $file ) {
            my @lines = <<EO_SQL_CF;
user_scores_dsn                 DBI:mysql:spamassassin:localhost
user_scores_sql_username        $conf->{'install_spamassassin_dbuser'}
user_scores_sql_password        $conf->{'install_spamassassin_dbpass'}
#user_scores_sql_table           userpref

bayes_store_module              Mail::SpamAssassin::BayesStore::SQL
bayes_sql_dsn                   DBI:mysql:spamassassin:localhost
bayes_sql_username              $conf->{'install_spamassassin_dbuser'}
bayes_sql_password              $conf->{'install_spamassassin_dbpass'}
#bayes_sql_override_username    someusername

auto_whitelist_factory          Mail::SpamAssassin::SQLBasedAddrList
user_awl_dsn                    DBI:mysql:spamassassin:localhost
user_awl_sql_username           $conf->{'install_spamassassin_dbuser'}
user_awl_sql_password           $conf->{'install_spamassassin_dbpass'}
user_awl_sql_table              awl
EO_SQL_CF
            $utility->file_write( file => $file, lines => \@lines );
        }
    }
    else {
        print
"Sorry, automatic MySQL SpamAssassin setup is not available on $OSNAME yet. You must
do this process manually by locating the *_mysql.sql files that arrived with SpamAssassin. Run
each one like this:
	mysql spamassassin < awl_mysql.sql
	mysql spamassassin < bayes_mysql.sql
	mysql spamassassin < userpref_mysql.sql

Then configure SpamAssassin to use them by creating a sql.cf file in SpamAssassin's etc dir with
the following contents:

	user_scores_dsn                 DBI:mysql:spamassassin:localhost
	user_scores_sql_username        $conf->{'install_spamassassin_dbuser'}
	user_scores_sql_password        $conf->{'install_spamassassin_dbpass'}

	# default query
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username ASC
	# global, then domain level
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' OR username = '@~'||_DOMAIN_ ORDER BY username ASC
	# global overrides user prefs
	#SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\@GLOBAL' ORDER BY username DESC
	# from the SA SQL README
	#user_scores_sql_custom_query     SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '\$GLOBAL' OR username = CONCAT('%',_DOMAIN_) ORDER BY username ASC

	bayes_store_module              Mail::SpamAssassin::BayesStore::SQL
	bayes_sql_dsn                   DBI:mysql:spamassassin:localhost
	bayes_sql_username              $conf->{'install_spamassassin_dbuser'}
	bayes_sql_password              $conf->{'install_spamassassin_dbpass'}
	#bayes_sql_override_username    someusername

	auto_whitelist_factory       Mail::SpamAssassin::SQLBasedAddrList
	user_awl_dsn                 DBI:mysql:spamassassin:localhost
	user_awl_sql_username        $conf->{'install_spamassassin_dbuser'}
	user_awl_sql_password        $conf->{'install_spamassassin_dbpass'}
	user_awl_sql_table           awl
";
    }
}

sub smtp_test_auth {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    print "smtp_test_auth: checking Net::SMTP_auth .......................... ";
    $perl->module_load( module => "Net::SMTP_auth", debug=>$debug, auto=>1 );
    print "ok\n";

    my $user = $conf->{'toaster_test_email'}      || 'test2@example.com';
    my $pass = $conf->{'toaster_test_email_pass'} || 'cHanGeMe';
    my $host = $conf->{'smtpd_listen_on_address'} || 'localhost';

    if ( $host eq "system" || $host eq "qmail" || $host eq "all" ) {
        $host = "localhost";
    }

    print "getting a list of SMTP AUTH methods...";
    my $smtp = Net::SMTP_auth->new($host);
    unless ( defined $smtp ) {
        $utility->_formatted(
            "smtp_test_auth: (couldn't connect to smtp port on $host!)",
            "FAILED" );
        return 0;
    }

    my @auths = $smtp->auth_types();
    print "done.\n";
    $smtp->quit;

    # test each authentication method the server advertises
    AUTH:
    foreach (@auths) {

        $smtp = Net::SMTP_auth->new($host);
        if ( ! $smtp->auth( $_, $user, $pass ) ) {
            $utility->_formatted(
                "smtp_test_auth: sending with $_ authentication", "FAILED" );
            next AUTH;
        };

        $smtp->mail( $conf->{'toaster_admin_email'} );
        $smtp->to('postmaster');
        $smtp->data();
        $smtp->datasend("To: postmaster\n");
        $smtp->datasend("\n");
        $smtp->datasend("A simple test message\n");
        $smtp->dataend();

        $smtp->quit;
        $utility->_formatted("smtp_test_auth: sending with $_ authentication", "ok" );
    }
}

sub socklog {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'ip'    => { type => SCALAR, },
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
        },
    );

    my $ip    = $p{'ip'};
    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $user  = $conf->{'qmail_log_user'}  || "qmaill";
    my $group = $conf->{'qmail_log_group'} || "qnofiles";

    my $uid = getpwnam($user);
    my $gid = getgrnam($group);

    my $log = $conf->{'qmail_log_base'};
    unless ( -d $log ) { $log = "/var/log/mail" }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "socklog", base => "sysutils" );
    }
    else {
        print "\n\nNOTICE: Be sure to install socklog!!\n\n";
    }
    socklog_qmail_control( "send", $ip, $user, undef, $log );
    socklog_qmail_control( "smtp", $ip, $user, undef, $log );
    socklog_qmail_control( "pop3", $ip, $user, undef, $log );

    unless ( -d $log ) {
        mkdir( $log, oct('0755') ) or croak "socklog: couldn't create $log: $!";
        chown( $uid, $gid, $log ) or croak "socklog: couldn't chown  $log: $!";
    }

    foreach my $prot (qw/ send smtp pop3 /) {
        unless ( -d "$log/$prot" ) {
            mkdir( "$log/$prot", oct('0755') )
              or croak "socklog: couldn't create $log/$prot: $!";
        }
        chown( $uid, $gid, "$log/$prot" )
          or croak "socklog: couldn't chown $log/$prot: $!";
    }
}

sub socklog_qmail_control {

    my ( $serv, $ip, $user, $supervise, $log, $debug ) = @_;

    $ip        ||= "192.168.2.9";
    $user      ||= "qmaill";
    $supervise ||= "/var/qmail/supervise";
    $log       ||= "/var/log/mail";

    my $run_f = "$supervise/$serv/log/run";

    if ( -s $run_f ) {
        print "socklog_qmail_control skipping: $run_f exists!\n";
        return 1;
    }

    print "socklog_qmail_control creating: $run_f...";
    my @socklog_run_file = <<EO_SOCKLOG;
#!/bin/sh
LOGDIR=$log
LOGSERVERIP=$ip
PORT=10116

PATH=/var/qmail/bin:/usr/local/bin:/usr/bin:/bin
export PATH

exec setuidgid $user multilog t s4096 n20 \
  !"tryto -pv tcpclient -v \$LOGSERVERIP \$PORT sh -c 'cat >&7'" \
  \${LOGDIR}/$serv
EO_SOCKLOG
    $utility->file_write( file => $run_f, lines => \@socklog_run_file, debug=>$debug );

#	open(my $RUN, ">", $run_f) or croak "socklog_qmail_control: couldn't open for write: $!";
#	close $RUN;
    chmod oct('0755'), $run_f or croak "socklog: couldn't chmod $run_f: $!";
    print "done.\n";
}

sub config_spamassassin {

    print "Visit http://www.yrex.com/spam/spamconfig.php \n";
}

sub squirrelmail {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $ver = $conf->{'install_squirrelmail'};

    unless ($ver) {
        print "skipping SquirrelMail install because it's not enabled!\n";
        return 0;
    }

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {
        if ( $freebsd->is_port_installed( port => "squirrelmail", debug=>$debug ) ) {
            print "Squirrelmail is already installed, skipping!\n";
            return 0;
        }

	$freebsd->port_install( 
            port => "php4-mysql", 
            base => "databases" ,
            debug => $debug,
	);

	$freebsd->port_install( 
            port => "pear-DB", 
            base => "databases" ,
            debug => $debug,
	);

        if ( $conf->{'install_apache'} == 2 ) {

            $freebsd->port_install(
                port  => "php4-mbstring",
                base  => "converters",
                flags => "BATCH,WITH_APACHE2,WITH_DATABASE",
                debug => $debug,
            );

            $freebsd->port_install(
                port  => "squirrelmail",
                base  => "mail",
                flags => "WITH_APACHE2=yes,WITH_DATABASE=1",
                debug => $debug,
            );
        }
        else {
            $freebsd->port_install( 
                port => "squirrelmail", 
                base => "mail" ,
                debug => $debug,
            );
        }

        if ( -d "/usr/local/www/squirrelmail" ) {
            unless ( -e "/usr/local/www/squirrelmail/config/config.php" ) {
                chdir("/usr/local/www/squirrelmail/config");
                print "squirrelmail: installing a default config.php\n";

                $utility->file_write(
                    file  => "config.php",
                    lines => [ $self->squirrelmail_config() ],
                    debug => $debug,
                );
            }
        }

        if ( $freebsd->is_port_installed( port => "squirrelmail", debug=>$debug ) ) {
            $self->squirrelmail_mysql(debug=>$debug);
            return 1;
        }
    }

    $ver = "1.4.6" if ( $ver eq "port" );

    print "squirrelmail: attempting to install from sources.\n";

    my $htdocs = $conf->{'toaster_http_docs'} || "/usr/local/www/data";
    my $srcdir = $conf->{'toaster_src_dir'}   || "/usr/local/src";
    $srcdir .= "/mail";

    unless ( -d $htdocs ) {
        $htdocs = "/var/www/data" if ( -d "/var/www/data" );    # linux
        $htdocs = "/Library/Webserver/Documents"
          if ( -d "/Library/Webserver/Documents" );             # OS X
    }

    if ( -d "$htdocs/squirrelmail" ) {
        print "Squirrelmail is already installed, I won't install it again!\n";
        return 0;
    }

    $utility->install_from_source(
        conf           => $conf,
        package        => "squirrelmail-$ver",
        site           => "http://" . $conf->{'toaster_sf_mirror'},
        url            => "/squirrelmail",
        targets        => ["mv $srcdir/squirrelmail-$ver $htdocs/squirrelmail"],
        source_sub_dir => 'mail',
        debug          => $debug,
    );

    chdir("$htdocs/squirrelmail/config");
    print "squirrelmail: installing a default config.php";
    $utility->file_write(
        file  => "config.php",
        lines => [ $self->squirrelmail_config( ) ],
        debug => $debug,
    );

    $self->squirrelmail_mysql(  debug=>$debug );
}

sub squirrelmail_mysql {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    return 0 unless $conf->{'install_squirrelmail_sql'};

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "pear-DB", base => "databases" );
        print
'\nHEY!  You need to add include_path = ".:/usr/local/share/pear" to php.ini.\n\n';
    }

    my $db   = "squirrelmail";
    my $user = "squirrel";
    my $pass = "secret";
    my $host = "localhost";

    require Mail::Toaster::Mysql;
    my $mysql = Mail::Toaster::Mysql->new();

    my $dot = $mysql->parse_dot_file( ".my.cnf", "[mysql]", 0 );
    my ( $dbh, $dsn, $drh ) = $mysql->connect( $dot, 1 );

    if ($dbh) {
        my $query = "use squirrelmail";
        my $sth   = $mysql->query( $dbh, $query, 1 );

        if ( !$sth->errstr ) {
            print "squirrelmail: squirrelmail database already exists.\n";
            $sth->finish;
            return 1;
        }

        print "squirrelmail: creating MySQL database for squirrelmail.\n";
        $query = "CREATE DATABASE squirrelmail";
        $sth   = $mysql->query( $dbh, $query );

        $query =
"GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass'";
        $sth = $mysql->query( $dbh, $query );

        $query =
"CREATE TABLE squirrelmail.address ( owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL, firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL, email varchar(128) DEFAULT '' NOT NULL,
label varchar(255), PRIMARY KEY (owner,nickname), KEY firstname (firstname,lastname));
";
        $sth = $mysql->query( $dbh, $query );

        $query =
"CREATE TABLE squirrelmail.global_abook ( owner varchar(128) DEFAULT '' NOT NULL, nickname varchar(16) DEFAULT '' NOT NULL, firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL, email varchar(128) DEFAULT '' NOT NULL,
label varchar(255), PRIMARY KEY (owner,nickname), KEY firstname (firstname,lastname));";

        $sth = $mysql->query( $dbh, $query );

        $query =
"CREATE TABLE squirrelmail.userprefs ( user varchar(128) DEFAULT '' NOT NULL, prefkey varchar(64) DEFAULT '' NOT NULL, prefval BLOB DEFAULT '' NOT NULL, PRIMARY KEY (user,prefkey))";
        $sth = $mysql->query( $dbh, $query );

        $sth->finish;
        return 1;
    }

    print "

WARNING: I could not connect to your database server!  If this is a new install, 
you will need to connect to your database server and run this command manually:

mysql -u root -h $host -p
CREATE DATABASE squirrelmail;
GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass';
CREATE TABLE squirrelmail.address (
owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL,
firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL,
email varchar(128) DEFAULT '' NOT NULL,
label varchar(255),
PRIMARY KEY (owner,nickname),
KEY firstname (firstname,lastname)
);
CREATE TABLE squirrelmail.global_abook (
owner varchar(128) DEFAULT '' NOT NULL,
nickname varchar(16) DEFAULT '' NOT NULL,
firstname varchar(128) DEFAULT '' NOT NULL,
lastname varchar(128) DEFAULT '' NOT NULL,
email varchar(128) DEFAULT '' NOT NULL,
label varchar(255),
PRIMARY KEY (owner,nickname),
KEY firstname (firstname,lastname)
);
CREATE TABLE squirrelmail.userprefs (
user varchar(128) DEFAULT '' NOT NULL,
prefkey varchar(64) DEFAULT '' NOT NULL,
prefval BLOB DEFAULT '' NOT NULL,
PRIMARY KEY (user,prefkey)
);
quit;

If this is an upgrade, you can probably ignore this warning.

";
}

sub squirrelmail_config {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $mailhost = $conf->{'toaster_hostname'};
    my $dsn      = "";

    if ( $conf->{'install_squirrelmail_sql'} ) {
        $dsn = 'mysql://squirrel:secret@localhost/squirrelmail';
    }

    my $string = <<"EOCONFIG";
<?php

/**
 * SquirrelMail Configuration File
 * Generated by Mail::Toaster http://mail-toaster.org/
*/

global \$version;
\$config_version = '1.4.0';
\$config_use_color = 2;

\$org_name      = "SquirrelMail";
\$org_logo      = SM_PATH . 'images/tnpi_logo.jpg';
\$org_logo_width  = '308';
\$org_logo_height = '111';
\$org_title     = "SquirrelMail \$version";
\$signout_page  = 'https://$mailhost/';
\$frame_top     = '_top';

\$provider_uri     = 'http://mail-toaster.org/docs/';
\$provider_name     = 'Powered by Mail::Toaster';

\$motd = "";

\$squirrelmail_default_language = 'en_US';

\$domain                 = '$mailhost';
\$imapServerAddress      = 'localhost';
\$imapPort               = 143;
\$useSendmail            = true;
\$smtpServerAddress      = 'localhost';
\$smtpPort               = 25;
\$sendmail_path          = '/usr/sbin/sendmail';
\$pop_before_smtp        = false;
\$imap_server_type       = 'courier';
\$invert_time            = false;
\$optional_delimiter     = 'detect';

\$default_folder_prefix          = '';
\$trash_folder                   = 'INBOX.Trash';
\$sent_folder                    = 'INBOX.Sent';
\$draft_folder                   = 'INBOX.Drafts';
\$default_move_to_trash          = true;
\$default_move_to_sent           = true;
\$default_save_as_draft          = true;
\$show_prefix_option             = false;
\$list_special_folders_first     = true;
\$use_special_folder_color       = true;
\$auto_expunge                   = true;
\$default_sub_of_inbox           = true;
\$show_contain_subfolders_option = false;
\$default_unseen_notify          = 2;
\$default_unseen_type            = 1;
\$auto_create_special            = true;
\$delete_folder                  = false;
\$noselect_fix_enable            = false;

\$default_charset          = 'iso-8859-1';
\$data_dir                 = '/var/spool/squirrelmail/pref/';
\$attachment_dir           = '/var/spool/squirrelmail/attach/';
\$dir_hash_level           = 0;
\$default_left_size        = '150';
\$force_username_lowercase = false;
\$default_use_priority     = true;
\$hide_sm_attributions     = false;
\$default_use_mdn          = true;
\$edit_identity            = true;
\$edit_name                = true;
\$allow_thread_sort        = false;
\$allow_server_sort        = false;
\$allow_charset_search     = true;
\$uid_support              = true;


\$theme_css = '';
\$theme_default = 0;
\$theme[0]['PATH'] = SM_PATH . 'themes/default_theme.php';
\$theme[0]['NAME'] = 'Default';
\$theme[1]['PATH'] = SM_PATH . 'themes/plain_blue_theme.php';
\$theme[1]['NAME'] = 'Plain Blue';
\$theme[2]['PATH'] = SM_PATH . 'themes/sandstorm_theme.php';
\$theme[2]['NAME'] = 'Sand Storm';
\$theme[3]['PATH'] = SM_PATH . 'themes/deepocean_theme.php';
\$theme[3]['NAME'] = 'Deep Ocean';
\$theme[4]['PATH'] = SM_PATH . 'themes/slashdot_theme.php';
\$theme[4]['NAME'] = 'Slashdot';
\$theme[5]['PATH'] = SM_PATH . 'themes/purple_theme.php';
\$theme[5]['NAME'] = 'Purple';
\$theme[6]['PATH'] = SM_PATH . 'themes/forest_theme.php';
\$theme[6]['NAME'] = 'Forest';
\$theme[7]['PATH'] = SM_PATH . 'themes/ice_theme.php';
\$theme[7]['NAME'] = 'Ice';
\$theme[8]['PATH'] = SM_PATH . 'themes/seaspray_theme.php';
\$theme[8]['NAME'] = 'Sea Spray';
\$theme[9]['PATH'] = SM_PATH . 'themes/bluesteel_theme.php';
\$theme[9]['NAME'] = 'Blue Steel';
\$theme[10]['PATH'] = SM_PATH . 'themes/dark_grey_theme.php';
\$theme[10]['NAME'] = 'Dark Grey';
\$theme[11]['PATH'] = SM_PATH . 'themes/high_contrast_theme.php';
\$theme[11]['NAME'] = 'High Contrast';
\$theme[12]['PATH'] = SM_PATH . 'themes/black_bean_burrito_theme.php';
\$theme[12]['NAME'] = 'Black Bean Burrito';
\$theme[13]['PATH'] = SM_PATH . 'themes/servery_theme.php';
\$theme[13]['NAME'] = 'Servery';
\$theme[14]['PATH'] = SM_PATH . 'themes/maize_theme.php';
\$theme[14]['NAME'] = 'Maize';
\$theme[15]['PATH'] = SM_PATH . 'themes/bluesnews_theme.php';
\$theme[15]['NAME'] = 'BluesNews';
\$theme[16]['PATH'] = SM_PATH . 'themes/deepocean2_theme.php';
\$theme[16]['NAME'] = 'Deep Ocean 2';
\$theme[17]['PATH'] = SM_PATH . 'themes/blue_grey_theme.php';
\$theme[17]['NAME'] = 'Blue Grey';
\$theme[18]['PATH'] = SM_PATH . 'themes/dompie_theme.php';
\$theme[18]['NAME'] = 'Dompie';
\$theme[19]['PATH'] = SM_PATH . 'themes/methodical_theme.php';
\$theme[19]['NAME'] = 'Methodical';
\$theme[20]['PATH'] = SM_PATH . 'themes/greenhouse_effect.php';
\$theme[20]['NAME'] = 'Greenhouse Effect (Changes)';
\$theme[21]['PATH'] = SM_PATH . 'themes/in_the_pink.php';
\$theme[21]['NAME'] = 'In The Pink (Changes)';
\$theme[22]['PATH'] = SM_PATH . 'themes/kind_of_blue.php';
\$theme[22]['NAME'] = 'Kind of Blue (Changes)';
\$theme[23]['PATH'] = SM_PATH . 'themes/monostochastic.php';
\$theme[23]['NAME'] = 'Monostochastic (Changes)';
\$theme[24]['PATH'] = SM_PATH . 'themes/shades_of_grey.php';
\$theme[24]['NAME'] = 'Shades of Grey (Changes)';
\$theme[25]['PATH'] = SM_PATH . 'themes/spice_of_life.php';
\$theme[25]['NAME'] = 'Spice of Life (Changes)';
\$theme[26]['PATH'] = SM_PATH . 'themes/spice_of_life_lite.php';
\$theme[26]['NAME'] = 'Spice of Life - Lite (Changes)';
\$theme[27]['PATH'] = SM_PATH . 'themes/spice_of_life_dark.php';
\$theme[27]['NAME'] = 'Spice of Life - Dark (Changes)';
\$theme[28]['PATH'] = SM_PATH . 'themes/christmas.php';
\$theme[28]['NAME'] = 'Holiday - Christmas';
\$theme[29]['PATH'] = SM_PATH . 'themes/darkness.php';
\$theme[29]['NAME'] = 'Darkness (Changes)';
\$theme[30]['PATH'] = SM_PATH . 'themes/random.php';
\$theme[30]['NAME'] = 'Random (Changes every login)';
\$theme[31]['PATH'] = SM_PATH . 'themes/midnight.php';
\$theme[31]['NAME'] = 'Midnight';
\$theme[32]['PATH'] = SM_PATH . 'themes/alien_glow.php';
\$theme[32]['NAME'] = 'Alien Glow';
\$theme[33]['PATH'] = SM_PATH . 'themes/dark_green.php';
\$theme[33]['NAME'] = 'Dark Green';
\$theme[34]['PATH'] = SM_PATH . 'themes/penguin.php';
\$theme[34]['NAME'] = 'Penguin';
\$theme[35]['PATH'] = SM_PATH . 'themes/minimal_bw.php';
\$theme[35]['NAME'] = 'Minimal BW';

\$default_use_javascript_addr_book = false;
\$addrbook_dsn = '$dsn';
\$addrbook_table = 'address';

\$prefs_dsn = '$dsn';
\$prefs_table = 'userprefs';
\$prefs_user_field = 'user';
\$prefs_key_field = 'prefkey';
\$prefs_val_field = 'prefval';
\$no_list_for_subscribe = false;
\$smtp_auth_mech = 'none';
\$imap_auth_mech = 'login';
\$use_imap_tls = false;
\$use_smtp_tls = false;
\$session_name = 'SQMSESSID';

\@include SM_PATH . 'config/config_local.php';

?>
EOCONFIG
      ;
    chomp $string;
    return $string;
}

sub sqwebmail {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $ver = $conf->{'install_sqwebmail'};

    unless ($ver) {
        print "Sqwebmail installation is disabled!\n";
        return 0;
    }

    $self->courier_authlib(  debug=>$debug, );

    my $httpdir = $conf->{'toaster_http_base'} || "/usr/local/www";
    my $cgi     = $conf->{'toaster_cgi_bin'};
    my $prefix  = $conf->{'toaster_prefix'} || "/usr/local";

    unless ( $cgi && -d $cgi ) { $cgi = "$httpdir/cgi-bin" }

    my $datadir = $conf->{'toaster_http_docs'};
    unless ( -d $datadir ) {
        if    ( -d "$httpdir/data/mail" ) { $datadir = "$httpdir/data/mail"; }
        elsif ( -d "$httpdir/mail" )      { $datadir = "$httpdir/mail"; }
        else { $datadir = "$httpdir/data"; }
    }

    my $mime = -e "$prefix/etc/apache2/mime.types"  ? "$prefix/etc/apache2/mime.types"
             : -e "$prefix/etc/apache22/mime.types" ? "$prefix/etc/apache22/mime.types"
             : "$prefix/etc/apache/mime.types";

    my $cachedir = "/var/run/sqwebmail";

    if ( $OSNAME eq "freebsd" && $ver eq "port" ) {

        #$self->expect( debug=>$debug );

        unless ( $freebsd->is_port_installed( port => "gnupg", debug=>$debug ) ) {
            $freebsd->package_install( port => "gnupg", debug=>$debug )
              or $freebsd->port_install( 
					port    => "gnupg", 
					base    => "security", 
					debug   => $debug,
					options => "# This file was generated by mail-toaster
# No user-servicable parts inside!
# Options for gnupg-1.4.5
_OPTIONS_READ=gnupg-1.4.5
WITHOUT_LDAP=true
WITHOUT_LIBICONV=true
WITHOUT_LIBUSB=true
WITHOUT_SUID_GPG=true
WITH_NLS=true",
				 );
        }

        if ( $cgi     =~ /\/usr\/local\/(.*)$/ ) { $cgi     = $1; }
        if ( $datadir =~ /\/usr\/local\/(.*)$/ ) { $datadir = $1; }

        my @args = "WITHOUT_AUTHDAEMON=yes";
        push @args, "WITH_HTTPS=yes";
        push @args, "WITH_VCHKPW=yes";
        push @args, "WITH_ISPELL=yes";
        push @args, "WITHOUT_IMAP=yes";
        #		push @args, "WITH_MIMETYPES";
        push @args, "CGIBINDIR=$cgi";
        push @args, "CGIBINSUBDIR=''";
        push @args, "WEBDATADIR=$datadir";
        push @args, "CACHEDIR=$cachedir";

        $freebsd->port_install(
            port  => "sqwebmail",
            base  => "mail",
            flags => join( ",", @args ),
            options => "# This file is auto-generated by 'make config'.
# No user-servicable parts inside!
# Options for sqwebmail-5.1.3
_OPTIONS_READ=sqwebmail-5.1.3
WITH_CACHEDIR=true
WITHOUT_GDBM=true
WITH_GZIP=true
WITH_HTTPS=true
WITH_HTTPS_LOGIN=true
WITHOUT_IMAP=true
WITH_ISPELL=true
WITH_MIMETYPES=true
WITHOUT_SENTRENAME=true
WITHOUT_AUTH_LDAP=true
WITHOUT_AUTH_MYSQL=true
WITHOUT_AUTH_PGSQL=true
WITHOUT_AUTH_USERDB=true
WITH_AUTH_VCHKPW=true",
            debug => $debug,
        );

        $freebsd->rc_dot_conf_check(
            check => "sqwebmaild_enable",
            line  => 'sqwebmaild_enable="YES"',
            debug => $debug,
        );

        print "sqwebmail: starting sqwebmaild.\n";
        my $start = "$prefix/etc/rc.d/sqwebmail-sqwebmaild";

          -x $start      ? $utility->syscmd( command => "$start start", debug=>$debug )
        : -x "$start.sh" ? $utility->syscmd( command => "$start.sh start", debug=>$debug )
        : carp "could not find the startup file for courier-imap!\n";
    }

    if (   $OSNAME eq "freebsd" && $ver eq "port"
        && $freebsd->is_port_installed( port => "sqwebmail", debug=>$debug ) )
    {
        $self->sqwebmail_conf( );
        return 1;
    }

    $ver = "4.0.7" if ( $ver eq "port" );

    if ( -x "$prefix/libexec/sqwebmail/authlib/authvchkpw" ) {
        if (
            !$utility->yes_or_no(
                question => "Sqwebmail is already installed, re-install it?",
                timeout  => 300
            )
          )
        {
            print "ok, skipping out.\n";
            return 0;
        }
    }

    my $package = "sqwebmail-$ver";
    my $site    = "http://" . $conf->{'toaster_sf_mirror'} . "/courier";
    my $src     = $conf->{'toaster_src_dir'} || "/usr/local/src";

    $utility->chdir_source_dir( dir => "$src/mail" );

    if ( -d "$package" ) {
        unless ( $utility->source_warning( $package, 1, $src ) ) {
            carp "sqwebmail: OK, skipping sqwebmail.\n";
            return 0;
        }
    }

    unless ( -e "$package.tar.bz2" ) {
        $utility->file_get( url => "$site/$package.tar.bz2" );
        unless ( -e "$package.tar.bz2" ) {
            croak "sqwebmail FAILED: coudn't fetch $package\n";
        }
    }

    $utility->archive_expand( archive => "$package.tar.bz2", debug => $debug );

    chdir($package) or croak "sqwebmail FAILED: coudn't chdir $package\n";

    my $cmd = "./configure --prefix=$prefix --with-htmldir=$prefix/share/sqwebmail "
        . "--with-cachedir=/var/run/sqwebmail --enable-webpass=vpopmail "
        . "--with-module=authvchkpw --enable-https --enable-logincache "
        . "--enable-imagedir=$datadir/webmail --without-authdaemon "
        . "--enable-mimetypes=$mime --enable-cgibindir=" . $cgi;

    if ( $OSNAME eq "darwin" ) { $cmd .= " --with-cacheowner=daemon"; };

    $utility->syscmd( command => $cmd, debug=>$debug );
    $utility->syscmd( command => "make configure-check", debug=>$debug );
    $utility->syscmd( command => "make check", debug=>$debug );
    $utility->syscmd( command => "make", debug=>$debug );

    my $share = "$prefix/share/sqwebmail";
    if ( -d $share ) {
        $utility->syscmd( command => "make install-exec", debug=>$debug );
        print
          "\n\nWARNING: I have only installed the $package binaries, thus\n";
        print "preserving any custom settings you might have in $share.\n";
        print
          "If you wish to do a full install, overwriting any customizations\n";
        print "you might have, then do this:\n\n";
        print "\tcd $src/mail/$package; make install\n";
    }
    else {
        $utility->syscmd( command => "make install", debug=>$debug );
        chmod oct('0755'), $share;
        chmod oct('0755'), "$datadir/sqwebmail";
        copy( "$share/ldapaddressbook.dist", "$share/ldapaddressbook" )
          or croak "copy failed: $!";
    }

    $utility->syscmd( command => "gmake install-configure", debug=>$debug );

    $self->sqwebmail_conf(  debug=>$debug );
}

sub sqwebmail_conf {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate(@_, {
            'debug' => {type=>SCALAR, optional=>1, default=>$debug },
        },
    );

       $debug = $p{'debug'};

    my $cachedir = "/var/run/sqwebmail";
    my $prefix   = $conf->{'toaster_prefix'} || "/usr/local";

    unless ( -e $cachedir ) {
        my $uid = getpwnam("bin");
        my $gid = getgrnam("bin");
        mkdir( $cachedir, oct('0755') );
        chown( $uid, $gid, $cachedir );
    }

    if ( $conf->{'qmailadmin_return_to_mailhome'} ) {

        my $file = "$prefix/share/sqwebmail/html/en-us/login.html";
        return unless ( -e $file );
        print "sqwebmail: Adjusting login to return to Mail Center page\n";

        my @lines = $utility->file_read( file => $file, debug=>$debug );

        my $newline =
          '<META http-equiv="refresh" content="1;URL=https://'
          . $conf->{'toaster_hostname'} . '/">';

        foreach my $line (@lines) {
            if ( $line =~ /meta name="GENERATOR"/ ) {
                $line = $newline;
            }
        }
        $utility->file_write( file => $file, lines => \@lines, debug=>$debug );
    }
}

sub supervise {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my $supervise = $conf->{'qmail_supervise'} || "/var/qmail/supervise";
    my $prefix    = $conf->{'toaster_prefix'}  || "/usr/local";

    #require Mail::Toaster::Qmail;
    #my $qmail   = Mail::Toaster::Qmail->new();

    # moved into $qmail->config  to make supervise more generic and less
    # toaster centric (ie, for djbdns only servers, etc)
    #$qmail->control_create( conf => $conf, debug => $debug );

    #$toaster->service_dir_create( conf => $conf, debug => $debug );
    #$toaster->supervise_dirs_create( conf => $conf, debug => $debug );

    #$qmail->install_qmail_control_files( conf => $conf, debug => $debug );
    #$qmail->install_qmail_control_log_files( conf => $conf, debug => $debug );

    $self->startup_script(  debug => $debug );
    $self->service_symlinks(  debug => $debug );

    my $start = "$prefix/sbin/services";
    print "\a";

    print "\n\nStarting up services (Ctrl-C to cancel). 

If there's any problems, you can stop all supervised services by running:

          $start stop\n
If you get a not found error, you need to refresh your shell. Tcsh users 
do this with the command 'rehash'.\n\nStarting in 5 seconds: ";
    foreach ( 1 .. 5 ) {
        print ".";
        sleep 1;
    }
    print "\n";

    if ( -x $start ) {
        $utility->syscmd( command => "$start start", debug=>$debug );
    }
}

sub service_symlinks {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    my $pop_service_dir =
      $qmail->service_dir_get( conf => $conf, prot => "pop3", debug => $debug );

    my $pop_supervise_dir = $qmail->supervise_dir_get(
        conf  => $conf,
        prot  => "pop3",
        debug => $debug
    );

    if ( !$conf->{'pop3_daemon'} eq "qpop3d" ) {
        if ( -e $pop_service_dir ) {
            print "Deleting $pop_service_dir because we aren't using qpop3d!\n"
              if $debug;
            unlink($pop_service_dir);
        }
        else {
            print "NOTICE: Not enabled due to configuration settings.\n";
        }
    }
    else {
        if ( -e $pop_service_dir ) {
            print "service_symlinks: $pop_service_dir already exists.\n"
              if $debug;
        }
        else {
            if ( -d $pop_supervise_dir ) {
                print "service_symlinks: creating symlink from $pop_supervise_dir"
                . " to $pop_service_dir\n"
                if $debug;
                symlink( $pop_supervise_dir, $pop_service_dir )
                   or croak "couldn't symlink $pop_supervise_dir: $!";
            }
            else {
                print "service_symlinks: skipping symlink to $pop_service_dir because target $pop_supervise_dir doesn't exist.\n";
            }
        }
    }

    foreach my $prot ( "smtp", "send", "submit" ) {

        my $svcdir = $qmail->service_dir_get(
            conf  => $conf,
            prot  => $prot,
            debug => $debug
        );
        my $supdir = $qmail->supervise_dir_get(
            conf  => $conf,
            prot  => $prot,
            debug => $debug
        );

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

sub startup_script {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $r;

    my $dl_site = $conf->{'toaster_dl_site'}   || "http://www.tnpi.net";
    my $confdir = $conf->{'system_config_dir'} || "/usr/local/etc";
    my $dl_url = "$dl_site/internet/mail/toaster";
    my $start  = "$confdir/rc.d/services.sh";

    # make sure the service dir is set up
    unless ( $toaster->service_dir_test( conf => $conf, debug => $debug ) ) {
        print
"FATAL: the service directories don't appear to be set up. I refuse to configure them to start up until this is fixed.\n";
        return 0;
    }

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

# how we configure each startup file depends on what platform we're operating on

    if ( $OSNAME eq "freebsd" ) {

        # The FreeBSD port for daemontools includes rc.d/svscan.sh so we use it
        $start = "$confdir/rc.d/svscan.sh";
        unless ( -f $start ) {
            print
"WARNING: no svscan.sh, is daemontools installed and up-to-date?\n";
            print "\n\nInstalling a generic startup file....";

            $utility->file_get( url => "$dl_url/start/services.txt", debug=>$debug );
            $r = $utility->install_if_changed(
                newfile  => "services.txt",
                existing => $start,
                mode     => '0751',
                clean    => 1,
                debug    => $debug,
            );

            return 0 unless $r;
            $r == 1 ? $r = "ok" : $r = "ok (current)";

            $utility->_formatted( "startup_script: updating $start", $r );
        }

        $freebsd->rc_dot_conf_check(
            check => "svscan_enable",
            line  => 'svscan_enable="YES"',
            debug => $debug,
        );

        # if the qmail start file is installed, nuke it
        if ( -e "$confdir/rc.d/qmail.sh" ) {
            unlink("$confdir/rc.d/qmail.sh")
              or croak "couldn't delete $confdir/rc.d/qmail.sh: $!";
            print "startup_script: removing $confdir/rc.d/qmail.sh\n";
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        $start = "/Library/LaunchDaemons/to.yp.cr.daemontools-svscan.plist";
        unless ( -e $start ) {
            $utility->file_get(
                url => "$dl_url/start/to.yp.cr.daemontools-svscan.plist" );
            $r = $utility->install_if_changed(
                newfile  => "to.yp.cr.daemontools-svscan.plist",
                existing => $start,
                mode     => '0551',
                clean    => 1,
                debug    => $debug,
            );
            return 0 unless $r;
            $r == 1
              ? $r = "ok"
              : $r = "ok (current)";
            $utility->_formatted( "startup_script: updating $start", $r );
        }

        my $prefix = $conf->{'toaster_prefix'} || "/usr/local";
        $start = "$prefix/sbin/services";

        if ( -w $start ) {
            $utility->file_get( url => "$dl_url/start/services-darwin.txt" );

            $r = $utility->install_if_changed(
                newfile  => "services-darwin.txt",
                existing => $start,
                mode     => '0551',
                clean    => 1,
                debug    => $debug,
            );

            return 0 unless $r;
            $r == 1
              ? $r = "ok"
              : $r = "ok (current)";

            $utility->_formatted( "startup_script: updating $start", $r );
        }
    }
    else {
        print
"SORRY: I don't know how to set up the startup script on $OSNAME. If you know the proper method of doing so, please have a look at $dl_url/start/services.txt and adapt it to $OSNAME and send it to matt\@tnpi.net.\n";
    }

    my $sym = "/usr/local/sbin/services";
    if ( $OSNAME eq "freebsd" ) {

        # already exists
        return 1 if ( -l $sym && -x $sym );

        if ( -e $sym ) {
            unlink $sym
              or carp "couldn't remove existing $sym."
              . " please [re]move it and run this again!\n";
            return 0;
        }

        print "startup_script: adding $sym...";
        symlink( $start, $sym );
        -e $sym
          ? print "done.\n"
          : print "FAILED.\n";
    }
}

sub test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my @tests;

    print "testing...\n";

    $self->test_qmail(  debug=>$debug );
    $self->daemontools_test( debug=>$debug);
    $self->ucspi_test(  debug=>$debug );

    require Mail::Toaster::Qmail;

    print "does supervise directory exist?\n";
    my $q_sup = $conf->{'qmail_supervise'} || "/var/qmail/supervise";
    -d $q_sup
      ? $utility->_formatted( "\t$q_sup", "ok" )
      : $utility->_formatted( "\t$q_sup", "FAILED" );

    # check each supervised directory
    foreach (qw/smtp send pop3 submit/) {
        $toaster->supervised_dir_test( conf => $conf, prot => $_, debug=>$debug )
          ? $utility->_formatted( "\t$q_sup/$_", "ok" )
          : $utility->_formatted( "\t$q_sup/$_", "FAILED" );
    }

    print "do service directories exist?\n";
    my $q_ser = $conf->{'qmail_service'};

    require Mail::Toaster::Qmail;
    my $qmail = Mail::Toaster::Qmail->new();

    foreach (
        (
            $q_ser,
            $qmail->service_dir_get( conf => $conf, prot => "smtp", debug=>$debug ),
            $qmail->service_dir_get( conf => $conf, prot => "send", debug=>$debug ),
            $qmail->service_dir_get( conf => $conf, prot => "pop3", debug=>$debug ),
            $qmail->service_dir_get( conf => $conf, prot => "submit", debug=>$debug ),
        )
      )
    {
        -d $_
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "are the supervised services running?\n";
    my $svok = $utility->find_the_bin( bin => "svok", fatal => 0 );
    foreach (
        $qmail->service_dir_get( conf => $conf, prot => "smtp", debug=>$debug ),
        $qmail->service_dir_get( conf => $conf, prot => "send", debug=>$debug ),
        $qmail->service_dir_get( conf => $conf, prot => "pop3", debug=>$debug ),
        $qmail->service_dir_get( conf => $conf, prot => "submit", debug=>$debug ),
      )
    {
        $utility->syscmd( command => "$svok $_", debug=>$debug )
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    $self->test_logging( debug=>$debug );
    $self->vpopmail_test( debug=>$debug );

    $toaster->test_processes( conf=>$conf, debug=>$debug );

    if (
        !$utility->yes_or_no(
            question => "skip the network listener tests?",
            timeout  => 10,
        )
      )
    {

        my $netstat = $utility->find_the_bin( bin => "netstat", fatal => 0 );
        goto NETSTAT_DONE unless -x $netstat;

        if ( $OSNAME eq "freebsd" ) { $netstat .= " -aS " }
        if ( $OSNAME eq "darwin" )  { $netstat .= " -a " }
        if ( $OSNAME eq "linux" )   { $netstat .= " -an " }
        else { $netstat .= " -a " }
        ;    # should be pretty safe

        print "checking for listening tcp ports\n";
        foreach (qw( smtp http pop3 imap https submission pop3s imaps )) {
            `$netstat | grep $_ | grep -i listen`
              ? $utility->_formatted( "\t$_", "ok" )
              : $utility->_formatted( "\t$_", "FAILED" );
        }

        print "checking for udp listeners\n";
        foreach (qw( snmp )) {
            `$netstat | grep $_`
              ? $utility->_formatted( "\t$_", "ok" )
              : $utility->_formatted( "\t$_", "FAILED" );
        }
      NETSTAT_DONE:
    }

    $self->test_crons( debug=>$debug );
    $self->rrdutil_test( debug=>$debug );
    $qmail->check_rcpthosts();

    if (
        !$utility->yes_or_no(
            question => "skip the mail scanner tests?",
            timeout  => 10,
        )
      )
    {
        $self->filtering_test(  );
    }

    if (
        !$utility->yes_or_no(
            question => "skip the authentication tests?",
            timeout  => 10,
        )
      )
    {
        $self->test_auth( debug=>$debug );
    }

    # there's plenty more room here for more tests.

    # test DNS!
    # make sure primary IP is not reserved IP space
    # test reverse address for this machines IP
    # test resulting hostname and make sure it matches
    # make sure server's domain name has NS records
    # test MX records for server name
    # test for SPF records for server name

    # test for low disk space on /, qmail, and vpopmail partitions

    print "\ntesting complete.\n";
}

sub test_auth {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $email = $conf->{'toaster_test_email'};
    my $pass  = $conf->{'toaster_test_email_pass'};

    my $domain = ( split( '@', $email ) )[1];
    print "test_auth: testing domain is: $domain.\n";

    my $qmail_dir = $conf->{'qmail_dir'};
    my $grep      = $utility->find_the_bin( bin => "grep", debug=>$debug );

    unless ( -e "$qmail_dir/users/assign"
        && `$grep $domain $qmail_dir/users/assign` )
    {
        print "domain $domain is not set up.\n";
        unless (
            $utility->yes_or_no(
                question => "shall I add it for you?",
                timeout  => 30,
            )
          )
        {
            return 0;
        }

        my $vpdir = $conf->{'vpopmail_home_dir'};
        $utility->syscmd( command => "$vpdir/bin/vadddomain $domain $pass", debug=>$debug );
        $utility->syscmd( command => "$vpdir/bin/vadduser $email $pass", debug=>$debug );
    }

    if (   !-e "$qmail_dir/users/assign"
        or !`$grep $domain $qmail_dir/users/assign` )
    {
        return 0;
    }

    if ( $OSNAME eq "freebsd" ) {
        $freebsd->port_install( port => "p5-Mail-POP3Client", base => "mail", debug=>$debug );
        $freebsd->port_install( port => "p5-Mail-IMAPClient", base => "mail", debug=>$debug );
        $freebsd->port_install(
            port => "p5-IO-Socket-SSL",
            base => "security", 
            debug=> $debug,
        );
    }

    $self->imap_test_auth( );    # test imap auth
    $self->pop3_test_auth( );    # test pop3 auth
    $self->smtp_test_auth( );    # test smtp auth

    print
"\n\nNOTICE: It is normal for some of the tests to fail. This test suite is useful for any mail server, not just a Mail::Toaster. \n\n";

    # webmail auth
    # other ?
}

sub test_crons {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my @crons = (
        "/usr/local/vpopmail/bin/clearopensmtp",
        "/usr/local/sbin/toaster-watcher.pl",
    );

    push @crons, "/usr/local/share/sqwebmail/cleancache.pl"
      if $conf->{'install_sqwebmail'};
    push @crons, "/usr/local/www/cgi-bin/rrdutil.cgi -a update"
      if $conf->{'install_rrdutil'};

    print "checking cron processes\n";

    foreach (@crons) {
        $utility->syscmd( command => $_, debug=>$debug )
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }
}

sub test_dns {

    print <<'EODNS'
People forget to even have DNS setup on their Toaster, as Matt has said before. If someone forgot to configure DNS, chances are, little or nothing will work -- from port fetching to timely mail delivery.

How about adding a simple DNS check to the Toaster Setup test suite? And in the meantime, you could give some sort of crude benchmark, depending on the circumstances of the test data.  I am not looking for something too hefty, but something small and sturdy to make sure there is a good DNS server around answering queries reasonably fast.

Here is a sample of some DNS lookups you could perform.  What I would envision is that there were around 20 to 100 forward and reverse lookups, and that the lookups were timed.  I guess you could look them up in parallel, and wait a maximum of around 15 seconds for all of the replies.  The interesting thing about a lot of reverse lookups is that they often fail because no one has published them.

Iteration 1: lookup A records.
Iteration 2: lookup NS records.
Iteration 3: lookup MX records.
Iteration 4: lookup TXT records.
Iteration 5: Repeat step 1, observe the faster response time due to caching.

Here's a sample output!  Wow.

#toaster_setup.pl -s dnstest
Would you like to enter a local domain so I can test it in detail?
testmydomain-local.net
Would you like to test domains with underscores in them? (y/n)n
Testing /etc/rc.conf for a hostname= line...
This box is known as smtp.testmydomain-local.net
Verifying /etc/hosts exists ... Okay
Verifying /etc/host.conf exists ... Okay
Verifying /etc/nsswitch.conf exists ... Okay
Doing reverse lookups in in-addr.arpa using default name service....
Doing forward A lookups using default name service....
Doing forward NS lookups using default name service....
Doing forward MX lookups using default name service....
Doing forward TXT lookups using default name service....
Results:
[Any errors, like...]
Listing Reverses Not found:
10.120.187.45 (normal)
169.254.89.123 (normal)
Listing A Records Not found:
example.impossible.nonexistent.bogus.co.nl (normal)
Listing TXT Records Not found:
Attempting to lookup the same A records again....  Hmmm. much faster!
Your DNS Server (or its forwarder) seems to be caching responses. (Good)

Checking local domain known as testmydomain-local.net
Checking to see if I can query the testmydomain-local.net NS servers and retrieve the entire DNS record...
ns1.testmydomain-local.net....yes.
ns256.backup-dns.com....yes.
ns13.ns-ns-ns.net...no.
Do DNS records agree on all DNS servers?  Yes. identical.
Skipping SOA match.

I have discovered that testmydomain-local.net has no MX records.  Shame on you, this is a mail server!  Please fix this issue and try again.

I have discovered that testmydomain-local.net has no TXT records.  You may need to consider an SPF v1 TXT record.

Here is a dump of your domain records I dug up for you:
xoxoxoxox

Does hostname agree with DNS?  Yes. (good).

Is this machine a CNAME for something else in DNS?  No.

Does this machine have any A records in DNS?  Yes.
smtp.testmydomain-local.net is 192.168.41.19.  This is a private IP.

Round-Robin A Records in DNS pointing to another machine/interface?
No.

Does this machine have any CNAME records in DNS?  Yes. aka
box1.testmydomain-local.net
pop.testmydomain-local.net
webmail.testmydomain-local.net

***************DNS Test Output complete

Sample Forwards:
The first few may be cached, and the last one should fail.  Some will have no MX server, some will have many.  (The second to last entry has an interesting mail exchanger and priority.)  Many of these will (hopefully) not be found in even a good sized DNS cache.

I have purposely listed a few more obscure entries to try to get the DNS server to do a full lookup.
localhost
<vpopmail_default_domain if set>
www.google.com
yahoo.com
nasa.gov
sony.co.jp
ctr.columbia.edu
time.nrc.ca
distancelearning.org
www.vatican.va
klipsch.com
simerson.net
warhammer.mcc.virginia.edu
example.net
foo.com
example.impossible.nonexistent.bogus.co.nl

[need some obscure ones that are probably always around, plus some non-US sample domains.]

Sample Reverses:
Most of these should be pretty much static.  Border routers, nics and such.  I was looking for a good range of IP's from different continents and providers.  Help needed in some networks.  I didn't try to include many that don't have a published reverse name, but many examples exist in case you want to purposely have some.
127.0.0.1
224.0.0.1
198.32.200.50	(the big daddy?!)
209.197.64.1
4.2.49.2
38.117.144.45
64.8.194.3
72.9.240.9
128.143.3.7
192.228.79.201
192.43.244.18
193.0.0.193
194.85.119.131
195.250.64.90
198.32.187.73
198.41.3.54
198.32.200.157
198.41.0.4
198.32.187.58
198.32.200.148
200.23.179.1
202.11.16.169
202.12.27.33
204.70.25.234
207.132.116.7
212.26.18.3
10.120.187.45
169.254.89.123

[Looking to fill in some of the 12s, 50s and 209s better.  Remove some 198s]

Just a little project.  I'm not sure how I could code it, but it is a little snippet I have been thinking about.  I figure that if you write the code once, it would be quite a handy little feature to try on a server you are new to.

Billy

EODNS
      ;
}

sub test_logging {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    print "do the logging directories exist?\n";
    my $q_log = $conf->{'qmail_log_base'};
    foreach ( "", "pop3", "send", "smtp", "submit" ) {

        -d "$q_log/$_"
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "checking log files?\n";
    foreach (
        "clean.log",    "maildrop.log",   "watcher.log", "send/current",
        "smtp/current", "submit/current", "pop3/current",
      )
    {
        -f "$q_log/$_"
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }
}

sub test_qmail {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $qdir = $conf->{'qmail_dir'};
    print "does qmail's home directory exist?\n";
    -d $qdir
      ? $utility->_formatted( "\t$qdir", "ok" )
      : $utility->_formatted( "\t$qdir", "FAILED" );

    print "checking qmail directory contents\n";
    my @tests = qw(alias boot control man users bin doc queue);
    push @tests, "configure" if ( $OSNAME eq "freebsd" );    # added by the port
    foreach (@tests) {
        -d "$qdir/$_"
          ? $utility->_formatted( "\t$qdir/$_", "ok" )
          : $utility->_formatted( "\t$qdir/$_", "FAILED" );
    }

    print "is the qmail rc file executable?\n";
    -x "$qdir/rc"
      ? $utility->_formatted( "\t$qdir/rc", "ok" )
      : $utility->_formatted( "\t$qdir/rc", "FAILED" );

    require Mail::Toaster::Passwd;
    my $passwd = Mail::Toaster::Passwd->new();

    print "do the qmail users exist?\n";
    foreach (
        $conf->{'qmail_user_alias'},  $conf->{'qmail_user_daemon'},
        $conf->{'qmail_user_passwd'}, $conf->{'qmail_user_queue'},
        $conf->{'qmail_user_remote'}, $conf->{'qmail_user_send'},
      )
    {
        $passwd->exist($_)
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "do the qmail groups exist?\n";
    foreach ( $conf->{'qmail_group'}, $conf->{'qmail_log_group'} ) {

        getgrnam($_)
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "do the qmail alias files have contents?\n";
    my $q_alias = "$qdir/alias";
    foreach (
        (
            "$q_alias/.qmail-postmaster", "$q_alias/.qmail-root",
            "$q_alias/.qmail-mailer-daemon",
        )
      )
    {
        -s $_
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }
}

sub ucspi_tcp {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # pre-declarations. We configure these for each platform and use them
    # at the end to build ucspi_tcp from source.

    my ($patches);
    my @targets = ( 'make', 'make setup check' );

    if ( $conf->{'install_mysql'} ) {

        # we want MySQL support, so make sure MySQL is present
        $patches = ["ucspi-tcp-0.88-mysql+rss.patch"];
    }

    if ( $OSNAME eq "freebsd" ) {

       # we install it from ports first so that it is registered in the ports
       # database. Otherwise, installing other ports in the future may overwrite
       # our customized version. (don't forget to install pkgtools.conf from
       # the contrib directory to prevent the port from being upgraded!

        unless ( $freebsd->is_port_installed( port => "ucspi-tcp", debug=>$debug ) ) {
            $freebsd->port_install(
                port  => "ucspi-tcp",
                base  => "sysutils",
                flags => "BATCH=yes WITH_RSS_DIFF=1",
                debug => $debug,
            );

            # if that didn't work..
            $freebsd->port_install(
                port  => "ucspi-tcp",
                base  => "sysutils",
                flags => "BATCH=yes",
                debug => $debug,
            );
        }
    }
    elsif ( $OSNAME eq "darwin" ) {

        @targets = "echo '/opt/local' > conf-home";

        #		$vals->{'patches'} = ["ucspi-tcp-0.88-mysql+rss-darwin.patch"];

        if ( $conf->{'install_mysql'} ) {
            my $mysql_prefix = "/opt/local";
            if ( !-d "$mysql_prefix/include/mysql" ) {
                if ( -d "/usr/include/mysql" ) {
                    $mysql_prefix = "/usr";
                }
            }
            push @targets,
"echo 'gcc -s -I$mysql_prefix/include/mysql -L$mysql_prefix/lib/mysql -lmysqlclient' > conf-ld";
            push @targets,
              "echo 'gcc -O2 -I$mysql_prefix/include/mysql' > conf-cc";
        }

        push @targets, "make";
        push @targets, "make setup";
    }
    elsif ( $OSNAME eq "linux" ) {
        @targets = (
            "echo gcc -O2 -include /usr/include/errno.h > conf-cc",
            "make", "make setup check"
        );

#		Need to test MySQL patch on linux before enabling it.
#		$vals->{'patches'}    = ('ucspi-tcp-0.88-mysql+rss.patch', 'ucspi-tcp-0.88.errno.patch');
#		$vals->{'patch_args'} = "-p0";
    }

    # see if it is installed
    my $tcpserver = $utility->find_the_bin( bin => "tcpserver", fatal => 0, debug=>0 );
    if ( -x $tcpserver ) {
        if ( !$conf->{'install_mysql'} ) {

            # done if we don't need mysql
            $utility->_formatted( "ucspi-tcp: already installed",
                "ok (exists)" );
            return 2;
        }
        my $strings = $utility->find_the_bin( bin => "strings", debug=>0 );
        if ( grep( /sql/, `$strings $tcpserver` ) )
        {    # check if mysql libs are present
            $utility->_formatted(
                "ucspi-tcp: mysql support is already installed",
                "ok (exists)" );
            return 1;
        }
        print "ucspi-tcp is installed but w/o mysql support\n" .
            "compiling from sources.\n";
    }

    # save having to download it again
    if ( -e "/usr/ports/distfiles/ucspi-tcp-0.88.tar.gz" ) {
        copy(
            "/usr/ports/distfiles/ucspi-tcp-0.88.tar.gz",
            "/usr/local/src/ucspi-tcp-0.88.tar.gz"
        );
    }

    $utility->install_from_source(
        conf    => $conf,
        package => "ucspi-tcp-0.88",
        patches => $patches,
        site    => 'http://cr.yp.to',
        url     => '/ucspi-tcp',
        targets => \@targets,
        debug   => $debug,
    );

    print "should be all done!\n";
    -x $utility->find_the_bin( bin => "tcpserver", fatal => 0, debug => 0 )
      ? return 1
      : return 0;

    #	my $file = "db.c";
    #	my @lines = $utility->file_read( file=>$file );
    #	foreach my $line (@lines) { #
    #		if ( $line =~ /^#include <unistd.h>/ ) { #
    #			$line = '#include <sys/unistd.h>';
    #		};
    #	};
    #	$utility->file_write( file=>$file, lines=>\@lines );
}

sub ucspi_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, { 
            'debug' => { type=>BOOLEAN, optional=>1, default=>$debug },
        }, 
    );

    $debug = $p{'debug'};

    print "checking ucspi-tcp binaries...\n";
    foreach (qw( tcprules tcpserver rblsmtpd tcpclient recordio )) {
        -x $utility->find_the_bin( bin => $_, fatal => 0, debug=>$debug )
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    my $tcpserver = $utility->find_the_bin( bin => "tcpserver", fatal => 0, debug=>$debug );

    if ( $conf->{'install_mysql'} ) {
        if (`strings $tcpserver | grep sql`) {
            $utility->_formatted( "\ttcpserver mysql support", "ok" );
        }
        else {
            $utility->_formatted( "\ttcpserver mysql support", "FAILED" );
            return 0;
        }
    }

    return 1;
}

sub vpopmail {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( !$conf->{'install_vpopmail'} ) {
        $utility->_formatted( "vpopmail: installing", "skipping (disabled)" )
          if $debug;
        print "\tVpopmail installation not selected! Utterly strange. You have to be joking?\n"
          if $debug;
        return;
    }

    my ( $ans, $ddom, $ddb, $cflags, $my_write, $conf_args );

    my $version = $conf->{'install_vpopmail'} || "5.4.13";

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) 
    {
        if ( !$freebsd->is_port_installed( port => "vpopmail", debug=>$debug ) ) 
        {
            # we install the port version regardless of whether it is selected.
            # This is because later apps (like courier) that we want to install
            # from ports require it to be registered in the ports db

            $self->vpopmail_install_freebsd_port();
        };

        my $installed = $freebsd->is_port_installed( port=>"vpopmail", debug=>$debug);
        if ( $installed) 
        {
             $utility->_formatted("install vpopmail ($version)", "ok ($installed)");
        };

        return 1 if $version eq "port";
    };

    my $package = "vpopmail-$version";

    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $vpuser  = $conf->{'vpopmail_user'}     || "vpopmail";
    my $vpgroup = $conf->{'vpopmail_group'}    || "vchkpw";

    # add the vpopmail user/group if missing
    $self->vpopmail_user( );

    my $uid = getpwnam($vpuser);
    my $gid = getgrnam($vpgroup);

    # check installed version
    if ( !-x "$vpopdir/bin/vpasswd" ) {
        print "vpopmail is not installed yet.\n";
    }
    else {
        $perl->module_load( module => "vpopmail", debug=>$debug, auto=>1)
          if $conf->{'install_ezmlm_cgi'};
        my $installed = `$vpopdir/bin/vpasswd -v | head -1 | cut -f2 -d" "`;
        chop $installed;
        print "vpopmail version $installed currently installed.\n";
        if ( $installed eq $version ) {
            if ( ! $utility->yes_or_no(
                question =>
                  "Do you want to reinstall vpopmail with the same version?",
                timeout => 60,
              )
            ) {
                $self->vpopmail_etc();
                $self->vpopmail_mysql_privs();
                return 1;
            }
        }
    }

    my $mysql = $self->vpopmail_use_mysql($version);
    $conf_args = $mysql if $mysql;

    if ( !defined $conf->{'vpopmail_rebuild_tcpserver_file'}
        || $conf->{'vpopmail_rebuild_tcpserver_file'} == 1 )
    {
        $conf_args .= " --enable-rebuild-tcpserver-file=n";
        print "rebuild tcpserver file: no\n";
    }

    if ( defined $conf->{'vpopmail_ip_alias_domains'} ) {
        $conf_args .= " --enable-ip-alias-domains=y";
    }

    if ( ! $self->is_newer( min => "5.3.30", cur => $version ) ) {
        if ( defined $conf->{'vpopmail_default_quota'} ) {
            $conf_args .=
              " --enable-defaultquota=$conf->{'vpopmail_default_quota'}";
            print "default quota: $conf->{'vpopmail_default_quota'}\n";
        }
        else {
            $conf_args .= " --enable-defaultquota=100000000S,10000C";
            print "default quota: 100000000S,10000C\n";
        }
    }

    $conf_args .= $self->vpopmail_roaming_users();

    if ( $OSNAME eq "darwin" && !-d "/usr/local/mysql"
        && -d "/opt/local/include/mysql" )
    {
        $conf_args .= " --enable-incdir=/opt/local/include/mysql";
        $conf_args .= " --enable-libdir=/opt/local/lib/mysql";
    }

    my $tcprules = $utility->find_the_bin( bin => "tcprules", debug=>0 );
    $conf_args .= " --enable-tcprules-prog=$tcprules";

    my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";

    $utility->chdir_source_dir( dir => "$src/mail", debug=>$debug );

    my $tarball = "$package.tar.gz";

    $utility->sources_get(
        conf    => $conf,
        package => $package,
        site    => "http://" . $conf->{'toaster_sf_mirror'},
        url     => "/vpopmail",
        debug   => $debug
    );

    if ( -d $package ) {
        if ( !$utility->source_warning(
                package => $package,
                src     => "$src/mail",
            ) )
        {
            carp "vpopmail: OK then, skipping install.\n";
            return;
        }
    }

    if ( !$utility->archive_expand( archive => $tarball, debug => $debug ) )
    {
        croak "Couldn't expand $tarball!\n";
    }

    $conf_args .= $self->vpopmail_learn_passwords();
    $conf_args .= $self->vpopmail_logging();
    $conf_args .= $self->vpopmail_default_domain($version);
    $conf_args .= $self->vpopmail_etc_passwd();

    unless ( defined $conf->{'vpopmail_valias'} ) {
        if ( $utility->yes_or_no(
                question => "Do you use valias processing? (n) "
            ))
        {
            $conf_args .= " --enable-valias=y";
            print "valias processing: yes\n";
        }
    }
    else {
        if ( $conf->{'vpopmail_valias'} ) {
            $conf_args .= " --enable-valias=y";
            print "valias processing: yes\n";
        }
    }

    unless ( defined $conf->{'vpopmail_mysql_logging'} ) {
        if ( $utility->yes_or_no(
                question => "Do you want mysql logging? (n) "
            ))
        {
            $conf_args .= " --enable-mysql-logging=y";
            print "mysql logging: yes\n";
        }
    }
    else {
        if ( $conf->{'vpopmail_mysql_logging'} ) {
            $conf_args .= " --enable-mysql-logging=y";
            print "mysql logging: yes\n";
        }
    }

    unless ( defined $conf->{'vpopmail_qmail_extensions'} ) {
        if (
            $utility->yes_or_no(
                question => "Do you want qmail extensions? (n) "
            )
          )
        {
            $conf_args .= " --enable-qmail-ext=y";
            print "qmail extensions: yes\n";
        }
    }
    else {
        if ( $conf->{'vpopmail_qmail_extensions'} ) {
            $conf_args .= " --enable-qmail-ext=y";
            print "qmail extensions: yes\n";
        }
    }

    chdir($package);

    $conf_args .= $self->vpopmail_mysql_options() if $mysql; 
    $conf_args .= $self->vpopmail_domain_quotas();

#    chdir($package);
    print "running configure with $conf_args\n\n";

    $utility->syscmd( command => "./configure $conf_args", debug => 0 );
    $utility->syscmd( command => "make",                   debug => 0 );
    $utility->syscmd( command => "make install-strip",     debug => 0 );

    if ( -e "vlimits.h" ) {
        # this was needed due to a bug in vpopmail 5.4.?(1-2) installer
        $utility->syscmd(
            command => "cp vlimits.h $vpopdir/include/",
            debug   => 0
        );
    }

    $self->vpopmail_etc( );
    $self->vpopmail_mysql_privs( );

    if ( $conf->{'install_ezmlm_cgi'} ) {
        $perl->module_load( 
            module     => "vpopmail", 
            port_name  => "p5-vpopmail", 
            port_group => "mail",
            debug      => $debug,
            auto       => 1,
        );
    }

    print "vpopmail: complete.\n";
    return 1;
}

sub vpopmail_default_domain {
    my $self = shift;
    my $version = shift;

    my $conf = $self->{'conf'};

    my $default_domain;

    if ( defined $conf->{'vpopmail_default_domain'} ) 
    {
        $default_domain = $conf->{'vpopmail_default_domain'};
    } 
    else {
        if ( ! $utility->yes_or_no(
                question => "Do you want to use a default domain? ", 
            ) )
        {
            print "default domain: NONE SELECTED.\n";
            return q{};
        };

        $default_domain = $utility->answer(q=>"your default domain");
    };

    if ( ! $default_domain ) 
    {
        print "default domain: NONE SELECTED.\n";
        return q{};
    };

    if ( $self->is_newer( min => "5.3.22", cur => $version ) ) {
        my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
        $utility->file_write(
            file  => "$vpopdir/etc/defaultdomain",
            lines => [ $default_domain ],
            debug => 0,
        );

        $utility->file_chown(
            file => "$vpopdir/etc/defaultdomain",
            uid  => $conf->{'vpopmail_user'}  || "vpopmail",
            gid  => $conf->{'vpopmail_group'} || "vchkpw",
            debug => 0,
        );

        return q{};
    }

    print "default domain: $default_domain\n";
    return " --enable-default-domain=$default_domain";
};

sub vpopmail_domain_quotas {
    my $self = shift;
    my $conf = $self->{'conf'};

    # do not ever do this, regardless of what the user selects!
    # domain quotas are badly broken in vpopmail.

    if ( defined $conf->{'vpopmail_domain_quotas'} ) {
        if ( $conf->{'vpopmail_domain_quotas'} ) {
            print "domain quotas: no (OVERRIDDEN!)\n";
            return q{};
            #return " --enable-domainquotas=y";
        }
        print "domain quotas: no\n";
        return q{};
    };

    if ( $utility->yes_or_no(
            question => "Do you want vpopmail's domain quotas? (n) "
        ))
    {
        print "domain quotas: no (OVERRIDDEN!)\n";
        return q{};
        #return " --enable-domainquotas=y";
    }
    return q{};
};

sub vpopmail_etc {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my @lines;

    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $vetc    = "$vpopdir/etc";
    my $qdir    = $conf->{'qmail_dir'};

    mkdir( $vpopdir, oct('0775') ) unless ( -d $vpopdir );

    if ( -d $vetc ) { print "$vetc already exists.\n"; }
    else {
        print "creating $vetc\n";
        mkdir( $vetc, oct('0775') ) or carp "failed to create $vetc: $!\n";
    }

    $self->vpopmail_install_default_tcp_smtp( etc_dir => $vetc );

    my $qmail_control = "$qdir/bin/qmailctl";
    if ( -x $qmail_control ) {
        print " vpopmail_etc: rebuilding tcp.smtp.cdb\n";
        $utility->syscmd( command => "$qmail_control cdb", debug => 0 );
    }
}

sub vpopmail_etc_passwd {
    my $self = shift;
    my $conf = $self->{'conf'};

    unless ( defined $conf->{'vpopmail_etc_passwd'} ) {
        print "\t\t CAUTION!!  CAUTION!!

    The system user account feature is NOT compatible with qmail-smtpd-chkusr.
    If you selected that option in the qmail build, you should not answer
    yes here. If you are unsure, select (n).\n";

        if (
            $utility->yes_or_no(
                question => "Do system users (/etc/passwd) get mail? (n) "
            )
          )
        {
            print "system password accounts: yes\n";
            return " --enable-passwd";
        }
    }

    if ( $conf->{'vpopmail_etc_passwd'} ) {
        print "system password accounts: yes\n";
        return " --enable-passwd";
    }

    print "system password accounts: no\n";
};

sub vpopmail_install_freebsd_port {

    my $self = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $version = $conf->{'install_vpopmail'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    my @defs = "WITH_CLEAR_PASSWD=yes";
    push @defs, "WITH_LEARN_PASSWORDS=yes"
        if ( $conf->{'vpopmail_learn_passwords'} );
    push @defs, "WITH_MYSQL=yes";

    push @defs, "WITH_MYSQL_REPLICATION=yes"
        if ( $conf->{'vpopmail_mysql_replication'} );
    push @defs, "WITH_MYSQL_LIMITS=yes"
        if ( $conf->{'vpopmail_mysql_limits'} );
    push @defs, "WITH_IP_ALIAS=yes"
        if ( $conf->{'vpopmail_ip_alias_domains'} );
    push @defs, "WITH_QMAIL_EXT=yes"
        if ( $conf->{'vpopmail_qmail_extensions'} );
    push @defs, "WITH_DOMAIN_QUOTAS=yes"
        if ( $conf->{'vpopmail_domain_quotas'} );
    push @defs, "WITH_SINGLE_DOMAIN=yes"
        if ( $conf->{'vpopmail_disable_many_domains'} );

    push @defs,
        'WITH_MYSQL_SERVER="' . $conf->{'vpopmail_mysql_repl_master'} . '"';
    push @defs,
        'WITH_MYSQL_USER="' . $conf->{'vpopmail_mysql_repl_user'} . '"';
    push @defs,
        'WITH_MYSQL_PASSWD="' . $conf->{'vpopmail_mysql_repl_pass'} . '"';
    push @defs,
        'WITH_MYSQL_DB="' . $conf->{'vpopmail_mysql_database'} . '"';
    push @defs,
        'WITH_MYSQL_READ_SERVER="'
        . $conf->{'vpopmail_mysql_repl_slave'} . '"';

    push @defs, 'LOGLEVEL="p"';

    my $r = $freebsd->port_install(
        port  => "vpopmail",
        base  => "mail",
        flags => join( ",", @defs ),
        debug => $debug,
    );

    return unless $r;

    # add a symlink so docs are web browsable 
    my $vpopdir = $conf->{'vpopmail_home_dir'};
    my $docroot = $conf->{'toaster_http_docs'};

    unless ( -e "$docroot/vpopmail" ) {
        if ( -d "$vpopdir/doc/man_html" && -d $docroot ) {
            symlink "$vpopdir/doc/man_html", "$docroot/vpopmail";
        }
    }

    $freebsd->port_install( 
        port => "p5-vpopmail", 
        base => "mail", 
        debug => $debug, 
        fatal => 0,
    ); 

    if ($version eq "port") {
        $self->vpopmail_etc( );
        $self->vpopmail_mysql_privs( );
        return 1 
    };
}

sub vpopmail_install_default_tcp_smtp {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    my %p = validate( @_, {
            'etc_dir' => { type => SCALAR },
        },
    );

    my $etc_dir = $p{'etc_dir'};

    # test for an existing one
    if ( -f "$etc_dir/tcp.smtp" ) {
        my $count = $utility->file_read( file => "$etc_dir/tcp.smtp" );
        return if $count != 1;
        # back it up
        $utility->file_archive( file => "$etc_dir/tcp.smtp" );
    }

    my $qdir = $conf->{'qmail_dir'};

    my @lines = <<"EO_TCP_SMTP";
# RELAYCLIENT="" means IP can relay
# RBLSMTPD=""    means DNSBLs are ignored for this IP
# QMAILQUEUE=""  is the qmail queue process, defaults to $qdir/bin/qmail-queue
#
#    common QMAILQUEUE settings:
# QMAILQUEUE="$qdir/bin/qmail-queue"
# QMAILQUEUE="$qdir/bin/simscan"
# QMAILQUEUE="$qdir/bin/qmail-scanner-queue.pl"
# 
#      handy test settings
# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="$qdir/bin/simscan"
# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="$qdir/bin/qmail-scanner-queue.pl"
# 127.:allow,RELAYCLIENT="",RBLSMTPD="",QMAILQUEUE="$qdir/bin/qscanq/bin/qscanq"
127.0.0.1:allow,RELAYCLIENT="",RBLSMTPD=""

EO_TCP_SMTP
    my $block = 1;

    if ( $conf->{'vpopmail_enable_netblocks'} ) {

        if (
            $utility->yes_or_no(
                question =>
                  "Do you need to enable relay access for any netblocks? :

NOTE: If you are an ISP and have dialup pools, this is where you want
to enter those netblocks. If you have systems that should be able to 
relay through this host, enter their IP/netblocks here as well.\n\n"
            )
          )
        {
            do {
                $block =
                  $utility->answer(
                    q => "the netblock to add (empty to finish)" );
                push @lines, "$block:allow" if $block;
            } until ( !$block );
        }
    }

    #no Smart::Comments;
    push @lines, <<"EO_QMAIL_SCANNER";
### BEGIN QMAIL SCANNER VIRUS ENTRIES ###
### END QMAIL SCANNER VIRUS ENTRIES ###
#
# Allow anyone with reverse DNS set up
#=:allow
#    soft block on no reverse DNS
#:allow,RBLSMTPD="Blocked - Reverse DNS queries for your IP fail. Fix your DNS!"
#    hard block on no reverse DNS
#:allow,RBLSMTPD="-Blocked - Reverse DNS queries for your IP fail. You cannot send me mail."
#    default allow
#:allow,QMAILQUEUE="$qdir/bin/simscan"
:allow
EO_QMAIL_SCANNER

    $utility->file_write( file => "$etc_dir/tcp.smtp", lines => \@lines );
}

sub vpopmail_learn_passwords {

    my $self = shift;
    my $conf = $self->{'conf'};

    # if set, then we're done
    if ( defined $conf->{'vpopmail_learn_passwords'}
        && $conf->{'vpopmail_learn_passwords'} )
    {
        print "learning passwords yes\n";
        return " --enable-learn-passwords=y";
    }

    if ( $utility->yes_or_no(
            question => "Do you want password learning? (y) "
        ))
    {
        print "password learning: yes\n";
        return " --enable-learn-passwords=y";
    }
    print "password learning: no\n";
    return " --enable-learn-passwords=n";
}

sub vpopmail_logging {

    my $self = shift;
    my $conf = $self->{'conf'};

    if ( defined $conf->{'vpopmail_logging'} ) 
    {
        if ( $conf->{'vpopmail_logging'} ) 
        {
            if ( $conf->{'vpopmail_logging_verbose'} ) 
            {
                print "logging: verbose with failed passwords\n";
                return " --enable-logging=v";
            }

            print "logging: everything\n";
            return " --enable-logging=y";
        }
    }

    if ( ! $utility->yes_or_no(
            question => "Do you want logging enabled? (y) "
        ))
    {
        return " --enable-logging=p";
    };

    if ( $utility->yes_or_no(
            question => "Do you want verbose logging? (y) "
        ))
    {
        print "logging: verbose\n";
        return " --enable-logging=v";
    }

    print "logging: verbose with failed passwords\n";
    return " --enable-logging=p";
};

sub vpopmail_roaming_users {
    my $self = shift;
    my $conf = $self->{'conf'};

    my $roaming = $conf->{'vpopmail_roaming_users'};

    if ( defined $roaming && !$roaming ) {
        print "roaming users: no\n";
        return " --enable-roaming-users=n";
    }

    # default to enabled
    if ( !defined $conf->{'vpopmail_roaming_users'} ) {
        print "roaming users: value not set?!\n";
    }

    print "roaming users: yes\n";

    my $min = $conf->{'vpopmail_relay_clear_minutes'};
    if ( $min && $min ne 180 ) {
        print "roaming user minutes: $min\n";
        return " --enable-roaming-users=y" .
            " --enable-relay-clear-minutes=$min";
    };
    return " --enable-roaming-users=y";
};

sub vpopmail_test {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    print "do vpopmail directories exist...\n";
    my $vpdir = $conf->{'vpopmail_home_dir'};
    foreach (
        "$vpdir",      "$vpdir/bin",     "$vpdir/domains",
        "$vpdir/etc/", "$vpdir/include", "$vpdir/lib",
      )
    {
        -d $_
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "checking vpopmail binaries...\n";
    foreach (
        qw/
        clearopensmtp   vaddaliasdomain     vadddomain
        valias          vadduser            vchkpw
        vchangepw       vconvert            vdeldomain
        vdelivermail    vdeloldusers        vdeluser
        vdominfo        vipmap              vkill
        vmkpasswd       vmoddomlimits       vmoduser
        vpasswd         vpopbull            vqmaillocal
        vsetuserquota   vuserinfo   /
      )
    {

        -x "$vpdir/bin/$_"
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "do vpopmail libs exist...\n";
    foreach ("$vpdir/lib/libvpopmail.a") {

        -e $_
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "do vpopmail includes exist...\n";
    foreach (qw/ config.h vauth.h vlimits.h vpopmail.h vpopmail_config.h /) {

        -e "$vpdir/include/$_"
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }

    print "checking vpopmail etc files...\n";
    foreach (
        qw/   inc_deps lib_deps
        tcp.smtp tcp.smtp.cdb
        vlimits.default vpopmail.mysql /
      )
    {

        -e "$vpdir/etc/$_" && -s "$vpdir/etc/$_"
          ? $utility->_formatted( "\t$_", "ok" )
          : $utility->_formatted( "\t$_", "FAILED" );
    }
}

sub vpopmail_user {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";
    my $vpuser  = $conf->{'vpopmail_user'}     || "vpopmail";
    my $vpgroup = $conf->{'vpopmail_group'}    || "vchkpw";

    my $uid = getpwnam($vpuser);
    my $gid = getgrnam($vpgroup);

    if ( !$uid || !$gid ) {
        require Mail::Toaster::Passwd;
        my $passwd = Mail::Toaster::Passwd->new();

        $passwd->creategroup( $vpgroup, "89" );
        $passwd->user_add(
            { user => $vpuser, homedir => $vpopdir, uid => 89, gid => 89 } );
    }

    $uid = getpwnam($vpuser);
    $gid = getgrnam($vpgroup);

    if ( !$uid || !$gid ) {
        print "failed to add vpopmail user or group!\n";
        croak if $fatal;
        return 0;
    }

    return 1;
}

sub vpopmail_use_mysql {
    my $self    = shift;
    my $version = shift;
    my $conf = $self->{'conf'};

    # install vpopmail from sources
    if ( !defined $conf->{'vpopmail_mysql'} || $conf->{'vpopmail_mysql'} == 0 )
    {
        print "authentication module: cdb\n";
        return 0;
    };

    print "authentication module: mysql\n";

    return $self->is_newer( min => "5.3.30", cur => $version ) 
        ? "--enable-auth-module=mysql "
        : "--enable-mysql=y "; 
};

sub vpopmail_vmysql_h {

    my $self = shift;
    my $conf = $self->{'conf'};

    my ( $mysql_repl, 
        $my_write, $my_write_port,
        $my_read,  $my_read_port,
        $my_user, $my_pass, $debug ) = @_;

    my $vpopdir = $conf->{'vpopmail_home_dir'} || "/usr/local/vpopmail";

    copy( "vmysql.h", "vmysql.h.orig" );
    my @lines = $utility->file_read( file => "vmysql.h", debug=>$debug );

    foreach my $line (@lines) {
        chomp $line;
        if ( $line =~ /^#define MYSQL_UPDATE_SERVER/ ) {
            if ($mysql_repl) {
                $line = "#define MYSQL_UPDATE_SERVER \"$my_write\"";
            }
            else {
                $line = "#define MYSQL_UPDATE_SERVER \"$my_read\"";
            }
        }
        elsif ( $line =~ /^#define MYSQL_UPDATE_USER/ ) {
            $line = "#define MYSQL_UPDATE_USER   \"$my_user\"";
        }
        elsif ( $line =~ /^#define MYSQL_UPDATE_PASSWD/ ) {
            $line = "#define MYSQL_UPDATE_PASSWD \"$my_pass\"";
        }
        elsif ( $line =~ /^#define MYSQL_READ_SERVER/ ) {
            $line = "#define MYSQL_READ_SERVER   \"$my_read\"";
        }
        elsif ( $line =~ /^#define MYSQL_READ_USER/ ) {
            $line = "#define MYSQL_READ_USER     \"$my_user\"";
        }
        elsif ( $line =~ /^#define MYSQL_READ_PASSWD/ ) {
            $line = "#define MYSQL_READ_PASSWD   \"$my_pass\"";
        }
    }

    $utility->file_write( file => "vmysql.h", lines => \@lines, debug=>$debug );

    @lines = "$my_read|0|$my_user|$my_pass|vpopmail";
    if ($mysql_repl) {
        push @lines, "$my_write|$my_write_port|$my_user|$my_pass|vpopmail";
    }
    else {
        push @lines, "$my_read|$my_read_port|$my_user|$my_pass|vpopmail";
    }

    $utility->file_write(
        file  => "$vpopdir/etc/vpopmail.mysql",
        lines => \@lines, 
        debug => $debug,
    );
}

sub vpopmail_mysql_options {

    my $self = shift;
    my $conf = $self->{'conf'};

    my ( $mysql_repl, $my_write, $my_write_port, $my_read, $my_read_port,
         $my_user, $my_pass );

    my $opts;

    unless ( defined $conf->{'vpopmail_mysql_limits'} ) {
        print "Qmailadmin supports limits via a .qmailadmin-limits " .
            "file. It can also get these limits from a MySQL table. ";

        if ( $utility->yes_or_no(
                question => "Do you want mysql limits? (n) "
            ))
        {
            print "mysql qmailadmin limits: yes\n";
            $opts .= " --enable-mysql-limits=y";
        }
    }
    else {
        if ( $conf->{'vpopmail_mysql_limits'} ) {
            print "mysql qmailadmin limits: yes\n";
            $opts .= " --enable-mysql-limits=y";
        }
    }

    if ( defined $conf->{'vpopmail_mysql_replication'} ) {

        $my_read_port = $conf->{'vpopmail_mysql_repl_slave_port'};
        $my_read = $conf->{'vpopmail_mysql_repl_slave'};
        $my_user = $conf->{'vpopmail_mysql_repl_user'};
        $my_pass = $conf->{'vpopmail_mysql_repl_pass'};

        if ( $conf->{'vpopmail_mysql_replication'} ) {
            $opts .= " --enable-mysql-replication=y";
            $mysql_repl++;
            $my_write  = $conf->{'vpopmail_mysql_repl_master'};
            $my_write_port = $conf->{'vpopmail_mysql_repl_master_port'} || "3306";
            print "mysql replication: yes\n";
            print "      replication master: $my_write\n";
        }
        else {
            $mysql_repl = 0;
            print "mysql server: $my_read\n";
        }
    }
    else {
        $mysql_repl = $utility->yes_or_no(
            question => "Do you want mysql replication enabled? (n) " );

        if ($mysql_repl) {
            $opts .= " --enable-mysql-replication=y";
            $my_write = $utility->answer(
                q       => "your MySQL master servers hostname" );
            $my_read = $utility->answer(
                q       => "your MySQL read server hostname",
                default => "localhost"
            );
            $my_user = $utility->answer(
                q       => "your MySQL user name",
                default => "vpopmail"
            );
            $my_pass = $utility->answer( q => "your MySQL password" );
        }
    }

    if ( $conf->{'vpopmail_disable_many_domains'} ) {
        $opts .= " --disable-many-domains";
    }

    $self->vpopmail_vmysql_h( 
        $mysql_repl, 
        $my_write, $my_write_port, 
        $my_read, $my_read_port, 
        $my_user, $my_pass,
    );

    return $opts;
}

sub vpopmail_mysql_privs {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    if ( !$conf->{'vpopmail_mysql'} ) {
        print "vpopmail_mysql_privs: mysql support not selected!\n";
        return 0;
    }

    my $db   = $conf->{'vpopmail_mysql_database'};
    my $user = $conf->{'vpopmail_mysql_repl_user'};
    my $pass = $conf->{'vpopmail_mysql_repl_pass'};
    my $host = $conf->{'vpopmail_mysql_repl_slave'};

    require Mail::Toaster::Mysql;
    my $mysql = Mail::Toaster::Mysql->new();

    my $dot = $mysql->parse_dot_file( ".my.cnf", "[mysql]", 0 );

    my ( $dbh, $dsn, $drh ) = $mysql->connect( $dot, 1 );

    if ( !$dbh ) {
        print <<"EOMYSQLGRANT";

        WARNING: I couldn't connect to your database server!  If this is a new install, 
        you will need to connect to your database server and run this command manually:

        mysql -u root -h $host -p
        CREATE DATABASE vpopmail;
        GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass';
        use vpopmail;
        CREATE TABLE relay ( ip_addr char(18) NOT NULL default '',
          timestamp char(12) default NULL, name char(64) default NULL,
          PRIMARY KEY (ip_addr)) TYPE=ISAM PACK_KEYS=1;
        quit;

        If this is an upgrade and you already use MySQL authentication, 
        then you can safely ignore this warning.

EOMYSQLGRANT
        return 0;
    }

    my $query = "use vpopmail";
    my $sth = $mysql->query( $dbh, $query, 1 );
    if ( !$sth->errstr ) {
        $utility->_formatted( "vpopmail: databases created", "ok (exists)" );
        $sth->finish;
        return 1;
    }

    print "vpopmail: no vpopmail database, creating it now...\n";
    $query = "CREATE DATABASE vpopmail";
    $sth   = $mysql->query( $dbh, $query );

    print "vpopmail: granting privileges to $user\n";
    $query =
      "GRANT ALL PRIVILEGES ON $db.* TO $user\@'$host' IDENTIFIED BY '$pass'";
    $sth = $mysql->query( $dbh, $query );

    print "vpopmail: creating the relay table.\n";
    $query =
"CREATE TABLE vpopmail.relay ( ip_addr char(18) NOT NULL default '', timestamp char(12) default NULL, name char(64) default NULL, PRIMARY KEY (ip_addr)) TYPE=ISAM PACK_KEYS=1";
    $sth = $mysql->query( $dbh, $query );

    $utility->_formatted( "vpopmail: databases created", "ok" );
    $sth->finish;

    return 1;
}

sub vqadmin {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    unless ( $conf->{'install_vqadmin'} ) {
        $utility->_formatted( "vqadmin: installing", "skipping (disabled)" )
          if $debug;
        return 0;
    }

    my $cgi  = $conf->{'toaster_cgi_bin'}   || "/usr/local/www/cgi-bin";
    my $data = $conf->{'toaster_http_docs'} || "/usr/local/www/data";

    my @defs = 'CGIBINDIR="' . $cgi . '"';
    push @defs, 'WEBDATADIR="' . $data . '"';

    if ( defined $p{'test_ok'} ) { return $p{'test_ok'}; }

    if ( $OSNAME eq "freebsd" ) {
        return 1
          if $freebsd->port_install(
            port  => "vqadmin",
            base  => "mail",
            flags => join( ",", @defs ),
            debug => $debug,
          );
    }

    print "trying to build vqadmin from sources\n";

    $utility->install_from_source(
        conf           => $conf,
        package        => "vqadmin",
        site           => "http://vpopmail.sf.net",
        url            => "/downloads",
        targets        => [ "./configure ", "gmake", "gmake install-strip" ],
        source_sub_dir => 'mail',
        debug => $debug,
    );
}

sub webmail {

    my $self  = shift;
    my $conf  = $self->{'conf'};
    my $debug = $self->{'debug'};

    # parameter validation
    my %p = validate( @_, {
            'fatal' => { type => BOOLEAN, optional => 1, default => 1 },
            'debug' => { type => BOOLEAN, optional => 1, default => $debug },
            'test_ok' => { type => BOOLEAN, optional => 1, },
        },
    );

    my $fatal = $p{'fatal'};
       $debug = $p{'debug'};

    # if the cgi_files dir is not available, we can't do much.
    if ( ! -d "cgi_files" ) {
        require Cwd;
        carp "You need to run this target while in the Mail::Toaster directory!\n" 
            . "Try this instead:

   cd /usr/local/src/Mail-Toaster-x.xx
   script/toaster_setup.pl -s webmail

You are currently in " . Cwd::cwd;
        croak "error is fatal" if $fatal;
        return;
    };

    # set the hostname in mt-script.js
    my $hostname = $conf->{'toaster_hostname'};

    my @lines = $utility->file_read(file=>"cgi_files/mt-script.js");
    foreach my $line ( @lines ) {
        if ( $line =~ /\Avar mailhost / ) {
            $line = qq{var mailhost = 'https://$hostname'};
        };
    }
    $utility->file_write(
        file  => "cgi_files/mt-script.js", 
        lines => \@lines, 
        debug => $debug,
    );

    my $htdocs = $conf->{'toaster_http_docs'};
    my $rsync = $utility->find_the_bin(bin=>"rsync",fatal=>0,debug=>0);

    if ( ! $rsync || ! -x $rsync ) {
        $self->rsync( debug=>$debug, fatal=>$fatal );
    };

    $rsync = $utility->find_the_bin(bin=>"rsync", debug=>0);

    my $cmd = "$rsync -av ./cgi_files/ $htdocs/";
    print "about to run cmd: $cmd\n";

    print "\a";
    if ( $utility->yes_or_no( 
            timeout  => 60,
            question => "\n
          CAUTION! DANGER! CAUTION!

    This action will install the Mail::Toaster webmail interface. Doing
    so may overwrite existing files in $htdocs. Is is safe to proceed?\n\n",
          ) 
    ) 
    {
        return $utility->syscmd(cmd=>$cmd, debug=>$debug);
    };

    return 1;
};

1;
__END__;


=head1 NAME

Mail::Toaster::Setup -  methods to configure and build all the components of a modern email server.


=head1 DESCRIPTION

The meat and potatoes of toaster_setup.pl. This is where the majority of the work gets done. Big chunks of the code and logic for getting all the various applications and scripts installed and configured resides in here. 


=head1 METHODS

All documented methods in this package (shown below) accept two optional arguments, debug and fatal. Setting debug to zero will supress nearly all informational and debugging output. If you want more output, simply pass along debug=>1 and status messages will print out. Fatal allows you to override the default behaviour of these methods, which is to die upon error. Each sub returns 0 if the action failed and 1 for success.

 arguments required:
   varies (most require conf)
 
 arguments optional:
   debug - print status messages
   fatal - die on errors (default)

 result:
   0 - failure
   1 - success

 Examples:

   1. $setup->apache( debug=>0, fatal=>0 );
   Try to build apache, do not print status messages and do not die on error(s). 

   2. $setup->apache( debug=>1 );
   Try to build apache, print status messages, die on error(s). 

   3. if ( $setup->apache( ) { print "yay!\n" };
   Test to see if apache installed correctly.

=over

=item new

To use any methods in Mail::Toaster::Setup, you must create a setup object: 

  use Mail::Toaster::Setup;
  my $setup = Mail::Toaster::Setup->new;

From there you can run any of the following methods via $setup->method as documented below.

Many of the methods require $conf, which is a hashref containing the contents of toaster-watcher.conf. 


=item apache

Calls $apache->install[1|2] which then builds and installs Apache for you based on how it was called. See Mail::Toaster::Apache for more details.

  $setup->apache( ver=>22 );

There are many popular Apache compile time options supported. To see what options are available, see toaster-watcher.conf.

 required arguments:
   conf

 optional arguments:
   ver - the version number of Apache to install
   debug
   fatal


=item autorespond

Install autorespond. Fetches sources from Inter7 web site and installs. Automatically patches the sources to compile correctly on Darwin. 

  $setup->autorespond( );

 required arguments:
   conf

 optional arguments:
   debug
   fatal


=item clamav

Install ClamAV, configure the startup and config files, download the latest virus definitions, and start up the daemons.

  $setup->clamav( );

 required arguments:
   conf

 optional arguments:
   debug
   fatal


=item config - personalize your toaster-watcher.conf settings

There are a subset of the settings in toaster-watcher.conf which must be personalized for your server. Things like the hostname, where you store your configuration files, html documents, passwords, etc. This function checks to make sure these settings have been changed and prompts for any necessary changes.

 required arguments:
   conf

 optional arguments:
   debug
   fatal


=item config_tweaks

Makes changes to the config file, dynamically based on detected circumstances such as a jailed hostname, or OS platform. Platforms like FreeBSD, Darwin, and Debian have package management capabilities. Rather than installing software via sources, we prefer to try using the package manager first. The toaster-watcher.conf file typically includes the latest stable version of each application to install. This subroutine will replace those version numbers with with 'port', 'package', or other platform specific tweaks.


=item courier

  $setup->courier( );

Installs courier imap based on your settings in toaster-watcher.conf.

 required arguments:
   conf

 optional arguments:
   debug
   fatal

 result:
   1 - success
   0 - failure


=item courier_startup

  $setup->courier_startup( );

Does the post-install configuration of Courier IMAP.


=item cpan

  $setup->cpan( );

Installs only the perl modules that are required for 'make test' to succeed. Useful for CPAN testers.

 Date::Parse
 HTML::Template
 Compress::Zlib
 Crypt::PasswdMD5
 Net::DNS
 Quota
 TimeDate


=item cronolog

Installs cronolog. If running on FreeBSD or Darwin, it will install from ports. If the port install fails for any reason, or you are on another platform, it will install from sources. 

required arguments:
  conf

optional arguments:
  debug
  fatal

result:
  1 - success
  0 - failure


=item daemontools

Fetches sources from DJB's web site and installs daemontools, per his instructions.

 Usage:
  $setup->daemontools( conf->$conf );

 required arguments:
   conf

 optional arguments:
   debug
   fatal

 result:
   1 - success
   0 - failure


=item dependencies

  $setup->dependencies( );

Installs a bunch of dependency programs that are needed by other programs we will install later during the build of a Mail::Toaster. You can install these yourself if you would like, this does not do anything special beyond installing them:

ispell, gdbm, setquota, expect, maildrop, autorespond, qmail, qmailanalog, daemontools, openldap-client, Crypt::OpenSSL-RSA, DBI, DBD::mysql.

required arguments:
  conf

optional arguments:
  debug
  fatal

result:
  1 - success
  0 - failure


=item djbdns

Fetches djbdns, compiles and installs it.

  $setup->djbdns( );

 required arguments:
   conf

 optional arguments:
   debug
   fatal

 result:
   1 - success
   0 - failure


=item expect

Expect is a component used by courier-imap and sqwebmail to enable password changing via those tools. Since those do not really work with a Mail::Toaster, we could live just fine without it, but since a number of FreeBSD ports want it installed, we install it without all the extra X11 dependencies.


=item ezmlm

Installs Ezmlm-idx. This also tweaks the port Makefile so that it will build against MySQL 4.0 libraries if you don't have MySQL 3 installed. It also copies the sample config files into place so that you have some default settings.

  $setup->ezmlm( );

 required arguments:
   conf

 optional arguments:
   debug
   fatal

 result:
   1 - success
   0 - failure


=item filtering

Installs SpamAssassin, ClamAV, simscan, QmailScanner, maildrop, procmail, and programs that support the aforementioned ones. See toaster-watcher.conf for options that allow you to customize which programs are installed and any options available.

  $setup->filtering();



=item is_newer

Checks a three place version string like 5.3.24 to see if the current version is newer than some value. Useful when you have various version of a program like vpopmail or mysql and the syntax you need to use for building it is different for differing version of the software.


=item isoqlog

Installs isoqlog.

  $setup->isoqlog();


=item maildrop

Installs a maildrop filter in $prefix/etc/mail/mailfilter, a script for use with Courier-IMAP in $prefix/sbin/subscribeIMAP.sh, and sets up a filter debugging file in /var/log/mail/maildrop.log.

  $setup->maildrop( );


=item maildrop_filter

Creates and installs the maildrop mailfilter file.

  $setup->maildrop_filter();


=item maillogs

Installs the maillogs script, creates the logging directories (toaster_log_dir/), creates the qmail supervise dirs, installs maillogs as a log post-processor and then builds the corresponding service/log/run file to use with each post-processor.

  $setup->maillogs();



=item mattbundle

Downloads and installs the latest version of MATT::Bundle.

  $setup->mattbundle(debug=>1);

Don't do it. Matt::Bundle has been deprecated for years now.


=item mysql

Installs mysql server for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in Mail::Toaster::Mysql so read the man page for Mail::Toaster::Mysql for more info.

  $setup->mysql( );


=item phpmyadmin

Installs PhpMyAdmin for you, based on your settings in toaster-watcher.conf. The actual code that does the work is in Mail::Toaster::Mysql (part of Mail::Toaster::Bundle) so read the man page for Mail::Toaster::Mysql for more info.

  $setup->phpmyadmin($conf);


=item ports

Install the ports tree on FreeBSD or Darwin and update it with cvsup. 

On FreeBSD, it optionally uses cvsup_fastest to choose the fastest cvsup server to mirror from. Configure toaster-watch.conf to adjust it's behaviour. It can also install the portupgrade port to use for updating your legacy installed ports. Portupgrade is very useful, but be very careful about using portupgrade -a. I always use portupgrade -ai and skip the toaster related ports such as qmail since we have customized version(s) of them installed.

  $setup->ports();


=item qmailadmin

Install qmailadmin based on your settings in toaster-watcher.conf.

  $setup->qmailadmin();


=item qmail_scanner

Installs qmail_scanner and configures it for use.

  $setup->qmail_scanner();


=item qmail_scanner_config

prints out a note telling you how to enable qmail-scanner.

  $setup->qmail_scanner_config;


=item qmail_scanner_test

Send several test messages via qmail-scanner to test it. Sends a clean message, an attachment, a virus, and spam message.

  $setup->qmail_scanner_test();


=item qs_stats

Install qmail-scanner stats

  $setup->qs_stats();



=item razor

Install Vipul's Razor2

  $setup->razor( );


=item ripmime

Installs ripmime

  $setup->ripmime();


=item rrdutil

Checks for and installs any missing programs upon which RRDutil depends (rrdtool, net-snmp, Net::SNMP, Time::Date) and then downloads and installs the latest version of RRDutil. 

If upgrading, it is wise to check for differences in your installed rrdutil.conf and the latest rrdutil.conf-dist included in the RRDutil distribution.

  $setup->rrdutil;


=item simscan

Install simscan from Inter7.

  $setup->simscan();

See toaster-watcher.conf to see how these settings affect the build and operations of simscan.


=item simscan_conf

Build the simcontrol and ssattach config files based on toaster-watcher.conf settings.


=item simscan_test

Send some test messages to the mail admin using simscan as a message scanner.

    $setup->simscan_test();


=item socklog

	$setup->socklog( ip=>$ip );

If you need to use socklog, then you'll appreciate how nicely this configures it. :)  $ip is the IP address of the socklog master server.


=item socklog_qmail_control

	socklog_qmail_control($service, $ip, $user, $supervisedir);

Builds a service/log/run file for use with socklog.


=item config_spamassassin

	$setup->config_spamassassin();

Shows this URL: http://www.yrex.com/spam/spamconfig.php


=item squirrelmail

	$setup->squirrelmail

Installs Squirrelmail using FreeBSD ports. Adjusts the FreeBSD port by passing along WITH_APACHE2 if you have Apache2 selected in your toaster-watcher.conf.


=item sqwebmail

	$setup->sqwebmail();

install sqwebmail based on your settings in toaster-watcher.conf.


=item supervise

	$setup->supervise();

One stop shopping: calls the following subs:

  $qmail->control_create        (conf=>$conf);
  $setup->service_dir_create    ();
  $toaster->supervise_dirs_create (conf=>$conf);
  $qmail->install_qmail_control_files ( conf=>$conf );
  $qmail->install_qmail_control_log_files( conf=>$conf);
  $setup->service_symlinks      ( debug=>$debug);


=item service_symlinks

Sets up the supervised mail services for Mail::Toaster

	$setup->service_symlinks();

This populates the supervised service directory (default: /var/service) with symlinks to the supervise control directories (typically /var/qmail/supervise/). Creates and sets permissions on the following directories and files:

  /var/service/pop3
  /var/service/smtp
  /var/service/send
  /var/service/submit


=item startup_script

Sets up the supervised mail services for Mail::Toaster

	$setup->startup_script( );

If they don't already exist, this sub will create:

	daemontools service directory (default /var/service) 
	symlink to the services script

The services script allows you to run "services stop" or "services start" on your system to control the supervised daemons (qmail-smtpd, qmail-pop3, qmail-send, qmail-submit). It affects the following files:

  $prefix/etc/rc.d/[svscan|services].sh
  /usr/local/sbin/services


=item test

Run a variety of tests to verify that your Mail::Toaster installation is working correctly.


=item ucspi_tcp

Installs ucspi-tcp with my (Matt Simerson) MySQL patch.

	$setup->ucspi_tcp( );


=item vpopmail

Vpopmail is great, but it has lots of options and remembering which option you used months or years ago to build a mail server is not always easy. So, store all the settings in toaster-watcher.conf and this sub will install vpopmail for you, honoring all your settings and passing the appropriate configure flags to vpopmail's configure.

	$setup->vpopmail( );

If you do not have toaster-watcher.conf installed, it will ask you a series of questions and then install based on your answers.


=item vpopmail_etc


Builds the ~vpopmail/etc/tcp.smtp file with a mess of sample entries and user specified settings.

	$setup->vpopmail_etc( );


=item vpopmail_vmysql_h

	vpopmail_vmysql_h(replication, master, slave, user, pass);

Versions of vpopmail less than 5.2.26 (or thereabouts) required you to manually edit vmysql.h to set your mysql login parameters. This sub modifies that file for you.


=item vpopmail_mysql_privs

Connects to MySQL server, creates the vpopmail table if it doesn't exist, and sets up a vpopmail user and password as set in $conf. 

    $setup->vpopmail_mysql_privs($conf);


=item vqadmin

	$setup->vqadmin($conf, $debug);

Installs vqadmin from ports on FreeBSD and from sources on other platforms. It honors your cgi-bin and your htdocs directory as configured in toaster-watcher.conf.

=back


=head1 DEPENDENCIES

    IO::Socket::SSL


=head1 AUTHOR

Matt Simerson - matt@tnpi.net


=head1 BUGS

None known. Report to author. Patches welcome (diff -u preferred)


=head1 TODO

Better documentation. It is almost reasonable now.


=head1 SEE ALSO

The following are all man/perldoc pages: 

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
