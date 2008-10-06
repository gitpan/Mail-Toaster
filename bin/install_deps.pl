#!perl

use strict;
use warnings;

use CPAN;
use English;

my %required_modules = (
    'Params::Validate' => { cat => 'devel',   port => 'p5-Params-Validate' },
    'Mail::Send'       => { cat => 'mail',    port => 'p5-Mail-Tools'  },
    'Net::DNS'         => { cat => 'dns',     port => 'p5-Net-DNS'     },
    'Date::Parse'      => { cat => 'devel',   port => 'p5-TimeDate'    },
    'Email::Valid'     => { cat => 'mail',    port => 'p5-Email-Valid' },
    'version'          => { cat => 'devel',   port => 'p5-version'     },
);

my $sudo = $EFFECTIVE_USER_ID == 0 ? '' : 'sudo';

if ( lc($OSNAME) eq 'freebsd' ) {
    print "detected FreeBSD, installing dependencies from ports\n";
    install_freebsd_ports();    
}
elsif ( lc($OSNAME) eq 'darwin' ) {
    install_darwin_ports();    
    install_cpan();
} else {
    install_cpan();
}

exit;

sub install_cpan {

    if ( $EFFECTIVE_USER_ID != 0 ) {
        warn "cannot use CPAN to install modules because you aren't root!\n";
        return;
    };

    foreach my $module ( keys %required_modules ) {
        CPAN::install $module;
    };
};

sub install_darwin_ports {

    my $dport = '/opt/local/bin/port';
    if ( ! -x $dport ) {
        warn "could not find $dport. Is DarwinPort/MacPorts installed?\n";
        return;
    }
    foreach my $module ( keys %required_modules ) {
        my $port = $required_modules{$module}->{'dport'} 
                || $required_modules{$module}->{'port'};
        system "$sudo $dport install $port";
    };
};

sub install_freebsd_ports {

    foreach my $module ( keys %required_modules ) {

        my $category = $required_modules{$module}->{'cat'};
        my $portdir  = $required_modules{$module}->{'port'};

        if ( !$category || !$portdir ) {
            warn "incorrect hash key or values for $module\n";
            next "cat/port not set";
        };

        my ($registered_name) = $portdir =~ /^p5-(.*)$/;

        if ( `/usr/sbin/pkg_info | /usr/bin/grep $registered_name` ) {
            print "$module is installed.\n";
            next;
        }

        print "installing $module\n";
        if ( ! chdir "/usr/ports/$category/$portdir" ) {
            warn "error, couldn't chdir to /usr/ports/$category/$portdir\n";
            next;
        }
        system "$sudo make install clean";
    }
}
