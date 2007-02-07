#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Perl.pm, matt Exp $
#

package Mail::Toaster::Perl;

use Carp;
use English qw( -no_match_vars );
use Params::Validate qw( :all);

use vars qw($VERSION $err);

$VERSION = '5.05';

use lib "inc";
use lib "lib";

sub new {
    my ( $class, $name ) = @_;
    my $self = { name => $name };
    bless( $self, $class );
    return $self;
}

sub check {

    my $self = shift;
    
    my %p = validate( @_, {
	        'min'    => { type=>SCALAR, optional=>1, default=>5.006001},
	        'timer'  => { type=>SCALAR, optional=>1, default=>60 },
            'debug'  => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

	my ($min, $timer, $debug) = ( $p{'min'}, $p{'timer'}, $p{'debug'} );

    unless ( $] < $min ) {    # $] is the version of perl  we're running
        print "using Perl " . $] . " which is current enough, skipping.\n"
          if $debug;
        return 1;
    }

    # we probably can't install anything unless we're root
    return 0 unless ( $REAL_USER_ID eq 0 );

    warn qq{\a\a\a
**************************************************************************
**************************************************************************
  Version $] of perl is NOT SUPPORTED by several mail toaster components. 
  You should strongly consider upgrading perl before continuing.  Perl 
  version $min is the lowest version supported and 5.8 is recommended.

  Press return to begin upgrading your perl... (or Control-C to cancel)
**************************************************************************
**************************************************************************
	};

    print "You should upgrade to perl 5.8.x as it is quite stable, in 
widespread use, and many useful perl programs such as SpamAssassin require
it for full functionality.";

    my $version = "perl-5.8";

    require Mail::Toaster::Utility;
    my $utility = Mail::Toaster::Utility->new;

    if (
        $utility->yes_or_no(
            question => "Would you like me to install 5.8?",
            timeout  => 20
        )
      )
    {
        $version = "perl-5.8";
    }

    $self->perl_install( version => $version );
}

sub has_module {
    my $self = shift;
    my($name, $ver) = @_;

    ## no critic ( ProhibitStringyEval )
    eval("use $name" . ($ver ? " $ver;" : ";"));
    ## use critic

    # returns the status of the eval error
    !$EVAL_ERROR;
};

sub module_install {
    my $self = shift;

    # parameter validation here
    my %p = validate( @_, {
            'conf'    => { type=>HASHREF|UNDEF, optional=>1, },
            'module'  => { type=>SCALAR,  optional=>0, },
            'archive' => { type=>SCALAR,  optional=>0, },
            'site'    => { type=>SCALAR,  optional=>0, },
            'url'     => { type=>SCALAR,  optional=>0, },
            'src'     => { type=>SCALAR,  optional=>1, default=>"/usr/local/src" },
            'targets' => { type=>ARRAYREF,optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $conf, $module, $site, $url, $src, $targets, $fatal, $debug )
        = ( $p{'conf'}, $p{'module'}, $p{'site'}, $p{'url'}, 
            $p{'src'}, $p{'targets'}, $p{'fatal'}, $p{'debug'} );


    require Mail::Toaster::Utility;
    my $utility = Mail::Toaster::Utility->new;

    $utility->chdir_source_dir( dir => $src );

    #$utility->syscmd( command=>"rm -rf $module-*" );   # nuke any old versions

    print "checking for previous build sources.\n";
    if ( -d $module ) {
        unless ( $utility->source_warning( package=>$module, src=>$src ) ) {
            carp "\nmodule_install: OK then, skipping install.\n";
            return 0;
        }
        else {
            $utility->syscmd( command => "rm -rf $module" );
        }
    }

    $utility->sources_get(
        conf    => $conf,
        site    => $site,
        url     => $url,
        package => $p{'archive'} || $module,
        debug   => $debug,
    );

    $utility->archive_expand( archive => $module, debug => $debug )
      or croak "Couldn't expand $module: $!\n";

    my $found;
    print "looking for $module in $src...";
    foreach my $file ( $utility->get_dir_files( dir => $src ) ) {

        next if ( $file !~ /$module-/ && $file !~ /$module/ );
        next if !-d $file;

        print "found: $file\n";
        $found++;
        chdir($file);

        my $targets = $targets;
        unless ( @$targets[0] && @$targets[0] ne "" ) {
            print "module_install: using default targets.\n";
            @$targets = ( "perl Makefile.PL", "make", "make install" );
        }

        print "installing with targets " . join( ", ", @$targets ) . "\n";
        foreach (@$targets) {
            if ( ! $utility->syscmd( command => $_ , debug=>$debug ) ) {
                carp "$_ failed!\n";
                return;
            };;
        }

        chdir("..");
        $utility->syscmd( command => "rm -rf $file", debug=>$debug );
        last;
    }

    $found ? return 1 : return 0;
}

sub module_load {

    my $self = shift;
    
    my %p = validate( @_, {
            'module'     => { type=>SCALAR,  optional=>0, },
            'port_name'  => { type=>SCALAR,  optional=>1, },
            'port_group' => { type=>SCALAR,  optional=>1, },
            'site'       => { type=>SCALAR,  optional=>1, },
            'url'        => { type=>SCALAR,  optional=>1, },
            'archive'    => { type=>SCALAR,  optional=>1, },
            'warn'       => { type=>BOOLEAN, optional=>1, default=>0  },
			'timer'      => { type=>SCALAR,  optional=>1, default=>30 },
            'auto'       => { type=>BOOLEAN, optional=>1, default=>0  },
            'fatal'      => { type=>BOOLEAN, optional=>1, default=>0  },
            'debug'      => { type=>BOOLEAN, optional=>1, default=>1  },
        },
    );

	my ($module, $port_name, $port_group, $site, 
        $url, $archive, $warn, $timer )
        = ( $p{'module'}, $p{'port_name'}, $p{'port_group'}, $p{'site'}, 
            $p{'url'}, $p{'archive'}, $p{'warn'}, $p{'timer'} );

    # this seems to work most of the time
    if ( $self->has_module($module) ) {
        if ( $p{'debug'} ) {
            eval {
                require ExtUtils::Installed;
                my $ext = ExtUtils::Installed->new();
                $self->_formatted("module_load, checking $module", 
                    "ok (". $ext->version($module) .")" );
            };
        };
        #$module->import();
        return 1;
    };

    # another way to skin the same cat as above
    #	eval { local $SIG{__DIE__}; require Term::ReadKey };
    #	if ($@) { #do fun stuff };

    # we probably can't install anything unless we're root
    unless ( $REAL_USER_ID eq 0 ) 
    {
        $err = "Sorry, root permissions are needed to install perl modules";
        croak $err if $p{'fatal'};
        carp $err;
        return;
    };

    carp "\ncouldn't import $module: $EVAL_ERROR\n";    # show error

    require Mail::Toaster::Utility;
    my $utility = Mail::Toaster::Utility->new;

    if ( ! $p{'auto'} && ! $utility->yes_or_no(
            question => "\n\nWould you like me to try installing $module: ",
            timeout  => $timer, )
    ) {
        if ($warn) {
            carp "\n$module is required, you have been warned.\n";
            return;
        }
        else { 
            croak "\nI'm sorry, $module is required to continue.\n" 
        }
    }

    if (   $OSNAME eq "freebsd" 
        && $port_group && $port_name
        && -e "/usr/ports/$port_group/$port_name" ) 
    {
        require Mail::Toaster::FreeBSD;
        if ( Mail::Toaster::FreeBSD->port_install( 
                port  => $port_name, 
                base  => $port_group,
                debug => $p{'debug'},
            ) 
          )
        {
            $module->import();
            return 1;
        }
    };

    require CPAN;
    CPAN::Shell->install($module);

    print "testing install...";
    if ( $self->has_module($module) ) {
        print "success.\n"; 
        return 1; 
    };
    print "FAILED.\n";

    # finally, try from sources if possible
    if ( $site && $url ) {
        print "trying to install from sources\n";
        $self->module_install(
            module  => $module,
            site    => $site,
            url     => $url,
            archive => $archive,
        );

        print "testing install...";
        if ( $self->has_module($module) ) {
            print "success.\n";
            return 1;
        }
        print "FAILED.\n";
    }

    croak "failed to install $module\n" if $p{'fatal'};
    return;
}

sub perl_install {

    my $self = shift;

    my %p = validate( @_, {
            'version' => { type=>SCALAR, },
            'options' => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
        },
    );

    my ( $version, $options, $debug )
        = ( $p{'version'}, $p{'optional'}, $p{'debug'} );

    require Mail::Toaster::Utility;
    my $utility = Mail::Toaster::Utility->new;

    if ( $OSNAME eq "freebsd" ) {

        $self->module_load( module => "Mail::Toaster::FreeBSD" );
        my $freebsd = Mail::Toaster::FreeBSD->new();

        my $portupgrade =
          $utility->find_the_bin( bin => "portupgrade", debug => 0 );

        my $port = $freebsd->is_port_installed( port => "perl" );
        if ( ! $port  ) {
            
            # install perl from ports
            $freebsd->port_install(
                port  => $version,
                base  => "lang",
                check => "perl-5",
                flags => $options
            );
            $utility->syscmd( command => "/usr/local/bin/use.perl port" );
            return 1;
        };
        
        # try to upgrade
        if ( -x $portupgrade ) {
            $utility->syscmd(
                command => "$portupgrade $port",
                debug   => $debug
            );
            print
"\n\nPerl has been upgraded. Now we must upgrade all the perl modules as well. This is going to take a while!\n\n";
            sleep 5;
            $utility->syscmd(
                command =>
                  "$portupgrade -f `pkg_info | grep p5- | cut -d\" \" -f1`",
                debug => $debug,
            );
            $utility->syscmd( command =>
"$portupgrade -f `pkg_info | grep rrdtool- | cut -d\" \" -f1`"
            );
        }
        return 1;
    }
    elsif ( $OSNAME eq "darwin" ) {
        
        if ( -d "/usr/ports/dports" || -d "/usr/dports/dports") {
            $self->module_load( module => "Mail::Toaster::Darwin" );
            my $darwin = Mail::Toaster::Darwin->new();
            
            $darwin->port_install(port_name => "perl5.8" );
            $darwin->port_install(port_name => "p5-compress-zlib" );
            return 1;
        }

        # as directed at http://developer.apple.com/internet/macosx/

        unless ( -d "/usr/local/src" ) { mkdir( "/usr/local/src", oct('0755') ) }
        chdir("/usr/local/src");

        $version ||= "perl-5.8.4";

        if ( $] < 5.008001 ) {
            unless ( -e "$version.tar.gz" ) {
                $utility->get_file(
                    "ftp://ftp.perl.org/pub/CPAN/src/$version.tar.gz");
            }

            if ( -d $version ) {
                my $r = $utility->source_warning( package=>$version );
            }

            $utility->syscmd( command => "tar -xzf $version.tar.gz" );

            chdir($version);
            my $replace = $utility->yes_or_no(
                question => "\n\n    NOTICE!   \n
Apple installs Perl in /usr/bin. I can install it there as well, overwriting Darwin's
supplied Perl (5.6.0) or it can be installed in /usr/local/bin (The BSD Way). Some
would feel that's safer as it leaves Darwin's distributed version of Perl in tact. I
would suggest that's apt to cause you grief later.\n

Shall I overwrite the default Perl?"
            );

            if ($replace) {
                $utility->syscmd( command => "./Configure -de -Dprefix=/usr" );
            }
            else { 
                $utility->syscmd( command => "./Configure -de" ); 
            }

            $utility->syscmd( command => "make" );
            $utility->syscmd( command => "make test" );

            my $install = $utility->yes_or_no(
                question => "\n\n
OK, I just finished running \"make test\" and the results are show above. You should see
a success rate somewhere along the lines of 99.7% okay with only a couple failures. If that's
the case, just feed me a y and I'll install perl for you. Select n to cancel.\n\n"
            );

            return unless $install;

            my $sudo = "";
            if ( $< ne "0" ) {
                $sudo = "/usr/bin/sudo -p 'Password for %u@%h:'";
            }

            if ($replace) {

# while this code is not critical, it will fix the problem
# described here: http://dev.perl.org/perl5/news/2002/07/18/580ann/perldelta.html#mac%20os%20x%20dyld%20undefined%20symbols
                use File::Copy;
                my $file = "/Library/Perl/darwin/CORE/libperl.dylib";
                if ( -e $file ) {
                    move( $file, "$file.old" )
                      or carp "failed to remove $file\n";
                }
                $file = "/System/Library/Perl/darwin/CORE/libperl.dylib";
                if ( -e $file ) {
                    move( $file, "$file.old" )
                      or carp "failed to remove $file\n";
                }
                $utility->syscmd( command =>
                      "$sudo find /Library/Perl -name '*.bundle' -exec rm {} \;"
                );
                $utility->syscmd( command =>
"$sudo find /System/Library/Perl -name '*.bundle' -exec rm {} \;"
                );
            }
            $utility->syscmd( command => "$sudo make install" );
        }
    }
}

sub _formatted {
    my ($self, $mess, $result) = @_;
    my $dots = '...';
    my $length_of_mess = length($mess);
    if ( $length_of_mess < 65 ) {
        until ( $length_of_mess == 65 ) { $dots .= "."; $length_of_mess++ }
    }
    print $mess if $mess;
    if ($result) {
        print $dots . $result;
    }
    print "\n";
}

1;
__END__


=head1 NAME

Mail::Toaster::Perl - Perl specific functions for Mail Toaster

=head1 SYNOPSIS

Perl functions for loading, installing and testing perl modules.


=head1 DESCRIPTION

Mail::Toaster::Perl is a few frequently used functions that make dealing with perl and perl modules a little more managable. The following methods are available:

	check       - checks perl version
	install     - installs perl
	module_load - loads a perl module (attempts to install if missing)

See the description for each method below.

=head1 METHODS

=over 8

=item new

To use a a method in this class, you must first request a Mail::Toaster::Perl object:

  use Mail::Toaster::Perl;
  my $perl = Mail::Toaster::Perl->new();

You can then call subsequent methods with $perl->method();


=item check

Checks perl to make sure the version is higher than a minimum (supplied) value.

   $perl->check( min=>'5.006001' );

 arguments required:
    min - defaults to 5.6.1 (5.006001).

 arguments optional:
    timer - default 60 seconds
    debug
    
 usage:
   $perl->check( min=>5.006001 );

returns 1 for success, 0 for failure.


=item has_module

Checks to see if a perl module is installed.

   if ( $perl->has_module("Date::Format") ) {
       print "yay!\n";
   };

 arguments required:
    module - the name of the perl module

 arguments optional:
    version - minimum version


=item module_install

Downloads and installs a perl module from sources.

The arguments get concatenated to a url like this: $site/$url/$module.tar.gz

Once downloaded, we expand the archive and attempt to build it. If not set, the default targets are: make, make test, and make install. After install, we clean up the sources and exit. 

This method builds from sources only. Compare to module_load which will attempt to build from FreeBSD ports, CPAN, and then finally resort to sources if all else fails.


 usage:
    $perl->module_install( module=>"Params::Validate", conf=>$conf );

 Example:

    $perl->module_install(
       module   => 'Mail-Toaster',
       archive  => 'Mail-Toaster-4.01.tar.gz',
       site     => 'http://www.tnpi.biz',
       url      => '/internet/mail/toaster/src',
       targets  => ['perl Makefile.PL', 'make install'],
    );

 arguments required:
    module  - module name          (CGI)
    site    - site to download from
    url     - path to downloads on site
    

 arguments optional:
    archive - archived module name (CGI-1.35.tar.gz)
    targets - build targets: 
    conf    - $conf is toaster-watcher.conf settings, (barely) optional.

 result:
    1 - success
    0 - failure.


=item module_load

    $perl->module_load( module=>'Net::DNS' );

Loads a required Perl module. If the load fails, we attempt to install the required module (rather than failing gracelessly).


 arguments required:
    module      - the name of the module: (ie. LWP::UserAgent)
    
 arguments optional:
    port_name  - is the name of the FreeBSD port
    port_group - is is the ports group ( "ls /usr/ports" to see groups)
    warn        - if set, we warn instead of dying upon failure
    timer       - how long (in seconds) to wait for user input (default 60)
    site        - site to download sources from
    url         - url at site (see module_install)
    archive     - downloadable archive name (module-1.03.tar.gz)

returns 1 for success, 0 for failure.


=item perl_install

    $perl->perl_install( version=>"perl-5.8.5" );

currently only works on FreeBSD and Darwin (Mac OS X)

input is a hashref with the following values:

    version - perl version to install
    options - compile flags to set (comma separated list)

On FreeBSD, version is the directory name such as "perl5.8" derived from /usr/ports/lang/perl5.8. Ex: $perl->perl_install( version=>"perl5.8" );

On Darwin, it's the directory name of the port in Darwin Ports. Ex: $perl->perl_install( {version=>"perl-5.8"} ) because perl is installed from /usr/ports/dports/lang/perl5.8. Otherwise, it's the exact version to download and install, ex: "perl-5.8.5".

Example with option:

$perl->perl_install( version=>"perl-5.8.5", options=>"ENABLE_SUIDPERL" );



=back

=head1 AUTHOR

Matt Simerson (matt@tnpi.net)

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://www.tnpi.net/internet/mail/toaster/

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003-2006, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut


