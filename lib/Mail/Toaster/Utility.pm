package Mail::Toaster::Utility;
# ABSTRACT: utility subroutines for sysadmin tasks

use strict;
use warnings;

our $VERSION = '5.50';

use Cwd;
use Carp;
#use Data::Dumper;
use English qw( -no_match_vars );
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use File::stat;
use Params::Validate qw(:all);
use Scalar::Util qw( openhandle );
#use URI;  # required in get_url

use lib 'lib';
use parent 'Mail::Toaster::Base';

sub ask {
    my $self = shift;
    my $question = shift;
    my %p = validate(
        @_,
        {   default  => { type => SCALAR|UNDEF, optional => 1 },
            timeout  => { type => SCALAR,  optional => 1 },
            password => { type => BOOLEAN, optional => 1, default => 0 },
            test_ok  => { type => BOOLEAN, optional => 1 },
        }
    );

    my $pass     = $p{password};
    my $default  = $p{default};

    if ( ! $self->is_interactive() ) {
        $self->audit( "not running interactively, can not prompt!");
        return $default;
    }

    return $self->error( "ask called with \'$question\' which looks unsafe." )
        if $question !~ m{\A \p{Any}* \z}xms;

    my $response;

    return $p{test_ok} if defined $p{test_ok};

PROMPT:
    print "Please enter $question";
    print " [$default]" if ( $default && !$pass );
    print ": ";

    system "stty -echo" if $pass;

    if ( $p{timeout} ) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $p{timeout};
            $response = <STDIN>;
            alarm 0;
        };
        if ($EVAL_ERROR) {
            $EVAL_ERROR eq "alarm\n" ? print "timed out!\n" : warn;
        }
    }
    else {
        $response = <STDIN>;
    }

    if ( $pass ) {
        print "Please enter $question (confirm): ";
        my $response2 = <STDIN>;
        unless ( $response eq $response2 ) {
            print "\nPasswords don't match, try again.\n";
            goto PROMPT;
        }
        system "stty echo";
        print "\n";
    }

    chomp $response;

    return $response if $response; # if they typed something, return it
    return $default if $default;   # return the default, if available
    return '';                     # return empty handed
}

sub archive_file {
    my $self = shift;
    my $file = shift or return $self->error("missing filename in request");
    my %p = validate( @_,
        {   'sudo'  => { type => BOOLEAN, optional => 1, default => 1 },
            'mode'  => { type => SCALAR,  optional => 1 },
            destdir => { type => SCALAR,  optional => 1 },
            $self->get_std_opts,
        }
    );

    my %args = $self->get_std_args( %p );

    return $self->error( "file ($file) is missing!", %args )
        if !-e $file;

    my $archive = $file . '.' . time;

    if ( $p{destdir} && -d $p{destdir} ) {
        my ($vol,$dirs,$file_wo_path) = File::Spec->splitpath( $archive );
        $archive = File::Spec->catfile( $p{destdir}, $file_wo_path );
    };

    # see if we can write to both files (new & archive) with current user
    if (    $self->is_writable( $file, %args )
         && $self->is_writable( $archive, %args ) ) {

        # we have permission, use perl's native copy
        copy( $file, $archive );
        if ( -e $archive ) {
            $self->audit("archive_file: $file backed up to $archive");
            $self->chmod( file => $file, mode => $p{mode}, %args ) if $p{mode};
            return $archive;
        };
    }

    # we failed with existing permissions, try to escalate
    $self->archive_file_sudo( $file ) if ( $p{sudo} && $< != 0 );

    return $self->error( "backup of $file to $archive failed: $!", %args)
        if ! -e $archive;

    $self->chmod( file => $file, mode => $p{mode}, %args ) if $p{mode};

    $self->audit("$file backed up to $archive");
    return $archive;
}

sub archive_file_sudo {
    my $self = shift;
    my ($file, $archive) = @_;

    my $sudo = $self->sudo();
    my $cp = $self->find_bin( 'cp',fatal=>0 );

    if ( $sudo && $cp ) {
        return $self->syscmd( "$sudo $cp $file $archive",fatal=>0 );
    }
    $self->error( "archive_file: sudo or cp was missing, could not escalate.",fatal=>0);
    return;
};

sub chmod {
    my $self = shift;
    my %p = validate(
        @_,
        {   'file'        => { type => SCALAR,  optional => 1, },
            'file_or_dir' => { type => SCALAR,  optional => 1, },
            'dir'         => { type => SCALAR,  optional => 1, },
            'mode'        => { type => SCALAR,  optional => 0, },
            'sudo'        => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts,
        }
    );

    my $mode = $p{mode};
    my %args = $self->get_std_args( %p );

    my $file = $p{file} || $p{file_or_dir} || $p{dir}
        or return $self->error( "invalid params to chmod in ". ref $self  );

    if ( $p{sudo} ) {
        my $chmod = $self->find_bin( 'chmod', verbose => 0 );
        my $sudo  = $self->sudo();
        $self->syscmd( "$sudo $chmod $mode $file", verbose => 0 )
            or return $self->error( "couldn't chmod $file: $!", %args );
    }

    # note the conversion of ($mode) to an octal value. Very important!
    CORE::chmod( oct($mode), $file ) or
        return $self->error( "couldn't chmod $file: $!", %args);

    $self->audit("chmod $mode $file");
}

sub chown {
    my $self = shift;
    my $file = shift;
    my %p = validate( @_,
        {   'uid'  => { type => SCALAR  },
            'gid'  => { type => SCALAR  },
            'sudo' => { type => BOOLEAN, optional => 1 },
            $self->get_std_opts,
        }
    );

    my %args = $self->get_std_args( %p );
    my ( $uid, $gid, $sudo ) = ( $p{uid}, $p{gid}, $p{sudo} );

    $file or return $self->error( "missing file or dir", %args );
    return $self->error( "file $file does not exist!", %args ) if ! -e $file;

    $self->audit("chown: preparing to chown $uid $file");

    # sudo forces system chown instead of the perl builtin
    return $self->chown_system( $file,
        %args,
        user  => $uid,
        group => $gid,
    ) if $sudo;

    my ( $nuid, $ngid ); # if uid or gid is not numeric, convert it

    if ( $uid =~ /\A[0-9]+\z/ ) {
        $nuid = int($uid);
        $self->audit("  using $nuid from int($uid)");
    }
    else {
        $nuid = getpwnam($uid);
        return $self->error( "failed to get uid for $uid", %args) if ! defined $nuid;
        $self->audit("  converted $uid to a number: $nuid");
    }

    if ( $gid =~ /\A[0-9\-]+\z/ ) {
        $ngid = int( $gid );
        $self->audit("  using $ngid from int($gid)");
    }
    else {
        $ngid = getgrnam( $gid );
        return $self->error( "failed to get gid for $gid", %args) if ! defined $ngid;
        $self->audit("  converted $gid to numeric: $ngid");
    }

    chown( $nuid, $ngid, $file )
        or return $self->error( "couldn't chown $file: $!",%args);

    return 1;
}

sub chown_system {
    my $self = shift;
    my $dir = shift;
    my %p = validate( @_,
        {   'user'    => { type => SCALAR,  optional => 0, },
            'group'   => { type => SCALAR,  optional => 1, },
            'recurse' => { type => BOOLEAN, optional => 1, },
            $self->get_std_opts,
        }
    );

    my ( $user, $group, $recurse ) = ( $p{user}, $p{group}, $p{recurse} );
    my %args = $self->get_std_args( %p );

    $dir or return $self->error( "missing file or dir", %args );
    my $cmd = $self->find_bin( 'chown', %args );

    $cmd .= " -R"     if $recurse;
    $cmd .= " $user";
    $cmd .= ":$group" if $group;
    $cmd .= " $dir";

    $self->audit( "cmd: $cmd" );

    $self->syscmd( $cmd, %args ) or
        return $self->error( "couldn't chown with $cmd: $!", %args);

    my $mess;
    $mess .= "Recursively " if $recurse;
    $mess .= "changed $dir to be owned by $user";
    $self->audit( $mess );

    return 1;
}

sub clean_tmp_dir {
    my $self = shift;
    my $dir = shift or die "missing dir name";
    my %p = validate( @_, { $self->get_std_opts } );

    my %args = $self->get_std_args( %p );

    my $before = cwd;   # remember where we started

    return $self->error( "couldn't chdir to $dir: $!", %args) if !chdir $dir;

    foreach ( $self->get_dir_files( $dir ) ) {
        next unless $_;

        my ($file) = $_ =~ /^(.*)$/;

        $self->audit( "deleting file $file" );

        if ( -f $file ) {
            unlink $file or
                $self->file_delete( $file, %args );
        }
        elsif ( -d $file ) {
            rmtree $file or return $self->error( "couldn't delete $file", %args);
        }
        else {
            $self->audit( "Cannot delete unknown entity: $file" );
        }
    }

    chdir $before;
    return 1;
}

sub cwd_source_dir {
    my $self = shift;
    my $dir = shift or die "missing dir in request\n";
    my %p = validate( @_,
        {   'src'   => { type => SCALAR,  optional => 1, },
            'sudo'  => { type => BOOLEAN, optional => 1, },
            $self->get_std_opts,
        }
    );

    my ( $src, $sudo, ) = ( $p{src}, $p{sudo}, );
    my %args = $self->get_std_args( %p );

    return $self->error( "Something (other than a directory) is at $dir and " .
        "that's my build directory. Please remove it and try again!", %args )
        if ( -e $dir && !-d $dir );

    if ( !-d $dir ) {

        $self->_try_mkdir( $dir ); # use the perl builtin mkdir

        if ( !-d $dir ) {
            $self->audit( "trying again with system mkdir...");
            $self->mkdir_system( dir => $dir, %args);

            if ( !-d $dir ) {
                $self->audit( "trying one last time with $sudo mkdir -p....");
                $self->mkdir_system( dir  => $dir, sudo => 1, %args)
                    or return $self->error("Couldn't create $dir.", %args);
            }
        }
    }

    chdir $dir or return $self->error( "failed to cd to $dir: $!", %args);
    return 1;
}

sub _try_mkdir {
    my ($self, $dir ) = @_;
    mkpath( $dir, 0, oct('0755') )
        or return $self->error( "mkdir $dir failed: $!");
    $self->audit( "created $dir");
    return 1;
}

sub extract_archive {
    my $self = shift;
    my $archive = shift or die "missing archive name";
    my %p = validate( @_, { $self->get_std_opts } );
    my %args = $self->get_std_args( %p );

    my $r;
    my %types = (
        gz  => { bin => 'gunzip',  content => 'gzip',       },
        bz2 => { bin => 'bunzip2', content => 'b(un)?zip2', }, # BSD bunzip2, Linux bzip2
        xz  => { bin => 'xz',      content => 'xz',         },
    );

    if ( !-e $archive ) {
        foreach my $ext ( keys %types, map { 'tar.' . $_ } keys %types ) {
            next if ! -e "$archive.$ext";
            $archive = "$archive.$ext";
            last;
        };
    }
    return $self->error( "file $archive is missing!", %args ) if ! -e $archive;

    $self->audit("found $archive");

    my $type
        = $archive =~ /bz2$/ ? 'bz2'
        : $archive =~ /gz$/  ? 'gz'
        : $archive =~ /xz$/  ? 'xz'
        :  return $self->error( 'unknown archive type', %args);

    # find binaries to inspect and expand the archive
    my $tar  = $self->find_bin( 'tar',  %args );
    my $file = $self->find_bin( 'file', %args );

    # make sure the archive contents match the file extension
    $ENV{PATH} = '/bin:/usr/bin'; # prevent taint checks from barfing on ``
    return $self->error( "$archive not a $type compressed file", %args)
        unless grep ( /$types{$type}{content}/, `$file $archive` );

    my $bin = $self->find_bin( $types{$type}{bin}, %args);

    $self->syscmd( "$bin -c $archive | $tar -xf -" ) or return;

    $self->audit( "extracted $archive" );
    return 1;
}

sub file_delete {
    my $self = shift;
    my $file = shift or die "missing file argument";
    my %p = validate( @_,
        {   'sudo'  => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts,
        }
    );

    my %args = $self->get_std_args( %p );

    return $self->error( "$file does not exist", %args ) if !-e $file;

    if ( -w $file ) {
        $self->audit( "write permission to $file: ok" );

        unlink $file or return $self->error( "failed to delete $file", %args );

        $self->audit( "deleted: $file" );
        return 1;
    }

    if ( !$p{sudo} ) {    # all done
        return -e $file ? undef : 1;
    }

    my $err = "trying with system rm";
    my $rm_command = $self->find_bin( "rm", %args );
    $rm_command .= " -f $file";

    if ( $< != 0 ) {      # we're not running as root
        my $sudo = $self->sudo( %args );
        $rm_command = "$sudo $rm_command";
        $err .= " (sudo)";
    }

    $self->syscmd( $rm_command, %args )
        or return $self->error( $err, %args );

    return -e $file ? 0 : 1;
}

sub file_is_newer {
    my $self = shift;
    my %p = validate( @_,
        {   f1  => { type => SCALAR },
            f2  => { type => SCALAR },
            $self->get_std_opts,
        }
    );

    my ( $file1, $file2 ) = ( $p{f1}, $p{f2} );

    # get file attributes via stat
    # (dev,ino,mode,nlink,uid,gid,rdev,size,atime,mtime,ctime,blksize,blocks)

    $self->audit( "checking age of $file1 and $file2" );

    my $stat1 = stat($file1)->mtime;
    my $stat2 = stat($file2)->mtime;

    $self->audit( "timestamps are $stat1 and $stat2");

    return 1 if ( $stat2 > $stat1 );
    return;

    # I could just:
    #
    # if ( stat($f1)[9] > stat($f2)[9] )
    #
    # but that forces the reader to read the man page for stat
    # to see what's happening
}

sub file_read {
    my $self = shift;
    my $file = shift or return $self->error("missing filename in request");
    my %p = validate(
        @_,
        {   'max_lines'  => { type => SCALAR, optional => 1 },
            'max_length' => { type => SCALAR, optional => 1 },
            $self->get_std_opts
        }
    );

    my ( $max_lines, $max_length ) = ( $p{max_lines}, $p{max_length} );
    my %args = $self->get_std_args( %p );

    return $self->error( "$file does not exist!", %args) if !-e $file;
    return $self->error( "$file is not readable", %args ) if !-r $file;

    open my $FILE, '<', $file or
        return $self->error( "could not open $file: $OS_ERROR", %args );

    my ( $line, @lines );

    if ( ! $max_lines) {
        chomp( @lines = <$FILE> );
        close $FILE;
        return @lines;
# TODO: make max_length work with slurp mode, without doing something ugly like
# reading in the entire line and then truncating it.
    };

    my $i = 0;
    while ( $i < $max_lines ) {
        if ($max_length) { $line = substr <$FILE>, 0, $max_length; }
        else             { $line = <$FILE>; };
        last if ! $line;
        last if eof $FILE;
        push @lines, $line;
        $i++;
    }
    chomp @lines;
    close $FILE;
    return @lines;
}

sub file_mode {
    my $self = shift;
    my %p = validate( @_,
        {   'file'  => { type => SCALAR },
            $self->get_std_opts
        }
    );

    my $file = $p{file};
    my %args = $self->get_std_args( %p );

    return $self->error( "file '$file' does not exist!", %args)
        if !-e $file;

    # one way to get file mode (using File::mode)
    #    my $raw_mode = stat($file)->[2];
    ## no critic
    my $mode = sprintf "%04o", stat($file)->[2] & 07777;

    # another way to get it
    #    my $st = stat($file);
    #    my $mode = sprintf "%lo", $st->mode & 07777;

    $self->audit( "file $file has mode: $mode" );
    return $mode;
}

sub file_write {
    my $self = shift;
    my $file = shift or return $self->error("missing filename in request");
    my %p = validate(
        @_,
        {   'lines'  => { type => ARRAYREF },
            'append' => { type => BOOLEAN, optional => 1, default => 0 },
            'mode'  => { type => SCALAR,  optional => 1 },
            $self->get_std_opts
        }
    );

    my $append = $p{append};
    my $lines  = $p{lines};
    my %args = $self->get_std_args( %p );

    return $self->error( "oops, $file is a directory", %args) if -d $file;
    return $self->error( "oops, $file is not writable", %args )
        if ( ! $self->is_writable( $file, %args) );

    my $m = "wrote";
    my $write_mode = '>';    # (over)write

    if ( $append ) {
        $m = "appended";
        $write_mode = '>>';
        if ( -f $file ) {
            copy $file, "$file.tmp" or return $self->error(
                "couldn't create $file.tmp for safe append", %args );
        };
    };

    open my $HANDLE, $write_mode, "$file.tmp"
        or return $self->error( "file_write: couldn't open $file: $!", %args );

    my $c = 0;
    foreach ( @$lines ) { chomp; print $HANDLE "$_\n"; $c++ };
    close $HANDLE or return $self->error( "couldn't close $file: $!", %args );

    $self->audit( "file_write: $m $c lines to $file", %args );

    move( "$file.tmp", $file )
        or return $self->error("  unable to update $file", %args);

    # set file permissions mode if requested
    $self->chmod( file => $file, mode => $p{mode}, %args )
        or return if $p{mode};

    return 1;
}

sub files_diff {
    my $self = shift;
    my %p = validate(
        @_,
        {   f1    => { type => SCALAR },
            f2    => { type => SCALAR },
            type  => { type => SCALAR,  optional => 1, default => 'text' },
            $self->get_std_opts,
        }
    );

    my ( $f1, $f2, $type ) = ( $p{f1}, $p{f2}, $p{type} );
    my %args = $self->get_std_args(%p);

    if ( !-e $f1 || !-e $f2 ) {
        $self->error( "$f1 or $f2 does not exist!", %args );
        return -1;
    };

    return $self->files_diff_md5( $f1, $f2, \%args)
        if $type ne "text";

### TODO
    # use file here to make sure files are ASCII
    #
    $self->audit("comparing ascii files $f1 and $f2 using diff", %args);

    my $diff = $self->find_bin( 'diff', %args );
    my $r = `$diff $f1 $f2`;
    chomp $r;
    return $r;
};

sub files_diff_md5 {
    my $self = shift;
    my ($f1, $f2, $args) = @_;

    $self->audit("comparing $f1 and $f2 using md5", %$args);

    eval { require Digest::MD5 };
    return $self->error( "couldn't load Digest::MD5!", %$args )
        if $EVAL_ERROR;

    $self->audit( "\t Digest::MD5 loaded", %$args );

    my @md5sums;

    foreach my $f ( $f1, $f2 ) {
        my ( $sum, $changed );

        # if the md5 file exists
        if ( -f "$f.md5" ) {
            $sum = $self->file_read( "$f.md5", %$args );
            $self->audit( "  md5 file for $f exists", %$args );
        }

   # if the md5 file is missing, invalid, or older than the file, recompute it
        if ( ! -f "$f.md5" or $sum !~ /[0-9a-f]+/i or
            $self->file_is_newer( f1 => "$f.md5", f2 => $f, %$args )
            )
        {
            my $ctx = Digest::MD5->new;
            open my $FILE, '<', $f;
            $ctx->addfile(*$FILE);
            $sum = $ctx->hexdigest;
            close $FILE;
            $changed++;
            $self->audit("  calculated md5: $sum", %$args);
        }

        push( @md5sums, $sum );
        $self->file_write( "$f.md5", lines => [$sum], %$args ) if $changed;
    }

    return if $md5sums[0] eq $md5sums[1];
    return 1;
}

sub find_bin {
    my $self = shift;
    my $bin  = shift or die "missing argument to find_bin\n";
    my %p = validate( @_,
        {   'dir'   => { type => SCALAR, optional => 1, },
            $self->get_std_opts,
        },
    );

    my $prefix = "/usr/local";
    my %args = $self->get_std_args(%p);

    if ( $bin =~ /^\// && -x $bin ) {  # we got a full path
        $self->audit( "find_bin: found $bin", %args );
        return $bin;
    };

    my @prefixes;
    push @prefixes, $p{dir} if $p{dir};
    push @prefixes, qw"
        /usr/local/bin /usr/local/sbin/ /opt/local/bin /opt/local/sbin
        $prefix/mysql/bin /bin /usr/bin /sbin /usr/sbin
        ";
    push @prefixes, cwd;

    my $found;
    foreach my $prefix ( @prefixes ) {
        if ( -x "$prefix/$bin" ) {
            $found = "$prefix/$bin" and last;
        };
    };

    if ($found) {
        $self->audit( "find_bin: found $found", %args);
        return $found;
    }

    return $self->error( "find_bin: could not find $bin", %args);
}

sub find_config {
    my $self = shift;
    my $file = shift or die "missing file name";
    my %p = validate( @_,
        {   etcdir => { type => SCALAR | UNDEF, optional => 1, },
            $self->get_std_opts,
        }
    );

    if ( $p{verbose} > 1 ) {
        my @caller = caller;
        $self->audit( sprintf("find_config loaded by %s, %s, %s\n", @caller ));
    };

    $self->audit("find_config: searching for $file");

    my @etc_dirs;
    my $etcdir = $p{etcdir};
    push @etc_dirs, $etcdir if ( $etcdir && -d $etcdir );
    push @etc_dirs, qw{ /opt/local/etc /usr/local/etc /etc etc };
    push @etc_dirs, cwd;

    my $r = $self->find_readable( $file, @etc_dirs );
    if ( $r ) {
        $self->audit( "  found $r" );
        return $r;
    };

    # try $file-dist in the working dir
    if ( -r "./$file-dist" ) {
        $self->audit("  found in ./");
        return cwd . "/$file-dist";
    }

    return $self->error( "could not find $file", fatal => $p{fatal} );
}

sub find_readable {
    my $self = shift;
    my $file = shift;
    my $dir  = shift or return;   # break recursion at end of @_

    #$self->audit("looking for $file in $dir") if $self->{verbose};
    if ( -r "$dir/$file" ) {
        no warnings;
        return "$dir/$file";       # success
    }

    if ( ! -d $dir ) {
        return $self->find_readable( $file, @_ );
    };

    # warn about directories we don't have read access to
    if ( ! -r $dir ) {
        $self->error( "$dir is not readable", fatal => 0 );
        return $self->find_readable( $file, @_ );
    };

    # warn about files that exist but aren't readable
    if ( -e "$dir/$file" ) {
        $self->error( "$dir/$file is not readable", fatal => 0);
    };

    return $self->find_readable( $file, @_ );
}

sub fstab_list {
    my $self = shift;
    my %p = validate( @_, {   $self->get_std_opts, } );

    if ( $OSNAME eq "darwin" ) {
        return ['fstab not used on Darwin!'];
    }

    my $fstab = "/etc/fstab";
    if ( !-e $fstab ) {
        print "fstab_list: FAILURE: $fstab does not exist!\n" if $p{verbose};
        return;
    }

    my $grep = $self->find_bin( "grep", verbose => 0 );
    my @fstabs = `$grep -v cdr $fstab`;

    #	foreach my $fstab (@fstabs)
    #	{}
    #		my @fields = split(/ /, $fstab);
    #		#print "device: $fields[0]  mount: $fields[1]\n";
    #	{};
    #	print "\n\n END of fstabs\n\n";

    return \@fstabs;
}

sub get_cpan_config {

    my $ftp = `which ftp`; chomp $ftp;
    my $gzip = `which gzip`; chomp $gzip;
    my $unzip = `which unzip`; chomp $unzip;
    my $tar  = `which tar`; chomp $tar;
    my $make = `which make`; chomp $make;
    my $wget = `which wget`; chomp $wget;

    return
{
  'build_cache' => q[10],
  'build_dir' => qq[$ENV{HOME}/.cpan/build],
  'cache_metadata' => q[1],
  'cpan_home' => qq[$ENV{HOME}/.cpan],
  'ftp' => $ftp,
  'ftp_proxy' => q[],
  'getcwd' => q[cwd],
  'gpg' => q[],
  'gzip' => $gzip,
  'histfile' => qq[$ENV{HOME}/.cpan/histfile],
  'histsize' => q[100],
  'http_proxy' => q[],
  'inactivity_timeout' => q[5],
  'index_expire' => q[1],
  'inhibit_startup_message' => q[1],
  'keep_source_where' => qq[$ENV{HOME}/.cpan/sources],
  'lynx' => q[],
  'make' => $make,
  'make_arg' => q[],
  'make_install_arg' => q[],
  'makepl_arg' => q[],
  'ncftp' => q[],
  'ncftpget' => q[],
  'no_proxy' => q[],
  'pager' => q[less],
  'prerequisites_policy' => q[follow],
  'scan_cache' => q[atstart],
  'shell' => q[/bin/csh],
  'tar' => $tar,
  'term_is_latin' => q[1],
  'unzip' => $unzip,
  'urllist' => [ 'http://www.perl.com/CPAN/', 'ftp://cpan.cs.utah.edu/pub/CPAN/', 'ftp://mirrors.kernel.org/pub/CPAN', 'ftp://osl.uoregon.edu/CPAN/', 'http://cpan.yahoo.com/' ],
  'wget' => $wget,
};

}

sub get_dir_files {
    my $self = shift;
    my $dir = shift or die "missing dir name";
    my %p = validate( @_, { $self->get_std_opts } );

    my %args = $self->get_std_args( %p );

    my @files;

    return $self->error( "dir $dir is not a directory!", %args)
        if ! -d $dir;

    opendir D, $dir or return $self->error( "couldn't open $dir: $!", %args );

    while ( defined( my $f = readdir(D) ) ) {
        next if $f =~ /^\.\.?$/;
        push @files, "$dir/$f";
    }

    closedir(D);

    return @files;
}

sub get_my_ips {

    ############################################
    # Usage      : @list_of_ips_ref = $util->get_my_ips();
    # Purpose    : get a list of IP addresses on local interfaces
    # Returns    : an arrayref of IP addresses
    # Parameters : only - can be one of: first, last
    #            : exclude_locahost  (all 127.0 addresses)
    #            : exclude_internals (192.168, 10., 169., 172.)
    #            : exclude_ipv6
    # Comments   : exclude options are boolean and enabled by default.
    #              tested on Mac OS X and FreeBSD

    my $self = shift;
    my %p = validate(
        @_,
        {   'only' => { type => SCALAR, optional => 1, default => 0 },
            'exclude_localhost' =>
                { type => BOOLEAN, optional => 1, default => 1 },
            'exclude_internals' =>
                { type => BOOLEAN, optional => 1, default => 1 },
            'exclude_ipv6' =>
                { type => BOOLEAN, optional => 1, default => 1 },
            $self->get_std_opts,
        }
    );

    my $only  = $p{only};

    my $ifconfig = $self->find_bin( "ifconfig", verbose => 0 );

    my $once = 0;

TRY:
    my @ips = grep {/inet/} `$ifconfig`; chomp @ips;
       @ips = grep {!/inet6/} @ips if $p{exclude_ipv6};
       @ips = grep {!/inet 127\.0\.0/} @ips if $p{exclude_localhost};
       @ips = grep {!/inet (192\.168\.|10\.|172\.16\.|169\.254\.)/} @ips
            if $p{exclude_internals};

    # this keeps us from failing if the box has only internal IPs
    if ( @ips < 1 || $ips[0] eq "" ) {
        $self->audit( "yikes, you really don't have any public IPs?!");
        $p{exclude_internals} = 0;
        $once++;
        goto TRY if ( $once < 2 );
    }

    foreach ( @ips ) { ($_) = $_ =~ m/inet ([\d\.]+)\s/; };

    return [ $ips[0]  ] if $only eq 'first';
    return [ $ips[-1] ] if $only eq 'last';
    return \@ips;
}

sub get_the_date {
    my $self = shift;
    my %p = validate(
        @_,
        {   'bump'  => { type => SCALAR,  optional => 1, },
            $self->get_std_opts
        }
    );

    my $bump  = $p{bump} || 0;
    my %args = $self->get_std_args( %p );

    my $time = time;
    my $mess = "get_the_date time: " . time;

    $bump = $bump * 86400 if $bump;
    my $offset_time = time - $bump;
    $mess .= ", (selected $offset_time)" if $time != $offset_time;

    # load Date::Format to get the time2str function
    eval { require Date::Format };
    if ( !$EVAL_ERROR ) {

        my $ss = Date::Format::time2str( "%S", ($offset_time) );
        my $mn = Date::Format::time2str( "%M", ($offset_time) );
        my $hh = Date::Format::time2str( "%H", ($offset_time) );
        my $dd = Date::Format::time2str( "%d", ($offset_time) );
        my $mm = Date::Format::time2str( "%m", ($offset_time) );
        my $yy = Date::Format::time2str( "%Y", ($offset_time) );
        my $lm = Date::Format::time2str( "%m", ( $offset_time - 2592000 ) );

        $self->audit( "$mess, $yy/$mm/$dd $hh:$mn", %args);
        return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
    }

    #  0    1    2     3     4    5     6     7     8
    # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
    #                    localtime(time);
    # 4 = month + 1   ( see perldoc localtime)
    # 5 = year + 1900     ""

    my @fields = localtime($offset_time);

    my $ss = sprintf( "%02i", $fields[0] );    # seconds
    my $mn = sprintf( "%02i", $fields[1] );    # minutes
    my $hh = sprintf( "%02i", $fields[2] );    # hours (24 hour clock)

    my $dd = sprintf( "%02i", $fields[3] );        # day of month
    my $mm = sprintf( "%02i", $fields[4] + 1 );    # month
    my $yy = ( $fields[5] + 1900 );                # year

    $self->audit( "$mess, $yy/$mm/$dd $hh:$mn", %args );
    return $dd, $mm, $yy, undef, $hh, $mn, $ss;
}

sub get_mounted_drives {
    my $self = shift;
    my %p = validate( @_, { $self->get_std_opts } );
    my %args = $self->get_std_args( %p );

    my $mount = $self->find_bin( 'mount', %args );

    -x $mount or return $self->error( "I couldn't find mount!", %args );

    $ENV{PATH} = "";
    my %hash;
    foreach (`$mount`) {
        my ( $d, $m ) = $_ =~ /^(.*) on (.*) \(/;

        #if ( $m =~ /^\// && $d =~ /^\// )  # mount drives that begin with /
        if ( $m && $m =~ /^\// ) {   # only mounts that begin with /
            $self->audit( "adding: $m \t $d" );
            $hash{$m} = $d;
        }
    }
    return \%hash;
}

sub get_url {
    my $self = shift;
    my $url = shift;
    my %p = validate(
        @_,
        {   dir     => { type => SCALAR, optional => 1 },
            timeout => { type => SCALAR, optional => 1 },
            $self->get_std_opts,
        }
    );

    my $dir = $p{dir};
    my %args = $self->get_std_args( %p );

    my ($ua, $response);
    eval "require LWP::Simple"; ## no critic ( StringyEval )
    if ( $EVAL_ERROR ) {
        $self->audit( "LWP::Simple not installed" );
        return $self->get_url_system( $url, %p );
    };

    eval "require URI";  ## no critic ( StringyEval )
    return $self->error( $@, fatal => $p{fatal} ) if $@;
    my $uri = URI->new($url);
    my @parts = $uri->path_segments;
    my $file = $parts[-1];  # everything after the last / in the URL
    my $file_path = $file;
    $file_path = "$dir/$file" if $dir;

    $self->audit( "fetching $url" );
    eval { $response = LWP::Simple::mirror($url, $file_path ); };
    $self->error( $EVAL_ERROR ) if $EVAL_ERROR;

    if ( $response ) {
        if ( $response == 404 ) {
            return $self->error( "file not found ($url)", %args );
        }
        elsif ($response == 304 ) {
            $self->audit( "result 304: file is up-to-date" );
        }
        elsif ( $response == 200 ) {
            $self->audit( "result 200: file download ok" );
        }
        else {
            $self->error( "unhandled response: $response for $url", fatal => 0 );
        };
    };

    $self->error( "download failed for $url!") if ! -e $file_path;
    return $response;
}

sub get_url_system {
    my $self = shift;
    my $url = shift;
    my %p = validate(
        @_,
        {   dir     => { type => SCALAR,  optional => 1 },
            timeout => { type => SCALAR,  optional => 1, },
            $self->get_std_opts,
        }
    );

    my $dir      = $p{dir};
    my $verbose  = $p{verbose};
    my %args = $self->get_std_args( %p );

    my ($fetchbin, $found);
    if ( $OSNAME eq "freebsd" ) {
        $fetchbin = $self->find_bin( 'fetch', %args);
        if ( $fetchbin && -x $fetchbin ) {
            $found = $fetchbin;
            $found .= " -q" if !$verbose;
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        $fetchbin = $self->find_bin( 'curl', %args );
        if ( $fetchbin && -x $fetchbin ) {
            $found = "$fetchbin -O";
            $found .= " -s " if !$verbose;
        }
    }

    if ( !$found ) {
        $fetchbin = $self->find_bin( 'wget', %args);
        $found = $fetchbin if $fetchbin && -x $fetchbin;
    }

    return $self->error( "Failed to fetch $url.\n\tCouldn't find wget. Please install it.", %args )
        if !$found;

    my $fetchcmd = "$found $url";

    my $timeout = $p{timeout} || 0;
    if ( ! $timeout ) {
        $self->syscmd( $fetchcmd, %args ) or return;
        eval "require URI";  ## no critic ( StringyEval )
        return $self->error( $@, fatal => $p{fatal} ) if $@;
        my $uri = URI->new($url);
        my @parts = $uri->path_segments;
        my $file = $parts[-1];  # everything after the last / in the URL
        if ( -e $file && $dir && -d $dir ) {
            $self->audit("moving file $file to $dir" );
            move $file, "$dir/$file";
            return 1;
        };
    };

    my $r;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        $r = $self->syscmd( $fetchcmd, %args );
        alarm 0;
    };

    if ($EVAL_ERROR) {    # propagate unexpected errors
        print "timed out!\n" if $EVAL_ERROR eq "alarm\n";
        return $self->error( $EVAL_ERROR, %args );
    }

    return $self->error( "error executing $fetchcmd", %args) if !$r;
    return 1;
}

sub has_module {
        my $self = shift;
            my ($name, $ver) = @_;

## no critic ( ProhibitStringyEval )
    eval "use $name" . ($ver ? " $ver;" : ";");
## use critic

        !$EVAL_ERROR;
};

sub install_if_changed {
    my $self = shift;
    my %p = validate(
        @_,
        {   newfile => { type => SCALAR, optional => 0, },
            existing=> { type => SCALAR, optional => 0, },
            mode    => { type => SCALAR, optional => 1, },
            uid     => { type => SCALAR, optional => 1, },
            gid     => { type => SCALAR, optional => 1, },
            sudo    => { type => BOOLEAN, optional => 1, default => 0 },
            notify  => { type => BOOLEAN, optional => 1, },
            email   => { type => SCALAR, optional => 1, default => 'postmaster' },
            clean   => { type => BOOLEAN, optional => 1, default => 1 },
            archive => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts,
        },
    );

    my ( $newfile, $existing, $mode, $uid, $gid, $email) = (
        $p{newfile}, $p{existing}, $p{mode}, $p{uid}, $p{gid}, $p{email} );
    my ($sudo, $notify ) = ($p{sudo}, $p{notify} );
    my %args = $self->get_std_args( %p );

    if ( $newfile !~ /\// ) {
        # relative filename given
        $self->audit( "relative filename given, use complete paths "
            . "for more predicatable results!\n"
            . "working directory is " . cwd() );
    }

    return $self->error( "file ($newfile) does not exist", %args )
        if !-e $newfile;

    return $self->error( "file ($newfile) is not a file", %args )
        if !-f $newfile;

    # make sure existing and new are writable
    if (   !$self->is_writable( $existing, fatal => 0 )
        || !$self->is_writable( $newfile,  fatal => 0 ) ) {

        # root does not have permission, sudo won't do any good
        return $self->error("no write permission", %args) if $UID == 0;

        if ( $sudo ) {
            $sudo = $self->find_bin( 'sudo', %args ) or
                return $self->error( "you are not root, sudo was not found, and you don't have permission to write to $newfile or $existing" );
        }
    }

    my $diffie;
    if ( -f $existing ) {
        $diffie = $self->files_diff( %args,
            f1    => $newfile,
            f2    => $existing,
            type  => "text",
        ) or do {
            $self->audit( "$existing is already up-to-date.", %args);
            unlink $newfile if $p{clean};
            return 2;
        };
    };

    $self->audit("checking $existing", %args);

    $self->chown( $newfile,
        uid => $uid,
        gid => $gid,
        sudo => $sudo,
        %args
    )
    if ( $uid && $gid );  # set file ownership on the new file

    # set file permissions on the new file
    $self->chmod(
        file_or_dir => $existing,
        mode        => $mode,
        sudo        => $sudo,
        %args
    )
    if ( -e $existing && $mode );

    $self->install_if_changed_notify( $notify, $email, $existing, $diffie);
    $self->archive_file( $existing, %args) if ( -e $existing && $p{archive} );
    $self->install_if_changed_copy( $sudo, $newfile, $existing, $p{clean}, \%args );

    $self->chown( $existing,
        uid         => $uid,
        gid         => $gid,
        sudo        => $sudo,
        %args
    ) if ( $uid && $gid ); # set ownership on new existing file

    $self->chmod(
        file_or_dir => $existing,
        mode        => $mode,
        sudo        => $sudo,
        %args
    )
    if $mode; # set file permissions (paranoid)

    $self->audit( "  updated $existing" );
    return 1;
}

sub install_if_changed_copy {
    my $self = shift;
    my ( $sudo, $newfile, $existing, $clean, $args ) = @_;

    # install the new file
    if ($sudo) {
        my $cp = $self->find_bin( 'cp', %$args );

        # back up the existing file
        $self->syscmd( "$sudo $cp $existing $existing.bak", %$args)
            if -e $existing;

        # install the new one
        if ( $clean ) {
            my $mv = $self->find_bin( 'mv' );
            $self->syscmd( "$sudo $mv $newfile $existing", %$args);
        }
        else {
            $self->syscmd( "$sudo $cp $newfile $existing",%$args);
        }
    }
    else {

        # back up the existing file
        copy( $existing, "$existing.bak" ) if -e $existing;

        if ( $clean ) {
            move( $newfile, $existing ) or
                return $self->error( "failed move $newfile to $existing", %$args);
        }
        else {
            copy( $newfile, $existing ) or
                return $self->error( "failed copy $newfile to $existing", %$args );
        }
    }
};

sub install_if_changed_notify {

    my ($self, $notify, $email, $existing, $diffie) = @_;

    return if ! $notify;
    return if ! -f $existing;

    # email diffs to admin

    eval { require Mail::Send; };

    return $self->error( "could not send notice, Mail::Send is not installed!", fatal => 0)
        if $EVAL_ERROR;

    my $msg = Mail::Send->new;
    $msg->subject("$existing updated by $0");
    $msg->to($email);
    my $email_message = $msg->open;

    print $email_message "This message is to notify you that $existing has been altered. The difference between the new file and the old one is:\n\n$diffie";

    $email_message->close;
};

sub install_from_source {
    my $self = shift;
    my %p = validate(
        @_,
        {   'site'           => { type => SCALAR,   optional => 0, },
            'url'            => { type => SCALAR,   optional => 0, },
            'package'        => { type => SCALAR,   optional => 0, },
            'targets'        => { type => ARRAYREF, optional => 1, },
            'patches'        => { type => ARRAYREF, optional => 1, },
            'patch_url'      => { type => SCALAR,   optional => 1, },
            'patch_args'     => { type => SCALAR,   optional => 1, },
            'source_dir'     => { type => SCALAR,   optional => 1, },
            'source_sub_dir' => { type => SCALAR,   optional => 1, },
            'bintest'        => { type => SCALAR,   optional => 1, },
            $self->get_std_opts,
        },
    );

    return $p{test_ok} if defined $p{test_ok};
    my %args = $self->get_std_args( %p );

    my ( $site, $url, $package, $targets, $patches, $bintest ) =
        ( $p{site},    $p{url}, $p{package},
          $p{targets}, $p{patches}, $p{bintest} );

    my $patch_args = $p{patch_args} || '';
    my $srcdir = $p{source_dir} || "/usr/local/src";
       $srcdir .= "/$p{source_sub_dir}" if $p{source_sub_dir};

    if ( $bintest && $self->find_bin( $bintest, fatal => 0, verbose => 0 ) ) {
        return if ! $self->yes_or_no(
            "$bintest exists, suggesting that "
                . "$package is installed. Do you want to reinstall?",
            timeout  => 60,
        );
    }

    $self->audit( "install_from_source: building $package in $srcdir" );

    my $original_directory = cwd;
    $self->cwd_source_dir( $srcdir, %args );

    $self->install_from_source_cleanup($package,$srcdir) or return;
    $self->install_from_source_get_files($package,$site,$url,$p{patch_url},$patches) or return;
    $self->extract_archive( $package ) or return;

    # cd into the package directory
    my $sub_path;
    if ( -d $package ) {
        chdir $package or
            return $self->error( "FAILED to chdir $package!", %args );
    }
    else {

       # some packages (like daemontools) unpack within an enclosing directory
        $sub_path = `find ./ -name $package`;       # tainted data
        chomp $sub_path;
        ($sub_path) = $sub_path =~ /^([-\w\/.]+)$/; # untaint it

        $self->audit( "found sources in $sub_path" ) if $sub_path;
        return $self->error( "FAILED to find $package sources!",fatal=>0)
            unless ( -d $sub_path && chdir $sub_path );
    }

    $self->install_from_source_apply_patches($srcdir, $patches, $patch_args) or return;

    # set default build targets if none are provided
    if ( !@$targets[0] ) {
        $self->audit( "\tusing default targets (./configure, make, make install)" );
        @$targets = ( "./configure", "make", "make install" );
    }

    my $msg = "install_from_source: using targets\n";
    foreach (@$targets) { $msg .= "\t$_\n" };
    $self->audit( $msg );

    # build the program
    foreach my $target (@$targets) {

        if ( $target =~ /^cd (.*)$/ ) {
            $self->audit( "cwd: " . cwd . " -> " . $1 );
            chdir($1) or return $self->error( "couldn't chdir $1: $!", %args);
            next;
        }

        $self->syscmd( $target, %args ) or
            return $self->error( "pwd: " . cwd .  "\n$target failed: $!", %args );
    }

    # clean up the build sources
    chdir $srcdir;
    File::Path::rmtree($package) if -d $package;

    if ( defined $sub_path && -d "$package/$sub_path" ) {
        File::Path::rmtree( "$package/$sub_path" );
    };

    chdir $original_directory;
    return 1;
}

sub install_from_source_apply_patches {
    my $self = shift;
    my ($src, $patches,$patch_args) = @_;

    return 1 if ! $patches;
    return 1 if ! $patches->[0];

    my $patchbin = $self->find_bin( "patch" );
    foreach my $patch (@$patches) {
        $self->syscmd( "$patchbin $patch_args < $src/$patch" )
            or return $self->error("failed to apply patch $patch");
    }
    return 1;
};

sub install_from_source_cleanup {
    my $self = shift;
    my ($package,$src) = @_;

    # make sure there are no previous sources in the way
    return 1 if ! -d $package;

    $self->source_warning(
        package => $package,
        clean   => 1,
        src     => $src,
    ) or return $self->error( "OK then, skipping install.", fatal => 0);

    $self->audit( "  removing previous build sources." );
    foreach my $dir ( glob "$package-*" ) {
        File::Path::rmtree( $dir )
            or return $self->error("failed to delete $package: $!");
    };
    return 1;
};

sub install_from_source_get_files {
    my $self = shift;
    my ($package,$site,$url,$patch_url,$patches) = @_;

    $self->sources_get(
        package => $package,
        site    => $site,
        path    => $url,
    ) or return;

    if ( ! $patches || ! $patches->[0] ) {
        $self->audit( "  no patches" );
        return 1;
    };

    return $self->error( "oops! You supplied patch names to apply without a URL!")
        if ! $patch_url;

    foreach my $patch (@$patches) {
        next if ! $patch;
        next if -e $patch;
        $self->get_url( "$patch_url/$patch" );
    };

    return 1;
};

sub install_package {
    my ($self, $app, $info) = @_;

    if ( lc($OSNAME) eq 'freebsd' ) {

        my $portname = $info->{port}
            or return $self->error( "skipping install of $app b/c port dir not set.", fatal => 0);

        require Mail::Toaster::FreeBSD;
        my $freebsd = Mail::Toaster::FreeBSD->new;
        if ( $freebsd->is_port_installed( $app ) ) {
            print "$app is installed.\n";
            return 1;
        }

        print "installing $app\n";
        my $portdir = glob("/usr/ports/*/$portname");

        return $self->error( "oops, couldn't find port $app at '$portname'")
            if ( ! -d $portdir || ! chdir $portdir );

        system "make install clean"
            and return $self->error( "'make install clean' failed for port $app", fatal => 0);
        return 1;
    };

    if ( lc($OSNAME) eq 'linux' ) {
        my $rpm = $info->{rpm} or return $self->error("skipping install of $app b/c rpm not set", fatal => 0);
        my $yum = '/usr/bin/yum';
        return $self->error( "couldn't find yum, skipping install.", fatal => 0)
            if ! -x $yum;
        return system "$yum install $rpm";
    };

    $self->error(" no package support for $OSNAME ");
}

sub install_module {
    my ($self, $module, %info) = @_;

    if ( lc($OSNAME) eq 'darwin' ) {
        $self->install_module_darwin( $module ) and return 1;
    }
    elsif ( lc($OSNAME) eq 'freebsd' ) {
        $self->install_module_freebsd( $module, \%info) and return 1;
    }
    elsif ( lc($OSNAME) eq 'linux' ) {
        $self->install_module_linux( $module, \%info) and return 1;
    };

    $self->install_module_cpan( $module );

    eval "use $module";   ## no critic ( StringyEval )
    if ( ! $EVAL_ERROR ) {
        $self->audit( "$module is installed." );
        return 1;
    };
    return;
}

sub install_module_cpan {
    my $self = shift;
    my ($module, $version) = @_;

    print " from CPAN...";
    require CPAN;

    # some Linux distros break CPAN by auto/preconfiguring it with no URL mirrors.
    # this works around that annoying little habit
    no warnings;
    $CPAN::Config = get_cpan_config();
    use warnings;

    if ( $module eq 'Provision::Unix' && $version ) {
        $module =~ s/\:\:/\-/g;
        $module = "M/MS/MSIMERSON/$module-$version.tar.gz";
    }
    CPAN::Shell->install($module);
}

sub install_module_darwin {
    my $self = shift;
    my $module = shift;

    my $dport = '/opt/local/bin/port';
    return $self->error( "Darwin ports is not installed!", fatal => 0)
        if ! -x $dport;

    my $port = lc "p5-$module";
    $port =~ s/::/-/g;
    system "sudo $dport install $port" or return 1;
    return;
};

sub install_module_freebsd {
    my $self = shift;
    my ($module, $info) = @_;

    my $portname = $info->{port}; # optional override
    if ( ! $portname ) {
        $portname = "p5-$module";
        $portname =~ s/::/-/g;
    };

    return 1 if $self->freebsd->is_port_installed( $portname );
    return 1 if $self->freebsd->install_package( $portname );

    my $portdir = glob("/usr/ports/*/$portname");
    return if ! $portdir;
    return if ! -d $portdir;

    $self->audit( "installing $module from ports ($portdir)" );
    system "make -C $portdir clean install clean";
    return 1;
}

sub install_module_from_src {
    my $self = shift;
    my %p = validate( @_, {
            module  => { type=>SCALAR,  optional=>0, },
            archive => { type=>SCALAR,  optional=>0, },
            site    => { type=>SCALAR,  optional=>0, },
            url     => { type=>SCALAR,  optional=>0, },
            src     => { type=>SCALAR,  optional=>1, default=>'/usr/local/src' },
            targets => { type=>ARRAYREF,optional=>1, },
            $self->get_std_opts,
        },
    );

    my ( $module, $site, $url, $src, $targets )
        = ( $p{module}, $p{site}, $p{url}, $p{src}, $p{targets} );
    my %args = $self->get_std_args( %p );

    $self->cwd_source_dir( $src, %args );

    $self->audit( "checking for previous build attempts.");
    if ( -d $module ) {
        if ( ! $self->source_warning( package=>$module, src=>$src, %args ) ) {
            print "\nokay, skipping install.\n";
            return;
        }
        File::Path::rmtree( "$module" ) or die $!;
    }

    $self->sources_get(
        site    => $site,
        path    => $url,
        package => $p{'archive'} || $module,
        %args,
    ) or return;

    $self->extract_archive( $module ) or return;

    my $found;
    print "looking for $module in $src...";
    foreach my $file ( $self->get_dir_files( $src ) ) {

        next if ! -d $file;  # only check directories
        next if $file !~ /$module/;

        print "found: $file\n";
        $found++;
        chdir $file;

        unless ( @$targets[0] && @$targets[0] ne "" ) {
            $self->audit( "using default targets." );
            $targets = [ "perl Makefile.PL", "make", "make install" ];
        }

        print "building with targets " . join( ", ", @$targets ) . "\n";
        foreach (@$targets) {
            return $self->error( "$_ failed!", %args)
                if ! $self->syscmd( cmd => $_ , %args);
        }

        chdir('..');
        File::Path::rmtree( $file ) or die $!;
        last;
    }

    return $found;
}

sub install_module_linux {
    my $self = shift;
    my ($module, $info ) = @_;
    my $rpm = $info->{rpm};
    if ( $rpm ) {
        my $portname = "perl-$rpm";
        $portname =~ s/::/-/g;
        my $yum = '/usr/bin/yum';
        system "$yum -y install $portname" if -x $yum;
    }
};

sub is_interactive {

    ## no critic
    # borrowed from IO::Interactive
    my $self = shift;
    my ($out_handle) = ( @_, select );    # Default to default output handle

    # Not interactive if output is not to terminal...
    return if not -t $out_handle;

    # If *ARGV is opened, we're interactive if...
    if ( openhandle * ARGV ) {

        # ...it's currently opened to the magic '-' file
        return -t *STDIN if defined $ARGV && $ARGV eq '-';

        # ...it's at end-of-file and the next file is the magic '-' file
        return @ARGV > 0 && $ARGV[0] eq '-' && -t *STDIN if eof *ARGV;

        # ...it's directly attached to the terminal
        return -t *ARGV;
    };

   # If *ARGV isn't opened, it will be interactive if *STDIN is attached
   # to a terminal and either there are no files specified on the command line
   # or if there are files and the first is the magic '-' file
    return -t *STDIN && ( @ARGV == 0 || $ARGV[0] eq '-' );
}

sub is_process_running {
    my ( $self, $process ) = @_;

    my $ps   = $self->find_bin( 'ps', verbose => 0 );

    if    ( lc($OSNAME) =~ /solaris/i ) { $ps .= ' -ef';  }
    elsif ( lc($OSNAME) =~ /irix/i    ) { $ps .= ' -ef';  }
    elsif ( lc($OSNAME) =~ /linux/i   ) { $ps .= ' -efw'; }
    else                                { $ps .= ' axww'; };

    my @procs = `$ps`;
    chomp @procs;
    return scalar grep {/$process/i} @procs;
}

sub is_readable {
    my $self = shift;
    my $file = shift or die "missing file or dir name\n";
    my %p = validate( @_, { $self->get_std_opts } );

    my %args = ( verbose => $p{verbose}, fatal => $p{fatal} );

    -e $file or return $self->error( "$file does not exist.", %args);
    -r $file or return $self->error( "$file is not readable by you ("
            . getpwuid($>)
            . "). You need to fix this, using chown or chmod.", %args);

    return 1;
}

sub is_writable {
    my $self = shift;
    my $file = shift or die "missing file or dir name\n";

    my %p = validate( @_, { $self->get_std_opts } );
    my %args = $self->get_std_args( %p );

    my $nl = "\n";
    $nl = "<br>" if ( $ENV{GATEWAY_INTERFACE} );

    if ( !-e $file ) {

        my ( $base, $path, $suffix ) = fileparse($file);

        return $self->error( "is_writable: $path not writable by "
            . getpwuid($>)
            . "$nl$nl", %args) if (-e $path && !-w $path);
        return 1;
    }

    return $self->error( "  $file not writable by " . getpwuid($>) . "$nl$nl", frames=>2, %args ) if ! -w $file;

    $self->audit( "$file is writable" );
    return 1;
}

sub logfile_append {
    my $self = shift;
    my $file = shift or croak "missing filename!";
    my %p = validate( @_,
        {   'lines' => { type => ARRAYREF, optional => 0, },
            'prog'  => { type => BOOLEAN,  optional => 1, default => 0, },
            $self->get_std_opts,
        },
    );

    my $lines = $p{lines};
    my %args = $self->get_std_args( %p );

    my ( $dd, $mm, $yy, $lm, $hh, $mn, $ss ) = $self->get_the_date( %args );

    open my $LOG_FILE, '>>', $file
        or return $self->error( "couldn't open $file: $OS_ERROR", %args);

    print $LOG_FILE "$yy-$mm-$dd $hh:$mn:$ss $p{prog} ";

    my $i;
    foreach (@$lines) { print $LOG_FILE "$_ "; $i++ }

    print $LOG_FILE "\n";
    close $LOG_FILE;

    $self->audit( "logfile_append wrote $i lines to $file", %args );
    return 1;
}

sub mail_toaster {
    my $self = shift;
    $self->install_module( 'Mail::Toaster' );
}

sub mkdir_system {
    my $self = shift;
    my %p = validate(
        @_,
        {   'dir'   => { type => SCALAR,  optional => 0, },
            'mode'  => { type => SCALAR,  optional => 1, },
            'sudo'  => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts,
        }
    );

    my ( $dir, $mode ) = ( $p{dir}, $p{mode} );
    my %args = $self->get_std_args( %p );

    return $self->audit( "mkdir_system: $dir already exists.") if -d $dir;

    my $mkdir = $self->find_bin( 'mkdir', %args) or return;

    # if we are root, just do it (no sudo nonsense)
    if ( $< == 0 ) {
        $self->syscmd( "$mkdir -p $dir", %args) or return;
        $self->chmod( dir => $dir, mode => $mode, %args ) if $mode;

        return 1 if -d $dir;
        return $self->error( "failed to create $dir", %args);
    }

    if ( $p{sudo} ) {
        my $sudo = $self->sudo();

        $self->audit( "trying $sudo $mkdir -p $dir");
        $self->syscmd( "$sudo $mkdir -p $dir", %args);

        $self->audit( "setting ownership to $<.");
        my $chown = $self->find_bin( 'chown', %args);
        $self->syscmd( "$sudo $chown $< $dir", %args);

        $self->chmod( dir => $dir, mode => $mode, sudo => $sudo, %args)
            if $mode;
        return -d $dir ? 1 : 0;
    }

    $self->audit( "trying mkdir -p $dir" );

    # no root and no sudo, just try and see what happens
    $self->syscmd( "$mkdir -p $dir", %args ) or return;

    $self->chmod( dir => $dir, mode => $mode, %args) if $mode;

    return $self->audit( "mkdir_system created $dir" ) if -d $dir;
    return $self->error( '', %args );
}

sub path_parse {
    my $self = shift;
    my $dir = shift or die "missing dir!";
    # code left here for reference, use File::Basename instead

    # if it ends with a /, chop if off
    if ( $dir =~ q{/$} ) { chop $dir }

    # get the position of the last / in the path
    my $rindex = rindex( $dir, "/" );

    # grabs everything up to the last /
    my $updir = substr( $dir, 0, $rindex );
    $rindex++;

    # matches from the last / char +1 to the end of string
    my $curdir = substr( $dir, $rindex );

    return $updir, $curdir;
}

sub check_pidfile {
    my $self = shift;
    my $file = shift;
    my %p = validate( @_, { $self->get_std_opts } );
    my %args = $self->get_std_args( %p );

    return $self->error( "missing filename", %args) if ! $file;
    return $self->error( "$file is not a regular file", %args)
        if ( -e $file && !-f $file );

    # test if file & enclosing directory is writable, revert to /tmp if not
    $self->is_writable( $file, %args)
        or do {
            my ( $base, $path, $suffix ) = fileparse($file);
            $self->audit( "NOTICE: using /tmp for file, $path is not writable!", %args);
            $file = "/tmp/$base";
        };

    # if it does not exist
    if ( !-e $file ) {
        $self->audit( "writing process id $PROCESS_ID to $file...");
        $self->file_write( $file, lines => [$PROCESS_ID], %args) and return $file;
    };

    my $age = time() - stat($file)->mtime;

    if ( $age < 1200 ) {    # less than 20 minutes old
        return $self->error( "check_pidfile: $file is " . $age / 60
            . " minutes old and might still be running. If it is not running,"
            . " please remove the file (rm $file).", %args);
    }
    elsif ( $age < 3600 ) {    # 1 hour
        return $self->error( "check_pidfile: $file is " . $age / 60
            . " minutes old and might still be running. If it is not running,"
            . " please remove the pidfile. (rm $file)", %args);
    }
    else {
        $self->audit( "check_pidfile: $file is $age seconds old, ignoring.", %args);
    }

    return $file;
}

sub parse_config {
    my $self = shift;
    my $file = shift or die "missing file name";
    my %p = validate( @_, {
            etcdir => { type=>SCALAR,  optional=>1, },
            $self->get_std_opts,
        },
    );

    my %args = $self->get_std_args( %p );

    if ( ! -f $file ) { $file = $self->find_config( $file, %args ); };

    if ( ! $file || ! -r $file ) {
        return $self->error( "could not find config file!", %args);
    };

    my %hash;
    $self->audit( "  read config from $file");

    my @config = $self->file_read( $file );
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

sub provision_unix {
    my $self = shift;
    $self->install_module( 'Provision::Unix' );
}

sub regexp_test {
    my $self = shift;
    my %p = validate(
        @_,
        {   'exp'    => { type => SCALAR },
            'string' => { type => SCALAR },
            'pbp'    => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts,
        },
    );

    my $verbose = $p{verbose};
    my ( $exp, $string, $pbp ) = ( $p{exp}, $p{string}, $p{pbp} );

    if ($pbp) {
        if ( $string =~ m{($exp)}xms ) {
            print "\t Matched pbp: |$`<$&>$'|\n" if $verbose;
            return $1;
        }
        else {
            print "\t No match.\n" if $verbose;
            return;
        }
    }

    if ( $string =~ m{($exp)} ) {
        print "\t Matched: |$`<$&>$'|\n" if $verbose;
        return $1;
    }

    print "\t No match.\n" if $verbose;
    return;
}

sub sources_get {
    my $self = shift;
    my %p = validate(
        @_,
        {   'package' => { type => SCALAR,  optional => 0 },
            site      => { type => SCALAR,  optional => 0 },
            path      => { type => SCALAR,  optional => 1 },
            $self->get_std_opts,
        },
    );

    my ( $package, $site, $path ) = ( $p{package}, $p{site}, $p{path} );
    my %args = $self->get_std_args( %p );

    $self->audit( "sources_get: fetching $package from site $site\n\t path: $path");

    my @extensions = qw/ tar.gz tgz tar.bz2 tbz2 /;

    my $filet = $self->find_bin( 'file', %args) or return;
    my $grep  = $self->find_bin( 'grep', %args) or return;

    foreach my $ext (@extensions) {

        my $tarball = "$package.$ext";
        next if !-e $tarball;
        $self->audit( " found $tarball!") if -e $tarball;

        if (`$filet $tarball | $grep compress`) {
            $self->yes_or_no( "$tarball exists, shall I use it?: ")
                and return $self->audit( "  ok, using existing archive: $tarball");
        }

        $self->file_delete( $tarball, %args );
    }

    foreach my $ext (@extensions) {
        my $tarball = "$package.$ext";

        $self->audit( "sources_get: fetching ".$site . $path.'/'.$tarball);

        $self->get_url( "$site$path/$tarball", fatal => 0)
            or return $self->error( "couldn't fetch $site$path/$tarball", %args);

        next if ! -e $tarball;

        $self->audit( "  sources_get: testing $tarball ");

        if (`$filet $tarball | $grep zip`) {
            $self->audit( "  sources_get: looks good!");
            return 1;
        };

        $self->audit( "  oops, is not [b|g]zipped data!");
        $self->file_delete( $tarball, %args);
    }

    return $self->error( "unable to get $package", %args );
}

sub source_warning {
    my $self = shift;
    my %p = validate(
        @_,
        {   'package' => { type => SCALAR, },
            'clean'   => { type => BOOLEAN, optional => 1, default => 1 },
            'src' => {
                type     => SCALAR,
                optional => 1,
                default  => "/usr/local/src"
            },
            'timeout' => { type => SCALAR,  optional => 1, default => 60 },
            $self->get_std_opts,
        },
    );

    my ( $package, $src ) = ( $p{package}, $p{src} );
    my %args = $self->get_std_args( %p );

    return $self->audit( "$package sources not present.", %args ) if !-d $package;

    if ( -e $package ) {
        print "
	$package sources are already present, indicating that you've already
	installed $package. If you want to reinstall it, remove the existing
	sources (rm -r $src/$package) and re-run this script\n\n";
        return if !$p{clean};
    }

    if ( !$self->yes_or_no( "\n\tMay I remove the sources for you?", timeout => $p{timeout} ) ) {
        print "\nskipping $package install.\n\n";
        return;
    };

    $self->audit( "  wd: " . cwd );
    $self->audit( "  deleting $src/$package");

    return $self->error( "failed to delete $package: $OS_ERROR", %args )
        if ! rmtree "$src/$package";
    return 1;
}

sub sudo {
    my $self = shift;
    my %p = validate( @_, { $self->get_std_opts } );

    # if we are running as root via $<
    if ( $REAL_USER_ID == 0 ) {
        $self->audit( "sudo: you are root, sudo isn't necessary.");
        return '';    # return an empty string, purposefully
    }

    my $sudo;
    my $path_to_sudo = $self->find_bin( 'sudo', fatal => 0 );

    # sudo is installed
    if ( $path_to_sudo && -x $path_to_sudo ) {
        $self->audit( "sudo: sudo was found at $path_to_sudo.");
        return "$path_to_sudo -p 'Password for %u@%h:'";
    }

    $self->audit( "\nWARNING: Couldn't find sudo. This may not be a problem but some features require root permissions and will not work without them. Having sudo can allow legitimate and limited root permission to non-root users. Some features of Mail::Toaster may not work as expected without it.\n");

    # try installing sudo
    $self->yes_or_no( "may I try to install sudo?", timeout => 20 ) or do {
        print "very well then, skipping along.\n";
        return "";
    };

    -x $self->find_bin( "sudo", fatal => 0 ) or
        $self->install_from_source(
            package => 'sudo-1.6.9p17',
            site    => 'http://www.courtesan.com',
            url     => '/sudo/',
            targets => [ './configure', 'make', 'make install' ],
            patches => '',
            verbose => 1,
        );

    # can we find it now?
    $path_to_sudo = $self->find_bin( "sudo" );

    if ( !-x $path_to_sudo ) {
        print "sudo install failed!";
        return '';
    }

    return "$path_to_sudo -p 'Password for %u@%h:'";
}

sub syscmd {
    my $self = shift;
    my $cmd = shift or die "missing command!\n";
    my %p = validate(
        @_,
        {   'timeout' => { type => SCALAR, optional => 1 },
            $self->get_std_opts,
        },
    );

    my %args  = $self->get_std_args( %p );

    $self->audit("syscmd: $cmd");

    my ( $is_safe, $tainted, $bin, @args );

    # separate the program from its arguments
    if ( $cmd =~ m/\s+/xm ) {
        ($cmd) = $cmd =~ /^\s*(.*?)\s*$/; # trim lead/trailing whitespace
        @args = split /\s+/, $cmd;  # split on whitespace
        $bin = shift @args;
        $is_safe++;
        $self->audit("\tprogram: $bin, args : " . join ' ', @args, %args);
    }
    else {
        # does not not contain a ./ pattern
        if ( $cmd !~ m{\./} ) { $bin = $cmd; $is_safe++; };
    }

    if ( $is_safe && !$bin ) {
        return $self->error("command is not safe! BAILING OUT!", %args);
    }

    my $message;
    $message .= "syscmd: bin is <$bin>" if $bin;
    $message .= " (safe)" if $is_safe;
    $self->audit($message, %args );

    if ( $bin && !-e $bin ) {  # $bin is set, but we have not found it
        $bin = $self->find_bin( $bin, fatal => 0, verbose => 0 )
            or return $self->error( "$bin was not found", %args);
    }
    unshift @args, $bin;

    require Scalar::Util;
    $tainted++ if Scalar::Util::tainted($cmd);

    my $before_path = $ENV{PATH};

    # instead of croaking, maybe try setting a
    # very restrictive PATH?  I'll err on the side of safety
    # $ENV{PATH} = '';
    return $self->error( "syscmd request has tainted data", %args)
        if ( $tainted && !$is_safe );

    if ($is_safe) {
        my $prefix = "/usr/local";   # restrict the path
        $prefix = "/opt/local" if -d "/opt/local";
        $ENV{PATH} = "/bin:/sbin:/usr/bin:/usr/sbin:$prefix/bin:$prefix/sbin";
    }

    my $r;
    eval {
        if ( defined $p{timeout} ) {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $p{timeout};
        };
        #$r = system $cmd;
        $r = `$cmd 2>&1`;
        alarm 0 if defined $p{timeout};
    };

    if ($EVAL_ERROR) {
        if ( $EVAL_ERROR eq "alarm\n" ) {
            $self->audit("timed out");
        }
        else {
            return $self->error( "unknown error '$EVAL_ERROR'", %args);
        }
    }
    $ENV{PATH} = $before_path;   # set PATH back to original value

    my @caller = caller;
    return $self->syscmd_exit_code( $r, $CHILD_ERROR, \@caller, \%args  );
}

sub syscmd_exit_code {
    my $self = shift;
    my ($r, $err, $caller, $args) = @_;

    $self->audit( "r: $r" );

    my $exit_code = sprintf ("%d", $err >> 8);
    return 1 if $exit_code == 0; # success

    #print 'error # ' . $ERRNO . "\n";   # $! == $ERRNO
    $self->error( "$err: $r",fatal=>0);

    if ( $err == -1 ) {     # check $? for "normal" errors
        $self->error( "failed to execute: $ERRNO", fatal=>0);
    }
    elsif ( $err & 127 ) {  # check for core dump
        printf "child died with signal %d, %s coredump\n", ( $? & 127 ),
            ( $? & 128 ) ? 'with' : 'without';
    }

    return $self->error( "$err: $r", location => join( ", ", @$caller ), %$args );
};

sub yes_or_no {
    my $self = shift;
    my $question = shift;
    my %p = validate(
        @_,
        {   'timeout'  => { type => SCALAR,  optional => 1 },
            'force'    => { type => BOOLEAN, optional => 1, default => 0 },
            $self->get_std_opts
        },
    );


    # for 'make test' testing
    return 1 if $question eq "test";

    # force if interactivity testing is not working properly.
    if ( !$p{force} && !$self->is_interactive ) {
        carp "not running interactively, can't prompt!";
        return;
    }

    my $response;

    print "\nYou have $p{timeout} seconds to respond.\n" if $p{timeout};
    print "\n\t\t$question";

    # I wish I knew why this is not working correctly
    #	eval { local $SIG{__DIE__}; require Term::ReadKey };
    #	if ($@) { #
    #		require Term::ReadKey;
    #		Term::ReadKey->import();
    #		print "yay, Term::ReadKey is present! Are you pleased? (y/n):\n";
    #		use Term::Readkey;
    #		ReadMode 4;
    #		while ( not defined ($key = ReadKey(-1)))
    #		{ # no key yet }
    #		print "Got key $key\n";
    #		ReadMode 0;
    #	};

    if ( $p{timeout} ) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $p{timeout};
            do {
                print "(y/n): ";
                $response = lc(<STDIN>);
                chomp($response);
            } until ( $response eq "n" || $response eq "y" );
            alarm 0;
        };

        if ($@) {
            $@ eq "alarm\n" ? print "timed out!\n" : carp;
        }

        return ($response && $response eq "y") ? 1 : 0;
    }

    do {
        print "(y/n): ";
        $response = lc(<STDIN>);
        chomp($response);
    } until ( $response eq "n" || $response eq "y" );

    return ($response eq "y") ? 1 : 0;
}

1;
__END__
sub {}; # for vim autofold


=head1 SYNOPSIS

  use Mail::Toaster::Utility;
  my $toaster = Mail::Toaster::Utility->new;

  $util->file_write($file, lines=> @lines);

This is just one of the many handy little methods I have amassed here. Rather than try to remember all of the best ways to code certain functions and then attempt to remember them, I have consolidated years of experience and countless references from Learning Perl, Programming Perl, Perl Best Practices, and many other sources into these subroutines.


=head1 DESCRIPTION

This Mail::Toaster::Utility package is my most frequently used one. Each method has its own documentation but in general, all methods accept as input a hashref with at least one required argument and a number of optional arguments.


=head1 DIAGNOSTICS

All methods set and return error codes (0 = fail, 1 = success) unless otherwise stated.

Unless otherwise mentioned, all methods accept two additional parameters:

  verbose - to print status and verbose error messages, set verbose=>1.
  fatal - die on errors. This is the default, set fatal=>0 to override.


=head1 DEPENDENCIES

  Perl.
  Scalar::Util -  built-in as of perl 5.8

Almost nothing else. A few of the methods do require certian things, like extract_archive requires tar and file. But in general, this package (Mail::Toaster::Utility) should run flawlessly on any UNIX-like system. Because I recycle this package in other places (not just Mail::Toaster), I avoid creating dependencies here.

=head1 METHODS

=over


=item new

To use any of the methods below, you must first create a utility object. The methods can be accessed via the utility object.

  ############################################
  # Usage      : use Mail::Toaster::Utility;
  #            : my $util = Mail::Toaster::Utility->new;
  # Purpose    : create a new Mail::Toaster::Utility object
  # Returns    : a bona fide object
  # Parameters : none
  ############################################


=item ask


Get a response from the user. If the user responds, their response is returned. If not, then the default response is returned. If no default was supplied, 0 is returned.

  ############################################
  # Usage      :  my $ask = $util->ask( "Would you like fries with that",
  #  		           default  => "SuperSized!",
  #  		           timeout  => 30
  #               );
  # Purpose    : prompt the user for information
  #
  # Returns    : S - the users response (if not empty) or
  #            : S - the default ask or
  #            : S - an empty string
  #
  # Parameters
  #   Required : S - question - what to ask
  #   Optional : S - default  - a default answer
  #            : I - timeout  - how long to wait for a response
  # Throws     : no exceptions
  # See Also   : yes_or_no


=item extract_archive


Decompresses a variety of archive formats using your systems built in tools.

  ############### extract_archive ##################
  # Usage      : $util->extract_archive( 'example.tar.bz2' );
  # Purpose    : test the archiver, determine its contents, and then
  #              use the best available means to expand it.
  # Returns    : 0 - failure, 1 - success
  # Parameters : S - archive - a bz2, gz, or tgz file to decompress


=item cwd_source_dir


Changes the current working directory to the supplied one. Creates it if it does not exist. Tries to create the directory using perl's builtin mkdir, then the system mkdir, and finally the system mkdir with sudo.

  ############ cwd_source_dir ###################
  # Usage      : $util->cwd_source_dir( "/usr/local/src" );
  # Purpose    : prepare a location to build source files in
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - dir - a directory to build programs in


=item check_homedir_ownership

Checks the ownership on all home directories to see if they are owned by their respective users in /etc/password. Offers to repair the permissions on incorrectly owned directories. This is useful when someone that knows better does something like "chown -R user /home /user" and fouls things up.

  ######### check_homedir_ownership ############
  # Usage      : $util->check_homedir_ownership();
  # Purpose    : repair user homedir ownership
  # Returns    : 0 - failure,  1 - success
  # Parameters :
  #   Optional : I - auto - no prompts, just fix everything
  # See Also   : sysadmin

Comments: Auto mode should be run with great caution. Run it first to see the results and then, if everything looks good, run in auto mode to do the actual repairs.


=item chown_system

The advantage this sub has over a Pure Perl implementation is that it can utilize sudo to gain elevated permissions that we might not otherwise have.


  ############### chown_system #################
  # Usage      : $util->chown_system( dir=>"/tmp/example", user=>'matt' );
  # Purpose    : change the ownership of a file or directory
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - dir    - the directory to chown
  #            : S - user   - a system username
  #   Optional : S - group  - a sytem group name
  #            : I - recurse - include all files/folders in directory?
  # Comments   : Uses the system chown binary
  # See Also   : n/a


=item clean_tmp_dir


  ############## clean_tmp_dir ################
  # Usage      : $util->clean_tmp_dir( $dir );
  # Purpose    : clean up old build stuff before rebuilding
  # Returns    : 0 - failure,  1 - success
  # Parameters : S - $dir - a directory or file.
  # Throws     : die on failure
  # Comments   : Running this will delete its contents. Be careful!


=item get_mounted_drives

  ############# get_mounted_drives ############
  # Usage      : my $mounts = $util->get_mounted_drives();
  # Purpose    : Uses mount to fetch a list of mounted drive/partitions
  # Returns    : a hashref of mounted slices and their mount points.


=item archive_file


  ############### archive_file #################
  # Purpose    : Make a backup copy of a file by copying the file to $file.timestamp.
  # Usage      : my $archived_file = $util->archive_file( $file );
  # Returns    : the filename of the backup file, or 0 on failure.
  # Parameters : S - file - the filname to be backed up
  # Comments   : none


=item chmod

Set the permissions (ugo-rwx) of a file. Will use the native perl methods (by default) but can also use system calls and prepend sudo if additional permissions are needed.

  $util->chmod(
		file_or_dir => '/etc/resolv.conf',
		mode => '0755',
		sudo => $sudo
  )

 arguments required:
   file_or_dir - a file or directory to alter permission on
   mode   - the permissions (numeric)

 arguments optional:
   sudo  - the output of $util->sudo

 result:
   0 - failure
   1 - success


=item chown

Set the ownership (user and group) of a file. Will use the native perl methods (by default) but can also use system calls and prepend sudo if additional permissions are needed.

  $util->chown(
		file_or_dir => '/etc/resolv.conf',
		uid => 'root',
		gid => 'wheel',
		sudo => 1
  );

 arguments required:
   file_or_dir - a file or directory to alter permission on
   uid   - the uid or user name
   gid   - the gid or group name

 arguments optional:
   file  - alias for file_or_dir
   dir   - alias for file_or_dir
   sudo  - the output of $util->sudo

 result:
   0 - failure
   1 - success


=item file_delete

  ############################################
  # Usage      : $util->file_delete( $file );
  # Purpose    : Deletes a file.
  # Returns    : 0 - failure, 1 - success
  # Parameters
  #   Required : file - a file path
  # Comments   : none
  # See Also   :

 Uses unlink if we have appropriate permissions, otherwise uses a system rm call, using sudo if it is not being run as root. This sub will try very hard to delete the file!


=item get_url

   $util->get_url( $url, verbose=>1 );

Use the standard URL fetching utility (fetch, curl, wget) for your OS to download a file from the $url handed to us.

 arguments required:
   url - the fully qualified URL

 arguments optional:
   timeout - the maximum amount of time to try

 result:
   1 - success
   0 - failure


=item file_is_newer

compares the mtime on two files to determine if one is newer than another.


=item file_mode

 usage:
   my @lines = "1", "2", "3";  # named array
   $util->file_write ( "/tmp/foo", lines=>\@lines );
        or
   $util->file_write ( "/tmp/foo", lines=>['1','2','3'] );  # anon arrayref

 required arguments:
   mode - the files permissions mode

 result:
   0 - failure
   1 - success


=item file_read

Reads in a file, and returns it in an array. All lines in the array are chomped.

   my @lines = $util->file_read( $file, max_lines=>100 )

 arguments required:
   file - the file to read in

 arguments optional:
   max_lines  - integer - max number of lines
   max_length - integer - maximum length of a line

 result:
   0 - failure
   success - returns an array with the files contents, one line per array element


=item file_write

 usage:
   my @lines = "1", "2", "3";  # named array
   $util->file_write ( "/tmp/foo", lines=>\@lines );
        or
   $util->file_write ( "/tmp/foo", lines=>['1','2','3'] );  # anon arrayref

 required arguments:
   file - the file path you want to write to
   lines - an arrayref. Each array element will be a line in the file

 result:
   0 - failure
   1 - success


=item files_diff

Determine if the files are different. $type is assumed to be text unless you set it otherwise. For anthing but text files, we do a MD5 checksum on the files to determine if they are different or not.

   $util->files_diff( f1=>$file1,f2=>$file2,type=>'text',verbose=>1 );

   if ( $util->files_diff( f1=>"foo", f2=>"bar" ) )
   {
       print "different!\n";
   };

 required arguments:
   f1 - the first file to compare
   f2 - the second file to compare

 arguments optional:
   type - the type of file (text or binary)

 result:
   0 - files are the same
   1 - files are different
  -1 - error.


=item find_bin

Check all the "normal" locations for a binary that should be on the system and returns the full path to the binary.

   $util->find_bin( 'dos2unix', dir=>'/opt/local/bin' );

Example:

   my $apachectl = $util->find_bin( "apachectl", dir=>"/usr/local/sbin" );


 arguments required:
   bin - the name of the program (its filename)

 arguments optional:
   dir - a directory to check first

 results:
   0 - failure
   success will return the full path to the binary.


=item find_config

This sub is called by several others to determine which configuration file to use. The general logic is as follows:

  If the etc dir and file name are provided and the file exists, use it.

If that fails, then go prowling around the drive and look in all the usual places, in order of preference:

  /opt/local/etc/
  /usr/local/etc/
  /etc

Finally, if none of those work, then check the working directory for the named .conf file, or a .conf-dist.

Example:
  my $twconf = $util->find_config ( 'toaster-watcher.conf',
      etcdir => '/usr/local/etc',
    )

 arguments required:
   file - the .conf file to read in

 arguments optional:
   etcdir - the etc directory to prefer

 result:
   0 - failure
   the path to $file


=item get_my_ips

returns an arrayref of IP addresses on local interfaces.

=item is_process_running

Verify if a process is running or not.

   $util->is_process_running($process) ? print "yes" : print "no";

$process is the name as it would appear in the process table.



=item is_readable


  ############################################
  # Usage      : $util->is_readable( file=>$file );
  # Purpose    : ????
  # Returns    : 0 = no (not reabable), 1 = yes
  # Parameters : S - file - a path name to a file
  # Throws     : no exceptions
  # Comments   : none
  # See Also   : n/a

  result:
     0 - no (file is not readable)
     1 - yes (file is readable)



=item is_writable

If the file exists, it checks to see if it is writable. If the file does not exist, it checks to see if the enclosing directory is writable.

  ############################################
  # Usage      : $util->is_writable( "/tmp/boogers");
  # Purpose    : make sure a file is writable
  # Returns    : 0 - no (not writable), 1 - yes (is writeable)
  # Parameters : S - file - a path name to a file
  # Throws     : no exceptions


=item fstab_list


  ############ fstab_list ###################
  # Usage      : $util->fstab_list;
  # Purpose    : Fetch a list of drives that are mountable from /etc/fstab.
  # Returns    : an arrayref
  # Comments   : used in backup.pl
  # See Also   : n/a


=item get_dir_files

   $util->get_dir_files( $dir, verbose=>1 )

 required arguments:
   dir - a directory

 result:
   an array of files names contained in that directory.
   0 - failure


=item get_the_date

Returns the date split into a easy to work with set of strings.

   $util->get_the_date( bump=>$bump, verbose=>$verbose )

 required arguments:
   none

 optional arguments:
   bump - the offset (in days) to subtract from the date.

 result: (array with the following elements)
	$dd = day
	$mm = month
	$yy = year
	$lm = last month
	$hh = hours
	$mn = minutes
	$ss = seconds

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = $util->get_the_date();


=item install_from_source

  usage:

	$util->install_from_source(
		package => 'simscan-1.07',
   	    site    => 'http://www.inter7.com',
		url     => '/simscan/',
		targets => ['./configure', 'make', 'make install'],
		patches => '',
		verbose => 1,
	);

Downloads and installs a program from sources.

 required arguments:
    conf    - hashref - mail-toaster.conf settings.
    site    -
    url     -
    package -

 optional arguments:
    targets - arrayref - defaults to [./configure, make, make install].
    patches - arrayref - patch(es) to apply to the sources before compiling
    patch_args -
    source_sub_dir - a subdirectory within the sources build directory
    bintest - check the usual places for an executable binary. If found, it will assume the software is already installed and require confirmation before re-installing.

 result:
   1 - success
   0 - failure


=item install_from_source_php

Downloads a PHP program and installs it. This function is not completed due to lack o interest.


=item is_interactive

tests to determine if the running process is attached to a terminal.


=item logfile_append

   $util->logfile_append( $file, lines=>\@lines )

Pass a filename and an array ref and it will append a timestamp and the array contents to the file. Here's a working example:

   $util->logfile_append( $file, prog=>"proggy", lines=>["Starting up", "Shutting down"] )

That will append a line like this to the log file:

   2004-11-12 23:20:06 proggy Starting up
   2004-11-12 23:20:06 proggy Shutting down

 arguments required:
   file  - the log file to append to
   prog  - the name of the application
   lines - arrayref - elements are events to log.

 result:
   1 - success
   0 - failure


=item mailtoaster

   $util->mailtoaster();

Downloads and installs Mail::Toaster.


=item mkdir_system

   $util->mkdir_system( dir => $dir, verbose=>$verbose );

creates a directory using the system mkdir binary. Can also make levels of directories (-p) and utilize sudo if necessary to escalate.


=item check_pidfile

check_pidfile is a process management method. It will check to make sure an existing pidfile does not exist and if not, it will create the pidfile.

   $pidfile = $util->check_pidfile( "/var/run/program.pid" );

The above example is all you need to do to add process checking (avoiding multiple daemons running at the same time) to a program or script. This is used in toaster-watcher.pl. toaster-watcher normally completes a run in a few seconds and is run every 5 minutes.

However, toaster-watcher can be configured to do things like expire old messages from maildirs and feed spam through a processor like sa-learn. This can take a long time on a large mail system so we don't want multiple instances of toaster-watcher running.

 result:
   the path to the pidfile (on success).

Example:

	my $pidfile = $util->check_pidfile( "/var/run/changeme.pid" );
	unless ($pidfile) {
		warn "WARNING: couldn't create a process id file!: $!\n";
		exit 0;
	};

	do_a_bunch_of_cool_stuff;
	unlink $pidfile;


=item regexp_test

Prints out a string with the regexp match bracketed. Credit to Damien Conway from Perl Best Practices.

 Example:
    $util->regexp_test(
		exp    => 'toast',
		string => 'mailtoaster rocks',
	);

 arguments required:
   exp    - the regular expression
   string - the string you are applying the regexp to

 result:
   printed string highlighting the regexp match


=item source_warning

Checks to see if the old build sources are present. If they are, offer to remove them.

 Usage:

   $util->source_warning(
		package => "Mail-Toaster-5.26",
		clean   => 1,
		src     => "/usr/local/src"
   );

 arguments required:
   package - the name of the packages directory

 arguments optional:
   src     - the source directory to build in (/usr/local/src)
   clean   - do we try removing the existing sources? (enabled)
   timeout - how long to wait for an answer (60 seconds)

 result:
   1 - removed
   0 - failure, package exists and needs to be removed.


=item sources_get

Tries to download a set of sources files from the site and url provided. It will try first fetching a gzipped tarball and if that files, a bzipped tarball. As new formats are introduced, I will expand the support for them here.

  usage:
	$self->sources_get(
		package => 'simscan-1.07',
		site    => 'http://www.inter7.com',
		path    => '/simscan/',
	)

 arguments required:
   package - the software package name
   site    - the host to fetch it from
   url     - the path to the package on $site

 arguments optional:
   conf    - hashref - values from toaster-watcher.conf

This sub proved quite useful during 2005 as many packages began to be distributed in bzip format instead of the traditional gzip.


=item sudo

   my $sudo = $util->sudo();

   $util->syscmd( "$sudo rm /etc/root-owned-file" );

Often you want to run a script as an unprivileged user. However, the script may need elevated privileges for a plethora of reasons. Rather than running the script suid, or as root, configure sudo allowing the script to run system commands with appropriate permissions.

If sudo is not installed and you're running as root, it'll offer to install sudo for you. This is recommended, as is properly configuring sudo.

 arguments required:

 result:
   0 - failure
   on success, the full path to the sudo binary


=item syscmd

   Just a little wrapper around system calls, that returns any failure codes and prints out the error(s) if present. A bit of sanity testing is also done to make sure the command to execute is safe.

      my $r = $util->syscmd( "gzip /tmp/example.txt" );
      $r ? print "ok!\n" : print "not ok.\n";

    arguments required:
      cmd     - the command to execute

    result
      the exit status of the program you called.


=item _try_mkdir

try creating a directory using perl's builtin mkdir.


=item yes_or_no

  my $r = $util->yes_or_no(
      "Would you like fries with that?",
      timeout  => 30
  );

	$r ? print "fries are in the bag\n" : print "no fries!\n";

 arguments required:
   none.

 arguments optional:
   question - the question to ask
   timeout  - how long to wait for an answer (in seconds)

 result:
   0 - negative (or null)
   1 - success (affirmative)


=back


=head1 TODO

  make all errors raise exceptions
  write test cases for every method

=head1 SEE ALSO

The following are all man/perldoc pages:

 Mail::Toaster


=cut
