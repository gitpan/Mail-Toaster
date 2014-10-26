package Mail::Toaster::Darwin;
use strict;
use warnings;

our $VERSION = '5.26';

use Carp;
use Params::Validate qw(:all);

use lib 'lib';
use Mail::Toaster 5.25;

my ($toaster, $log, $util, %std_opts );

sub new {
    my $class = shift;
    my %p     = validate( @_,
        {   'log' => { type => OBJECT,  optional => 1 },
            fatal => { type => BOOLEAN, optional => 1, default => 1 },
            debug => { type => BOOLEAN, optional => 1 },
        }
    );

    $toaster = $log = $p{'log'};
    $util = $toaster->get_util;

    my $debug = $log->get_debug;  # inherit from our parent
    my $fatal = $log->get_fatal;
    $debug = $p{debug} if defined $p{debug};  # explicity overridden
    $fatal = $p{fatal} if defined $p{fatal};

    my $self = {
        'log' => $log,
        debug => $debug,
        fatal => $fatal,
    };
    bless $self, $class;

    # globally scoped hash, populated with defaults as requested by the caller
    %std_opts = (
        'test_ok' => { type => BOOLEAN, optional => 1 },
        'fatal'   => { type => BOOLEAN, optional => 1, default => $fatal },
        'debug'   => { type => BOOLEAN, optional => 1, default => $debug },
    );

    return $self;
}

sub install_port {
    my $self = shift;
    my $port_name = shift or return $log->error("missing port name", fatal => 0);

    my %p = validate( @_, {
            'opts'   => { type=>SCALAR,  optional=>1 },
            %std_opts,
        },
    );

    my ( $opts ) = ( $p{'opts'} );
    my %args = ( debug => $p{debug}, fatal => $p{fatal} );

    #	$self->ports_check_age("30");

    print "install_port: installing $port_name...";

    my $port_bin = $util->find_bin( "port", %args );

    unless ( -x $port_bin ) {
        print "FAILED: please install DarwinPorts!\n";
        return 0;
    }

    my $cmd = "$port_bin install $port_name";
    $cmd .= " $opts" if (defined $opts && $opts);
    
    return $util->syscmd( $cmd, %args  );
}

sub ports_check_age {

    my ( $self, $age, $url ) = @_;

    $url ||= "http://mail-toaster.org";

    if ( -M "/usr/ports" > $age ) {
        $self->update_ports();
    }
    else {
        print "ports_check_age: Ports file is current (enough).\n";
    }
}

sub update_ports {
    my $self = shift;
    my $cvsbin = $util->find_bin( "cvs",fatal=>0, debug=>0 );

    unless ( -x $cvsbin ) {
        die "FATAL: could not find cvs, please install Developer Tools!\n";
    }

    print "Updating Darwin ports...\n";

    my $portsdir = "/usr/darwinports";

    if ( !-d $portsdir && -e "/usr/dports" ) { 
        $portsdir = "/usr/dports"; 
    }

    if ( !-d $portsdir && -e "/usr/ports/dports" ) {
        $portsdir = "/usr/ports/dports";
    }

    if ( -d $portsdir ) {
        $self->update_ports_sync() and return;
    }
    else {
        $self->update_ports_init();
    };
};

sub update_ports_init {
    my $self = shift;

    print <<'EO_NO_PORTS';
   WARNING! I expect to find your dports dir in /usr/ports/dports. Please install 
   it there or add a symlink there pointing to where you have your Darwin ports 
   installed.
   
   If you need to install DarwinPorts, please visit this URL for details: 
      http://darwinports.opendarwin.org/getdp/ 

   or the DarwinPorts guide: 
      http://darwinports.opendarwin.org/docs/ch01s03.html.

EO_NO_PORTS
;

    unless (
        $util->yes_or_no(
            q=>"May I try to set up darwin ports for you?")
        )
    {
        print "ok, skipping install.\n";
        return;
    }

    $util->cwd_source_dir( "/usr", debug=>0 );

    print "\n\nthe CVS password is blank, just hit return at the prompt\n\n";

    my $cmd =
'cvs -d :pserver:anonymous@anoncvs.opendarwin.org:/Volumes/src/cvs/od login';
    $util->syscmd( $cmd, debug=>0 );
    
    $cmd =
'cvs -d :pserver:anonymous@anoncvs.opendarwin.org:/Volumes/src/cvs/od co -P darwinports';
    $util->syscmd( $cmd, debug=>0 );
    
    chdir("/usr");
    $util->syscmd( "mv darwinports dports", debug=>0 );
    
    unless ( -d "/etc/ports" ) { mkdir( "/etc/ports", oct('0755') ) };
    
    $util->syscmd( "cp dports/base/doc/sources.conf /etc/ports/", debug=>0 );
    $util->syscmd( "cp dports/base/doc/ports.conf /etc/ports/", debug=>0 );
        
    $util->file_write( "/etc/ports/sources.conf",
        lines  => ["file:///usr/dports/dports"],
        append => 1,
        debug  => 0,
    );

    my $portindex = $util->find_bin( "portindex",debug=>0 );
    unless ( -x $portindex ) {
        print "compiling darwin ports base.\n";
        chdir("/usr/dports/base");
        $util->syscmd( "./configure; make; make install", debug=>0 );
    }
}

sub update_ports_sync {
    my $self = shift;

    print "\n\nupdate_ports: You might want to update your ports tree!\n\n";
    if ( ! $util->yes_or_no(
            question=>"\n\nWould you like me to do it for you?" ) )
    {
        print "ok then, skipping update.\n";
        return;
    }

    # the new way
    my $bin = $util->find_bin( "port" );
    return $util->syscmd( "$bin -d sync" );

    #	 the old way
    #chdir($portsdir);

    #print "\n\nthe CVS password is blank, just hit return at the prompt)\n\n";

    #my $cmd = 'cvs -d :pserver:anonymous@anoncvs.opendarwin.org:/Volumes/src/cvs/od login';
    #$util->syscmd( $cmd );
    #$util->syscmd( 'cvs -q -z3 update -dP' );

    #	if ( -x "/opt/local/bin/portindex") { #
    #		$util->syscmd( "/opt/local/bin/portindex" ); }
    #	elsif ( -x "/usr/local/bin/portindex" ) { #
    #		$util->syscmd( "/usr/local/bin/portindex" );
    #	};
}

1;
__END__


=head1 NAME

Mail::Toaster::Darwin - Darwin specific Mail Toaster functions

=head1 SYNOPSIS

Mac OS X (Darwin) scripting functions


=head1 DESCRIPTION

functions I've written for perl scripts running on MacOS X (Darwin) systems.

Usage examples for each subroutine are included.


=head1 SUBROUTINES

=over

=item new

    use Mail::Toaster::Darwin;
	my $darwin = Mail::Toaster::Darwin->new;


=item update_ports

Updates the Darwin Ports tree (/usr/ports/dports/).

	$darwin->update_ports();


=item install_port

	$darwin->install_port( "openldap2" );

That's it. Really. Honest. Nothing more. 

 arguments required:
    port  - the name of the port

 arguments optional:
    opts  - port options you can pass
    debug



=back

=head1 AUTHOR

Matt Simerson <matt@tnpi.net>

=head1 BUGS

None known. Report any to author.

=head1 TODO

Needs more documentation.

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://mail-toaster.org/


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003-2008, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
