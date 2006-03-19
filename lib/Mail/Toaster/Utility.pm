#!/usr/bin/perl
use strict;

#
# $Id: Utility.pm,v 4.28 2006/03/18 03:32:54 matt Exp $
#

package Mail::Toaster::Utility;

use Carp;
#use POSIX qw(uname);
my $os = $^O;

use vars qw($VERSION);
$VERSION = '4.19';

use lib "lib";
use lib "../..";

sub answer;
sub archive_expand($;$);
sub chdir_source_dir($;$);
sub check_homedir_ownership(;$);
sub clean_tmp_dir($);
sub drives_get_mounted(;$);
sub graceful_exit(;$$);
sub file_append;
sub file_archive;
sub file_check_readable;
sub file_check_writable;
sub file_delete;
sub file_get;
sub file_read;
sub file_write;
sub files_diff ;
sub find_the_bin;
sub fstab_list;
sub get_dir_files;
sub get_file;
sub get_the_date;
sub install_if_changed;
sub install_from_source;
sub install_from_sources_php;
sub is_arrayref;
sub is_hashref;
sub is_process_running;
sub logfile_append;
sub mailtoaster;
sub path_parse;
sub parse_config;
sub pidfile_check;
sub sources_get;
sub source_warning;
sub sudo;
sub syscmd;
sub yes_or_no;


1;

=head1 NAME

Mail::Toaster::Utility

=head1 SYNOPSIS

a group of frequently used perl methods I've written for use with various scripts.

=head1 DESCRIPTION

useful subs that I use in scripts all over the place. Peruse through the list of methods and surely you too can find something of use. 

=head1 METHODS

=head2 new

To use any of the utility methods, you must create a utility object:

  use Mail::Toaster::Utility;
  my $utility = Mail::Toaster::Utility->new;

=cut

sub new
{
	my ($class, $name) = @_;
	my $self = { name => $name };
	bless ($self, $class);
	return $self;
};

=head2 answer

  my $answer = $utility->answer("question", $default, $timer)

arguments:
 a string with the question to ask
 an optional default answer.
 how long (in seconds) to wait for a response

returned is a string. If the user responded, their response is returned. If not, then the default response is returned. If no default was supplied, 0 is returned.

=cut

sub answer
{
	my ($self, $q, $default, $timer) = @_;
	my $ans;

	if ($default) { print "Please enter $q. ($default) :" }
	else          { print "Please enter $q: "             };

	if ($timer) {
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" };
			alarm $timer;
			$ans = <STDIN>;
			alarm 0;
		};
		if ($@) { 
			($@ eq "alarm\n") ? print "timed out!\n" : carp;  # propagate unexpected errors
		};
	} 
	else { $ans = <STDIN> };

	chomp $ans;

	if ($ans ne "") { return $ans; }
	else
	{
		return ($default) if $default;
		return 0;
	};
};

=head2 archive_expand

  $utility->archive_expand("package.tar.bz2", $debug);

Takes an archive and decompresses and expands it's contents. Works with bz2, gz, and tgz files.

=cut

sub archive_expand($;$)
{
	my ($self, $archive, $debug) = @_;
	my $r;

	my $tar  = $self->find_the_bin("tar");
	my $file = $self->find_the_bin("file");
	my $grep = $self->find_the_bin("grep");

	unless ( -e $archive ) {
		if    ( -e "$archive.tar.gz"  ) { $archive = "$archive.tar.gz"  }
		elsif ( -e "$archive.tgz"     ) { $archive = "$archive.tgz" }
		elsif ( -e "$archive.tar.bz2" ) { $archive = "$archive.tar.bz2" }
		else  { print "archive_expand: file $archive is missing!\n"; };
	};

	if ( $archive =~ /bz2$/ ) 
	{
		print "archive_expand: decompressing $archive...." if $debug;

		# Check to make sure the archive contents match the file extension
		# this shouldn't be necessary but the world isn't perfect. Sigh.

		# file $file on BSD yields bunzip2, on Linux bzip2
		if ( `$file $archive | $grep bunzip2` || `$file $archive | $grep bzip2` ) {
			my $bunzip2 = $self->find_the_bin("bunzip2");
			if ( $self->syscmd("$bunzip2 -c $archive | $tar -xf -") ) {
				print "archive_expand: FAILURE expanding\n";
				return 0;
			} else {
				return 1;
			};
		} else {
			print "FAILURE: $archive is not a bz2 compressed file!\n";
			return 0;
		};
	}
	elsif ( $archive =~ /gz$/ )
	{
		print "archive_expand: decompressing $archive...." if $debug;
		if ( `$file $archive | $grep gzip` ) {
			my $gunzip = $self->find_the_bin("gunzip");
			if ( $self->syscmd("$gunzip -c $archive | $tar -xf -") ) {
				print "archive_expand: FAILURE expanding\n";
				return 0;
			} else {
				print "done.\n" if $debug;
				return 1;
			};
		} else {
			print "FAILURE: $archive is not a gzip compressed file!\n";
			return 0;
		};
	}
	else
	{
		print "archive_expand: FAILED: I don't know how to expand $archive!\n";
		return 0;
	}
	print "done.\n" if $debug;
	return 1;
};


=head2 chdir_source_dir

  $utility->chdir_source_dir("/usr/local/src");

changes your working directory to the supplied one. Creates it if it doesn't exist.

returns 1 on success

=cut

sub chdir_source_dir($;$)
{
	my ($self, $dir, $src) = @_;

	unless ( $dir ) { croak "You aren't calling this method correctly!\n"; };

	if ( $src ) 
	{
		if ( -e $src && ! -d $src ) {
			croak "Something (other than a directory) is at $src and that's my build directory. Please remove it and try again!\n";
		};

		unless ( -e $src )
		{
			mkdir($src, 0755) or carp "chdir_source_dir: mkdir $src failed: $!\n";
			unless ( -d $src ) 
			{
				print "chdir_source_dir: trying again with mkdir -p....\n";
				my $mkdir = $self->find_the_bin("mkdir");
				$self->syscmd("$mkdir -p $src");
				unless ( -d $src ) { 
					my $sudo = $self->sudo;
					if ( $sudo ) {
						print "chdir_source_dir: trying one last time with $sudo mkdir -p....\n";
						$self->syscmd("$sudo $mkdir -p $src");
						print "chdir_source_dir: fixing ownership.\n";
						my $chown = $self->find_the_bin("chown");
						$self->syscmd("$sudo $chown $< $src");
					};
				};
				unless ( -d $src ) { 
					croak "chdir_source_dir: Couldn't create $src.\n"; 
				};
			};
		};
	};

	if ( -e $dir && ! -d $dir ) {
		croak "Something (other than a directory) is at $dir and that's my build directory. Please remove it and try again!\n";
	};

	unless ( -d $dir ) 
	{
		mkdir($dir, 0755) or warn "mkdir $dir failed.\n";
		unless ( -d $dir ) {
			print "chdir_source_dir: trying again with mkdir -p $src\n";
			my $mkdir = $self->find_the_bin("mkdir");
			$self->syscmd("$mkdir -p $dir");
			unless ( -d $dir ) { 
				my $sudo = $self->sudo;
				if ( $sudo ) {
					print "chdir_source_dir: trying one last time with $sudo mkdir -p $dir\n";
					$self->syscmd("$sudo $mkdir -p $dir");
					print "chdir_source_dir: fixing ownership.\n";
					my $chown = $self->find_the_bin("chown");
					$self->syscmd("$sudo $chown $< $dir");
				};
			};
			unless ( -d $dir ) { croak "Couldn't create $dir.\n"; };
		}
	}

	chdir($dir) or croak "chdir_source_dir: FAILED to cd to $dir: $!\n";
	return 1;
};


=head2 check_homedir_ownership

Checks the ownership on all home directories to see if they are owned by their respective users in /etc/password. Offers to repair the permissions on incorrectly owned directories. This is useful when someone that knows better does something like "chown -R user /home /user" and fouls things up.

  $utility->check_homedir_ownership;

=cut

sub check_homedir_ownership(;$)
{
	my ($self, $debug) = @_;

	unless ( $os eq "freebsd" ) {
		print "WARNING: skipping, I don't know " . $os . "\n";
		return 0;
	};

	# name, passwd, uid, gid, quota, comment, gcos, dir, shell
	my $n;
	setpwent();
	while( my ($name, $uid, $dir) = (getpwent())[0,2,7] ) 
	{
		print "Checking for $name\n" if $debug;
		next if ( $uid < 100 );
		next if ( $name eq "nobody" );
		unless (-e $dir) {
			print "WARNING: ${name}'s home dir: $dir, does not exist.\n";
#			&get_users_domain_list($name);
			next;
		}
		my $dir_stat = stat($dir) or croak "Couldn't stat $dir: $!\n";
		if ( $uid != @$dir_stat[4] ) 
		{
			print "warning: $name is uid $uid, but $dir is owned by @$dir_stat[4].\n";
			if ( $self->yes_or_no("Would you like me to fix it? ", 5) ) 
			{
				my $sudo = $self->sudo;
				my $chown = $self->find_the_bin("chown");
				$self->syscmd("$sudo $chown -R $name $dir");
				print "Changed $dir to be owned by $name\n\n";
				next;
			} 
			else { next; }
		}
	};
	endpwent();
};


# exists solely for backwards compatability
sub check_pidfile { my $self = shift; return $self->pidfile_check(@_); };


=head2 clean_tmp_dir

  $utility->clean_tmp_dir($dir)

$dir is a directory. Running this will empty it. Be careful!

=cut

sub clean_tmp_dir($)
{
	my ($self, $dir) = @_;

	chdir ($dir) or croak "couldn't chdir to $dir: $!\n";

	foreach ( $self->get_dir_files($dir) )
	{
		if    ( -f $_ ) { $self->file_delete($_)  }
		elsif ( -d $_ )
		{
			use File::Path;
			rmtree $_ or croak "CleanTmpdir: couldn't delete $_\n";
		}
		else { 
			print "What the heck is $_?\n";
		}
	}
}


=head2 drives_get_mounted

  $utility->drives_get_mounted($debug);

Uses mount to fetch a list of mounted drive/partitions.

returned is a hashref of mounted slices and their mount points.

=cut

sub drives_get_mounted(;$)
{
	my ($self, $debug) = @_;
	my %hash;

	my $mountbin = $self->find_the_bin("mount");

	foreach ( `$mountbin` ) 
	{
		my ($d, $m) = $_ =~ /^(.*) on (.*) \(/;

#		if ( $m =~ /^\// && $d =~ /^\// )  # mounts and drives that begin with /
		if ( $m && $m =~ /^\// )           # only mounts that begin with /
		{
			print "adding: $m \t $d\n" if $debug;
			$hash{$m} = $d;
		};
	};
	return \%hash;
};


sub graceful_exit(;$$)
{
	my ($self, $code, $desc) = @_;

	print "$desc\n" if $desc;
	print "+$code\n" if $code;
	exit 1;
};


=head2 install_if_changed


 $attrs = {
	uid    => ,
	gid    => ,
	mode   => ,
	clean  => ,
	notify => ,
	email  => ,
 };


 return values:
  0 = error (failure)
  1 = normal success
  2 = success, no update required

=cut

sub install_if_changed
{
	my ($self, $new, $existing, $attrs, $debug) = @_;

	my $uid = $attrs->{'uid'}   if ( $self->is_hashref($attrs) );
	my $gid = $attrs->{'gid'}   if ( $self->is_hashref($attrs) );
	my $mode = $attrs->{'mode'} if ( $self->is_hashref($attrs) );
	my $sudo = "";

	unless ( -e $new ) {
		print "FATAL: the file to install ($new) does not exist!\n";
		return 0;
	};

	unless ( $self->file_check_writable($existing) && $self->file_check_writable($new) )
	{
		$sudo = $self->find_the_bin("sudo");
		unless ( -x $sudo )
		{
			carp "FAILED: you are not root, sudo is not installed, and you don't have permission to write to either $new or $existing. Sorry, I can't go on!\n";
			return 0;
		}
	} else {
		use File::Copy;
	};

	unless ( $self->files_diff($new, $existing, "text", $debug) ) 
	{
		print "install_if_changed: $existing is already up-to-date.\n" if $debug;
		unlink $new if ($attrs->{'clean'} );
		return 2;
	}

	print "install_if_changed: updating $existing..." if $debug;

	if ( $uid && $gid ) {                         # set file ownership
		if ( $sudo ) {
			unless ( $self->syscmd("$sudo chown $uid:$gid $new") ) {
				carp "couldn't chown $new: $!\n";
				return 0;
			};
		} else {
			unless ( chown($uid, $gid, $new) )
			{
				carp "couldn't chown $new: $!\n";
				return 0;
			}
		}
	};

	if ($mode) {                                  # set file permissions
		if ( $sudo ) {
			unless ( $self->syscmd("$sudo chmod $mode $new") ) {
				carp "couldn't chmod $new: $!\n";
				return 0;
			};
		} else {
			unless ( chmod $mode, $new ) {
				carp "couldn't chmod $new: $!\n";
				return 0;
			};
		}
	}

	if ($attrs->{'notify'} )                      # email diffs to admin
	{
		my $email = $attrs->{'email'} || "root";
		my $diff  = $self->find_the_bin("diff");

		use Mail::Toaster::Perl; my $perl = new Mail::Toaster::Perl;
		$perl->module_load( {module=>"Mail::Send", ports_name=>"p5-Mail-Tools", ports_group=>"mail"} );
		require Mail::Send;
		my $msg = new Mail::Send;
		$msg->subject("$existing updated");
		$msg->to($email);
		my $fh = $msg->open;

		print $fh "This message is to notify you that $existing has been altered. The difference between the new file and the old one is:\n\n";

		my $diffie = `$diff $new $existing`;
		print $fh $diffie;
		$fh->close;
	};

	if ( $sudo ) {                              # install the new file
		$self->syscmd("$sudo cp $existing $existing.bak") if (-e $existing);
		if ( $attrs->{'clean'} ) {
			$self->syscmd("$sudo mv $new $existing");
		} else {
			$self->syscmd("$sudo cp $new $existing");
		}
	}
	else
	{
		copy($existing, "$existing.bak") if (-e $existing);

		if ( $attrs->{'clean'} ) {
			unless ( move ($new, $existing) ) {
				carp "couldn't copy $new to $existing: $!\n";
				return 0;
			}
		} else {
			unless ( copy ($new, $existing) ) {
				carp "couldn't copy $new to $existing: $!\n";
				return 0;
			}
		}
	};

	if ( $uid && $gid ) {                         # set file ownership
		if ( $sudo ) {
			unless ( $self->syscmd("$sudo chown $uid:$gid $existing") ) {
				carp "couldn't chown $existing: $!\n";
				return 0;
			};
		} else {
			unless ( chown($uid, $gid, $existing) )
			{
				carp "couldn't chown $existing: $!\n";
				return 0;
			}
		}
	};

	if ($mode) {                                  # set file permissions
		if ( $sudo ) {
			unless ( $self->syscmd("$sudo chmod $mode $existing") ) {
				carp "couldn't chmod $existing: $!\n";
				return 0;
			};
		} else {
			unless ( chmod $mode, $existing ) {
				carp "couldn't chmod $existing: $!\n";
				return 0;
			};
		}
	}

	print "done.\n" if $debug;
	return 1;
};


=head2 install_from_sources_php

  $utility->install_from_sources_php();

Downloads a PHP program and installs it. Not completed.

=cut

sub install_from_sources_php($$$$;$$$)
{
	my $self = shift;
	#my ($conf, $vals) = @_;
	my ($conf, $package, $site, $url, $targets, $patches, $debug) = @_;
	my $patch;

	my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
	$self->chdir_source_dir($src);

	if ( -d $package ) 
	{
		unless ( $self->source_warning($package, 1, $src) )
		{
			carp "\ninstall_from_sources_php: OK then, skipping install.\n";
			return 0;
		} else {
			print "install_from_sources_php: removing any previous build sources.\n";
			$self->syscmd("rm -rf $package-*");   # nuke any old versions
		};
	};

	print "install_from_sources_php looking for existing sources...";

	my $tarball = "$package.tar.gz";
	if    ( -e $tarball )          { print "found.\n"; }
	elsif ( -e "$package.tgz" )    { print "found.\n"; $tarball = "$package.tgz"; } 
	elsif ( -e "$package.tar.bz2") { print "found.\n"; $tarball = "$package.tar.bz2"; } 
	else                           { print "not found.\n" };

	unless ( -e $tarball ) { $self->sources_get($conf, {package=>$package, site=>$site, url=>$url}) }
	else 
	{
		print "install_from_sources_php: using existing $tarball sources.\n";
	};

	if ( $patches && @$patches[0] ) 
	{
		print "install_from_sources_php: fetching patches...\n";
		foreach $patch ( @$patches ) 
		{
			my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
			unless ($toaster) { $toaster = "http://www.tnpi.biz/internet/mail/toaster"; };
			unless ( -e $patch ) {
				unless ( $self->file_get("$toaster/patches/$patch") )
				{
					croak "install_from_sources_php: couldn't fetch $toaster/$patches/$patch\n";
				};
			};
		};
	} 
	else 
	{
		print "install_from_sources_php: no patches to fetch.\n";
	};

	$self->archive_expand($tarball, 1) or croak "Couldn't expand $tarball: $!\n";

	if ( -d $package )
	{
		chdir $package;

		if ( $patches && @$patches[0] ) 
		{
			print "yes, should be patching here!\n";
			foreach $patch ( @$patches ) 
			{
				my $patchbin = $self->find_the_bin("patch");
				if ( $self->syscmd("$patchbin < ../$patch") ) 
				{ 
					croak "install_from_sources_php: patch failed: $!\n";
				};
			};
		};

#		unless ( @$targets[0] ) 
#		{
#			print "install_from_sources_php: using default targets (./configure, make, make install).\n";
#			@$targets = ( "./configure", "make", "make install") 
#		};

		foreach my $target ( @$targets ) 
		{ 
			if ( $self->syscmd($target) )
			{
				croak "install_from_source_php: $target failed: $!\n";
			};
		};
#		chdir("..");
#		$self->syscmd("rm -rf $package");
	};
};


=head2 file_append

  $utility->file_append($file, $lines)

Pass a filename and an array ref and it'll append the array contents to the file. It's that simple.

=cut

sub file_append($$)
{
	my ($self, $file, $lines) = @_;

	unless ( $self->is_arrayref($lines) ) 
	{
		my ($package, $filename, $line) = caller;
		if ($package ne "main") { print "WARNING: Package $package passed $filename an invalid argument "; } 
		else                    { print "WARNING: $filename was passed an invalid argument "; }
	}

	unless ( open FILE, ">>$file" )
	{
		carp "file_append: couldn't open: $!";
		return 0;
	};

	foreach (@$lines) { print FILE "$_\n"; };

	close FILE or return 0;
	return 1;
};


=head2 file_archive

  $utility->file_archive ($file)

Make a backup copy of a file by copying the file to $file.timestamp.

returns 0 on failure, a file path on success.

=cut

sub file_archive($)
{
	my ($self, $file) = @_;
	my $date = time;

	if ( $< != 0 )  # we're not root
	{
		my $sudo = $self->find_the_bin("sudo");
		my $cp   = $self->find_the_bin("cp");
		$self->syscmd( "$sudo cp $file $file.$date");
	} 
	else 
	{
		use File::Copy;
		copy($file, "$file\.$date") or croak "backup of $file to $file.$date failed: $!\n";
	};

	print "file_archive: $file backed up to $file.$date\n";
	-e "$file.$date" ? return "$file.$date" : return 0;
};


=head2 file_check_readable

  $utility->file_check_readable($file);

input is a string consisting of a path name to a file. An optional second argument changes the default exit behaviour to warn and continue (rather than dying).

return is 1 for yes, 0 for no.

=cut

sub file_check_readable($;$)
{
	my ($self, $file, $warn) = @_;

	unless ( -e $file )
	{
		print "\nfile_check_readable: ERROR: The file $file currently does not exist. This is most likely because you did not follow the installation instructions correctly. Please read and follow the instructions. If the problems persist, email a complete description of the problem to support\@tnpi.biz.\n\n";
		$warn ? return 0 : croak "\n";
	};

	unless ( -r $file ) 
	{
		print "\nfile_check_readable: ERROR: Pardon me but I need your help. The file $file is currently not readable by the user I'm running as (" . getpwuid($>) . "). You need to fix this, most likely using either chown or chmod.\n\n";
		$warn ? return 0 : croak "\n";
	}

	return 1;
};


=head2 file_check_writable

   use Mail::Toaster::Utility;
   $utility->file_check_writable("/tmp/boogers", $debug) ? print "yes" : print "no";

If the file exists, it checks to see if it's writable. If the file does not exist, then it checks to see if the enclosing directory is writable. 

It will output verbose messages if you set the debug flag.

returns a 1 if writable, zero otherwise.

=cut

sub file_check_writable($;$)
{
	my ($self, $file, $debug) = @_;

	my $nl = "\n"; $nl = "<br>" if ( $ENV{'GATEWAY_INTERFACE'} );

	print "file_check_writable: checking $file..." if $debug;

	if ( -e $file )    # if the file exists
	{
		unless ( -w $file ) 
		{
			print "WARNING: file_check_writable: $file not writable by " . getpwuid($>) . "!$nl$nl>" if $debug;
			#carp "WARNING: file_check_writable: $file not writable by " . getpwuid($>) . "!$nl$nl>";
			return 0;
		};
	} 
	else
	{
		use File::Basename;
		my ($base, $path, $suffix) = fileparse($file);

		unless ( -w $path )
		{
			#print "\nWARNING: file_check_writable: $path not writable by " . getpwuid($>) . "!$nl$nl" if $debug;
			carp "\nWARNING: file_check_writable: $path not writable by " . getpwuid($>) . "!$nl$nl" if $debug;
			return 0;
		};
	};

	print "yes.$nl" if $debug;
	return 1;
};


=head2 file_delete

Deletes a file. Uses unlink if we have appropriate permissions, otherwise uses a system rm call, using sudo if it's not being run as root. This sub will try very hard to delete the file!

   $utility->file_delete($file, $warn);

Arguments are a file path and $warn is an optional boolean.

returns 1 for success, 0 for failure.

=cut

sub file_delete($;$)
{       
	my ($self, $file, $warn) = @_;

	unless ( -e $file ) {
		print "WARNING: $file to delete does not exist!\n";
		return 0;
	};

	if ( -w $file ) {  # we have write permissions on the file
		if ( $warn ) { unlink $file or croak "FATAL: couldn't delete $file: $!\n"  } 
		else         { unlink $file or carp "WARNING: couldn't delete $file: $!\n" };
	} 
	else {
		my $rm = $self->find_the_bin("rm");
		if ( $< == 0 ) {   # we're running as root
			$self->syscmd("$rm -f $file");
		} else {
			my $sudo = $self->sudo();
			$self->syscmd("$sudo $rm -f $file");
		};
	}

	-e $file ? return 0 : return 1;
};

=head2 file_get

   $utility->file_get($url, $debug);

Use an appropriate URL fetching utility (fetch, curl, wget, etc) based on your OS to download a file from the $url handed to us. 

Returns 1 for success, 0 for failure.

=cut

sub file_get($;$)
{
	my ($self, $url, $debug) = @_;
	my ($fetchbin, $fetchcmd);

	print "file_get: fetching $url\n" if $debug;

	if    ( $os eq "freebsd" ) { $fetchbin = $self->find_the_bin("fetch")  }
	elsif ( $os eq "darwin"  ) { $fetchbin = $self->find_the_bin("curl")   }
	else                       { $fetchbin = $self->find_the_bin("wget")   };

	unless ( -x $fetchbin ) 
	{
		# should use LWP here
		print "Yikes, couldn't find wget! Please install it.\n";
		return 0;
	};

	if ( $os eq "freebsd" )
	{
		$fetchcmd  = "$fetchbin ";
		$fetchcmd .= "-q " unless $debug;
		$fetchcmd .= "$url";
	}
	elsif ( $os eq "darwin" ) {
		$fetchcmd  = "$fetchbin -O ";
		$fetchcmd .= "-s " unless $debug;
		$fetchcmd .= "$url";
	};
	$fetchcmd ||= "$fetchbin $url";

	my $r = $self->syscmd($fetchcmd);

	if ( $r != 0 )
	{
		print "file_get error executing $fetchcmd\n";
		print "file_get error result:  $r\n";
		return 0;
	};

	return 1;
};

=head2 file_read

   my @lines = $utility->file_read($file)

Reads in a file, and returns an array with the files contents, one line per array element. All lines in array are chomped. Accepts an optional maximum number of lines, passed as a numeric value.

=cut

sub file_read($;$)
{
	my ($self, $file, $max) = @_;

	unless ( -e $file ) {
		carp "file_read: $file does not exist!\n";
		return if defined wantarray;     # error checking is likely done by caller
		croak "FATAL: file_read could not find $file: $!\n";
	};

	unless ( -r $file ) {
		carp "file_read: $file is not readable!\n";
		return if defined wantarray;     # error checking is likely done by caller
		croak "FATAL: file_read could not find $file: $!\n";
	};

	open(FILE, $file) or carp "file_read: couldn't open $file: $!";
	my @lines;
	if ($max) {
		for ( my $i = 0; $i < $max; $i++ ) {
			my $line = <FILE>;
			push @lines, $line;
		};
	} else {
		@lines = <FILE>;
	};
	close FILE;

	chomp @lines;
	return @lines;
};


=head2 file_write

   $utility->file_write ($file, @lines)

	my $file = "/tmp/foo";
	my @lines = "1", "2", "3";

	print "success" if ($utility->file_write($file, @lines));

$file is the file you want to write to
@lines is a an array, each array element is a line in the file

1 is returned on success, 0 or undef on failure

=cut

sub file_write($@)
{
	my ($self, $file, @lines) = @_;

	if ( -d $file ) {
		print "file_write FAILURE: $file is a directory!\n";
		return 0;
	};

	if( -f $file && ! -w $file )
	{
		print "file_write FAILURE: $file is not writable!\n";
		return 0;
	}

	unless ( open FILE, ">$file" )
	{
		carp "file_write: couldn't open $file: $!";
		return 0;
	};

	for (@lines) { print FILE "$_\n" };
	close FILE;

	return 1;
};

=head2 files_diff

   $utility->files_diff($file1, $file2, $type, $debug);

   if ( $utility->files_diff("foo", "bar") ) 
   { 
       print "different!\n"; 
   };

Determine if the files are different. $type is assumed to be text unless you set it otherwise. For anthing but text files, we do a MD5 checksum on the files to determine if they're different or not.

return 0 if files are the same, 1 if they are different, and -1 on error.

=cut

sub files_diff ($$;$$)
{
	my ($self, $f1, $f2, $type, $debug) = @_;

	return -1 unless (-e $f1 && -e $f2);

	$type ||= "text";

	if ($type eq "text") {
		my $diff = `diff $f1 $f2`;
		return $diff;
	} 
	else 
	{
		eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;
		$perl->module_load( {module=>"Digest::MD5", ports_name=>"p5-Digest-MD5", ports_group=>"security"} );

		my @md5sums;
	
		foreach my $f ($f1, $f2) 
		{
			my $ctx = Digest::MD5->new;
			my $sum;
			if(-f "$f.md5"){
				open(F,"$f.md5");
				my $sum=<F>;
				close(F);
				chomp$sum;
			}
			if(!-f "$f.md5" || $sum!~/[0-9a-f]+/i){
				open(F,"$f");
				$ctx->addfile(*F);
				$sum=$ctx->hexdigest;
				close(F);
			}
			push (@md5sums,$sum);
			open(F,">$f.md5");
			print F $sum;
			close(F);
		}

		if ($md5sums[0] eq $md5sums[1]) {
			return 0;
		}
		return 1;
	};
};

=head2 find_the_bin

   $utility->find_the_bin($bin, $dir);

Check all the "normal" locations for a binary that should be on the system and returns the full path to the binary. Return zero if we can't find it.

If the optional $dir is sent, then check that directory first.

Example: 

   my $apachectl = $utility->find_the_bin("apachectl", "/usr/local/sbin")

=cut

sub find_the_bin($;$)
{
	my ($self, $bin, $dir) = @_;
	my $prefix = "/usr/local";

	if    ( $dir && -x "$dir/$bin"      ) { return "$dir/$bin"; };
	if    ( $bin =~ /^\// && -x $bin    ) { return $bin         };  # we got a full path

	if    ( -x "$prefix/bin/$bin"       ) { return "/usr/local/bin/$bin";  }
	elsif ( -x "$prefix/sbin/$bin"      ) { return "/usr/local/sbin/$bin"; }
	elsif ( -x "$prefix/mysql/bin/$bin" ) { return "$prefix/mysql/bin/$bin"; }
	elsif ( -x "/bin/$bin"              ) { return "/bin/$bin";            }
	elsif ( -x "/usr/bin/$bin"          ) { return "/usr/bin/$bin";        }
	elsif ( -x "/sbin/$bin"             ) { return "/sbin/$bin";           }
	elsif ( -x "/usr/sbin/$bin"         ) { return "/usr/sbin/$bin";       }
	elsif ( -x "/opt/local/bin/$bin"    ) { return "/opt/local/bin/$bin";  }
	elsif ( -x "/opt/local/sbin/$bin"   ) { return "/opt/local/sbin/$bin"; }
	else  { return };
};


=head2 fstab_list

Fetch a list of drives that are mountable from /etc/fstab.

   $utility->fstab_list;

returns an arrayref.

=cut

sub fstab_list
{
	my @fstabs = `grep -v cdr /etc/fstab`;
#	foreach my $fstab (@fstabs)
#	{
#		my @fields = split(" ", $fstab);
#		#print "device: $fields[0]  mount: $fields[1]\n";
#	};
#	print "\n\n END of fstabs\n\n";

	return \@fstabs;
}

=head2 get_dir_files

   $utility->get_dir_files($dir, $debug)

$dir is a directory. The return will be an array of files names contained in that directory.

=cut

sub get_dir_files($;$)
{
	my ($self, $dir, $debug) = @_;
	my @files;

	opendir(D, $dir) or croak "get_dir_files: couldn't open $dir: $!";
	while( defined ( my $f = readdir(D) ) )
	{
		next if $f =~ /^\.\.?$/;
		push @files, "$dir/$f";
	};
	closedir(D);
	return @files;
};

# here for compatability
sub get_file($;$) {	my $self = shift; return $self->file_get(@_) }

=head2 get_the_date

   $utility->get_the_date ($bump, $debug)

$bump is the optional offset (in seconds) to subtract from the date.

returned is an array:

	$dd = day
	$mm = month
	$yy = year
	$lm = last month
	$hh = hours
	$mn = minutes
	$ss = seconds

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = $utility->get_the_date();

=cut

sub get_the_date(;$$)
{
	my ($self, $bump, $debug) = @_;
	my $time = time;
	print "time: $time\n" if $debug;

	eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;
	$perl->module_load( {module=>"Date::Format", ports_name=>"p5-TimeDate", ports_group=>"devel"} );

	if ($bump) 
	{
		$bump  = $bump * 86400;
		my $ss = Date::Format::time2str("%S", ( time                   ));
		my $mn = Date::Format::time2str("%M", ( time                   ));
		my $hh = Date::Format::time2str("%H", ( time - (        $bump) ));
		my $dd = Date::Format::time2str("%d", ( time - (        $bump) ));
		my $mm = Date::Format::time2str("%m", ( time - (        $bump) ));
		my $yy = Date::Format::time2str("%Y", ( time - (        $bump) ));
		my $lm = Date::Format::time2str("%m", ( time - (2592000+$bump) ));

		print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
		return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
	}
	else
	{
		my $ss = Date::Format::time2str("%S", (time          ));
		my $mn = Date::Format::time2str("%M", (time          ));
		my $hh = Date::Format::time2str("%H", (time          ));
		my $dd = Date::Format::time2str("%d", (time          ));
		my $mm = Date::Format::time2str("%m", (time          ));
		my $yy = Date::Format::time2str("%Y", (time          ));
		my $lm = Date::Format::time2str("%m", (time - 2592000));
		print "get_the_date: $yy/$mm/$dd $hh:$mn\n" if $debug;
		return $dd, $mm, $yy, $lm, $hh, $mn, $ss;
	};
};


=head2 install_from_source

   $vals = { package => 'simscan-1.07',
   	   site    => 'http://www.inter7.com',
   	   url     => '/simscan/',
   	   targets => ['./configure', 'make', 'make install'],
   	   patches => '',
   	   debug   => 1,
   };

	$utility->install_from_source($conf, $vals, $debug);

Downloads and installs a program from sources.

targets and partches are array references.

An optional value to set is bintest. If set, it'll check the usual places for an executable binary. If found, it'll assume the software is already installed and require confirmation before re-installing.

returns 1 on success, 0 on failure.

=cut

sub install_from_source($$;$)
{
	my ($self, $conf, $vals, $debug) = @_;
	my $patch;

	unless ( $self->is_hashref($vals) ) {
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename passed install_from_source an invalid argument \n" if $debug;
		return 0;
	}

	if ( $conf && ! $self->is_hashref($conf) ) {
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename passed install_from_source an invalid argument \n" if $debug;
		return 0;
	}

	return 1 if ( $conf->{'int_test'} or $conf->{'int_test'} );

	my $src = $conf->{'toaster_src_dir'} || "/usr/local/src";
	if ( $vals->{'source_sub_dir'} ) { $src .= "/" . $vals->{'source_sub_dir'}; };
	$self->chdir_source_dir($src);

	my $package = $vals->{'package'};
	my $bintest = $vals->{'bintest'};

	if ( $bintest && -x $self->find_the_bin($bintest) ) {
		return 0 unless $self->yes_or_no("I detected $bintest which likely means that $package is already installed, do you want to reinstall?", 60);
	};

	if ( -d $package ) 
	{
		unless ( $self->source_warning($package, 1, $src) )
		{
			carp "\ninstall_from_source: OK then, skipping install.\n";
			return 0;
		}
		else
		{
			print "install_from_source: removing any previous build sources.\n";
			$self->syscmd("rm -rf $package-*");   # nuke any old versions
		};
	};

	#print "install_from_source: looking for existing sources...";
	$self->sources_get($conf, $vals);

	my $patches = $vals->{'patches'};
	if ( $patches && @$patches[0] ) 
	{
		print "install_from_source: fetching patches...\n";
		foreach $patch ( @$patches ) 
		{
			my $toaster = "$conf->{'toaster_dl_site'}$conf->{'toaster_dl_url'}";
			$toaster ||= "http://www.tnpi.biz/internet/mail/toaster";
			unless ( -e $patch ) {
				unless ( $self->file_get("$toaster/patches/$patch") )
				{
					if ( $toaster ne "http://www.tnpi.biz/internet/mail/toaster" ) {
						# print a helpful error message if the luser does something stupid 
						print "CAUTION: apparently you have edited toaster_dl_site or toaster_dl_url in your toaster-watcher.conf. You shouldn't do that unless you know what you're doing, and apparently you don't. Now I can't find a patch ($patch) that I need to install $package. Fix your toaster-watcher.conf file and try again.";
					};
					croak "install_from_source: couldn't fetch $toaster/patches/$patch\n";
				};
			};
		};
	} 
	else 
	{
		print "install_from_source: no patches to fetch.\n";
	};

	$self->archive_expand($package, 1) or croak "Couldn't expand $package: $!\n";

	if ( -d $package )
	{
		chdir $package or carp "FAILED to chdir $package!\n";
	}
	else {
		# some packages (like daemontools) unpack within an enclosing directory, grrr
		my $sub_path = `find ./ -name $package`; chomp $sub_path;
		print "found sources in $sub_path\n" if $sub_path;
		unless ( -d $sub_path && chdir($sub_path) ) {
			print "FAILED to find $package sources!\n";
			return 0;
		}
	}

	if ( $patches && @$patches[0] ) 
	{
		print "yes, should be patching here!\n";
		foreach $patch ( @$patches ) 
		{
			my $patchbin = $self->find_the_bin("patch");
			my $patch_args = $vals->{'patch_args'} || "";
			if ( $self->syscmd("$patchbin $patch_args < $src/$patch") )
			{
				croak "install_from_source: patch failed: $!\n";
			};
		};
	};

	my $targets = $vals->{'targets'};
	unless ( @$targets[0] ) 
	{
		print "install_from_source: using default targets (./configure, make, make install).\n";
		@$targets = ( "./configure", "make", "make install") 
	};

	foreach my $target ( @$targets ) 
	{ 
		if ( $self->syscmd($target) )
		{
			croak "install_from_source: $target failed: $!\n";
		};
	};

	chdir($src);
	$self->syscmd("rm -rf $package") if ( -d $package );
};

=head2 is_arrayref

Checks whatever object is passed to it to see if it's an arrayref.

   $utility->is_arrayref($testme, $debug);

Enable debugging to see helpful error messages.

=cut

sub is_arrayref($;$)
{
	my ($self, $should_be_arrayref, $debug) = @_;

	my $error;

	unless ( defined $should_be_arrayref ) {
		print "is_arrayref: not defined!\n" if $debug;
		$error++ 
	}

	eval {
		# simply accessing it will generate the exception.
		if ( $should_be_arrayref->[0] ) {
			print "is_arrayref is a arrayref!\n" if $debug;
		};
	};

	if ( $@ ) {
		print "is_arrayref: not a arrayref!\n" if $debug;
		$error++;
	};

	if ( $error ) {
		my ($package, $filename, $line) = caller;
		if ( $package ne "main" ) {
			print "WARNING: Package $package passed $filename an invalid argument " if $debug;
		} else {
			print "WARNING: $filename was passed an invalid argument " if $debug;
		}

		if ($debug) {
			$line ? print "(line $line)\n" : print "\n";
		};
		return 0;
	} else {
		return 1;
	}
}


=head2 is_hashref

Most methods pass parameters around inside hashrefs. Unfortunately, if you try accessing a hashref method and the object isn't a hashref, it generates a fatal exception. This traps that exception and prints a useful error message.

   $utility->is_hashref($hashref, $debug);

=cut

sub is_hashref
{
	my ($self, $should_be_hashref, $debug) = @_;

	my $error;

	unless ( defined $should_be_hashref ) {
		print "is_hashref: not defined!\n" if $debug;
		$error++ 
	}

	eval {
		# simply accessing it will generate the exception.
		if ( $should_be_hashref->{'debug'} ) {
			print "is_hashref is a hashref!\n" if $debug;
		};
	};

	if ( $@ ) {
		print "is_hashref: not a hashref!\n" if $debug;
		$error++;
	};

	if ( $error ) 
	{
		my ($package, $filename, $line) = caller;
		if ( $package ne "main" ) {
			print "WARNING: Package $package was passed an invalid argument " if $debug;
		} else {
			print "WARNING: $filename passed an invalid argument " if $debug;
		}

		if ($debug) {
			$line ? print "(line $line)\n" : print "\n";
		}
		return 0;
	} else {
		return 1;
	}
}


=head2 is_process_running

Verify if a process is running or not.

   $utility->is_process_running($process) ? print "yes" : print "no";

$process is the name as it would appear in the process table.

=cut

sub is_process_running($)
{
	my ($self, $process) = @_;

	my $r = `ps ax | grep $process | grep -v grep`;
	$r ? return 1 : return 0;
};

=head2 logfile_append

   $utility->logfile_append($file, \@lines)

Pass a filename and an array ref and it'll append a timestamp and the array contents to the file. Here's a working example:

   $utility->logfile_append($file, ["proggy", "Starting up", "Shutting down"] )

That will append a line like this to the log file:

   2004-11-12 23:20:06 proggy Starting up
   2004-11-12 23:20:06 proggy Shutting down

=cut

sub logfile_append($$)
{
	my ($self, $file, $lines) = @_;

	if ( $lines && ! $self->is_arrayref($lines) ) {
		my ($package, $filename, $line) = caller;
		croak "WARNING: $filename passed logfile_append an invalid argument\n";
		return 0;
	}

	my ($dd, $mm, $yy, $lm, $hh, $mn, $ss) = $self->get_the_date();
	my $prog = shift @$lines;

	unless ( open FILE, ">>$file" ) {
		carp "logfile_append: couldn't open $file: $!";
		return {error_code=>500, error_desc=>"couldn't open $file: $!"};
	};

	print FILE "$yy-$mm-$dd $hh:$mn:$ss $prog ";

	foreach (@$lines) { print FILE "$_ " };

	print FILE "\n";
	close FILE;

	return { error_code=>200, error_desc=>"file append success" };
};


=head2 mailtoaster

   $utility->mailtoaster();

Downloads and installs Mail::Toaster.

=cut

sub mailtoaster(;$)
{
	my ($self, $debug) = @_;
	my ($conf);

	my $perlbin = $self->find_the_bin("perl");

	my $confcmd = "make newconf";

	if ( -e "/usr/local/etc/toaster-watcher.conf" ) {
		$confcmd = "make conf";
		$conf = $self->parse_config( {file=>"/usr/local/etc/toaster-watcher.conf"} );
	};

	my $archive = "Mail-Toaster.tar.gz";
	my $url     = "/internet/mail/toaster";
	my $ver     = $conf->{'toaster_version'};

	if ($ver) {
		$archive = "Mail-Toaster-$ver.tar.gz";
		$url    = "/internet/mail/toaster/src";
	}

	print "going for archive $archive.\n";

	my  @targets = ("$perlbin Makefile.PL", "make", $confcmd, "make install", "make logs");

	push @targets, "make cgi" unless ($conf && $conf->{'preserve_cgifiles'});
	push @targets, "make test" if $debug;

	my $vals = {
		module   => 'Mail-Toaster',
		archive  => $archive,
		site     => 'http://www.tnpi.biz',
		url      => $url,
		targets  => \@targets,
		debug    => 1,
	};

	eval { require Mail::Toaster::Perl }; my $perl = Mail::Toaster::Perl->new;

	$perl->module_install($vals);
};


=head2 path_parse

   my ($up1dir, $userdir) = $utility->path_parse($dir)

Takes a path like "/usr/home/matt" and returns "/usr/home" and "matt"

You (and I) should be using File::Basename instead as it's more portable.

=cut

sub path_parse($) 
{
	my ($self, $dir) = @_;

	if ( $dir =~ /\/$/ ) { chop $dir };

	my $rindex = rindex($dir, "/");
	my $updir  = substr($dir, 0, $rindex);
	$rindex++;
	my $curdir = substr($dir, $rindex);       

	return $updir, $curdir;
};

=head2 parse_config

   $hashref = {
      file   => $file,    # file to be parsed
      debug  => $debug,   # 
      etcdir => $etcdir,  # where should I find $file?
   };

   $conf = $utility->parse_config( $hashref );

pass parse_config a hashref. $etcdir defaults to /usr/local/etc and will also checks the current working directory. 

A hashref is returned with the key/value pairs.

=cut

sub parse_config($)
{
	my ($self, $vals) = @_;

	my $file  = $vals->{'file'};
	my $debug = $vals->{'debug'};

	my $etcdir = $vals->{'etcdir'};

	unless ( $etcdir && -d $etcdir ) {
		if    ( -e "/usr/local/etc/$file" ) { $etcdir = "/usr/local/etc"; }
		elsif ( -e "/opt/local/etc/$file" ) { $etcdir = "/opt/local/etc"; }
		elsif ( -e "/etc/$file"           ) { $etcdir = "/etc";           }
		else                                { $etcdir = "/usr/local/etc"; };
	};

	if ( -r "$etcdir/$file" )              { $file = "$etcdir/$file" };
	if ( ! -r $file && -r "./$file"      ) { $file = "./$file"      };
	if ( ! -r $file && -r "./$file-dist" ) { $file = "./$file-dist" };

	unless ( -r $file) 
	{
		carp "WARNING: parse_config: can't read $file!\n";
		return 0;
	};

	my (%hash);

	print "using settings from file $file\n" if $debug;
	open(CONFIG, $file) or carp "WARNING: Can't open $file: $!";

	while ( <CONFIG> ) 
	{
		chomp;
		next if /^#/;          # skip lines beginning with #
		next if /^[\s+]?$/;    # skip empty lines
#		print "$_ \t" if $debug;

		# this regexp must match and return these patterns
		# localhost1  = localhost, disk, da0, disk_da0
		# htmldir = /usr/local/rrdutil/html
		# hosts   = localhost lab.simerson.net seattle.simerson.net

		my ($key, $val) = $_ =~ /\s*(.*?)\s*=\s*(.*)\s*$/;
		if ($val && $val =~ /#/) { ($val) = $val =~ /(.*?\S)\s*#/ };

		print "$key \t\t = $val\n" if $vals->{'debug'};

		$hash{$key} = $val if $key;
#		$hash{$key} = $val if $val;
	};

	close(CONFIG);
	return \%hash;
};

=head2 pidfile_check

pidfile_check is a process management method. It will check to make sure an existing pidfile does not exist and if not, it will create the pidfile.

   $pidfile = $utility->pidfile_check("/var/run/program.pid");

The above example is all you need to do to add process checking (avoiding multiple daemons running at the same time) to a program or script. This is used in toaster-watcher.pl and rrdutil. toaster-watcher normally completes a run in a few seconds and is run every 5 minutes. 

However, toaster-watcher can be configured to do things like expire old messages from maildirs and feed spam through a processor like sa-learn. This can take a long time on a large mail system so we don't want multiple instances of toaster-watcher running.

returns the path to the pidfile (on success).

Example:

	my $pidfile = $utility->pidfile_check("/var/run/changeme.pid");
	unless ($pidfile) {
		warn "WARNING: couldn't create a process id file!: $!\n";
		exit 0;
	};

	do_a_bunch_of_cool_stuff;
	unlink $pidfile;

=cut

sub pidfile_check($;$)
{
	my ($self, $pidfile, $debug) = @_;

	# make sure the file & enclosing directory is writable, revert to tmp if not
	unless ( $self->file_check_writable($pidfile, $debug) )
	{
		use File::Basename;
		my ($base, $path, $suffix) = fileparse($pidfile);
		print "NOTICE: using /tmp instead of $path for pidfile\n" if $debug;
		$pidfile = "/tmp/$base";
	};

	if ( -e $pidfile )
	{
		use File::stat;
		my $stats = stat($pidfile);
		my $age   = time() - $stats->mtime;

		if ($age < 3600 )     # if it's less than 1 hour old
		{
			print "\nWARNING! pidfile_check: $pidfile is $age seconds old and might still be running. If this is not the case, please remove it. \n\n";
			return 0;
		} else {
			print "\nWARNING: pidfile_check: $pidfile was found but it's $age seconds old, so I'm ignoring it.\n\n";
		};
	}
	else
	{
		print "pidfile_check: writing process id ", $$, " to $pidfile..." if $debug;
		$self->file_write($pidfile, $$);  # $$ is the process id of this process
		print "done.\n" if $debug;
	};

	return $pidfile;
};


=head1 sources_get

	unless ( -e $tarball ) { 
		$self->sources_get($conf, {package=>$package, site=>$site, url=>$url}) 
	}

Tries to download a set of sources files from the site and url provided. It will try first fetching a gzipped tarball and if that files, a bzipped tarball. As new formats are introduced, I'll expand the support for them here.

=cut

sub sources_get($$;$)
{
	my ($self, $conf, $vals, $debug) = @_;

	unless ( $self->is_hashref($vals) ) {
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename passed install_from_source an invalid argument...exiting \n" if $debug;
		return 0;
	}

	if ( $conf && ! $self->is_hashref($conf) ) {
		my ($package, $filename, $line) = caller;
		carp "WARNING: $filename passed install_from_source an invalid argument...exiting \n" if $debug;
		return 0;
	}

	#print "sources_get: site from vals: " . $vals->{'site'} . "\n";
	#print "sources_get: site from conf: " . $conf->{'toaster_dl_site'} . "\n";

	my $site = $vals->{'site'};           # take a value if given
	$site ||= $conf->{'toaster_dl_site'}; # get from toaster-watcher.conf
	$site ||= "http://www.tnpi.biz";      # if all else fails

	my $url = $vals->{'url'};             # get from passed value
	$url ||= $conf->{'toaster_dl_url'};   # get from toaster-watcher.conf
	$url ||= "/internet/mail/toaster";    # finally, a default

	my $package = $vals->{'package'};
	my $tarball = "$package.tar.gz";     # try gzip first

	unless ( -e $tarball ) {             # check for all the usual suspects
		if ( -e "$package.tgz"     ) { $tarball = "$package.tgz"; };
		if ( -e "$package.tar.bz2" ) { $tarball = "$package.tar.bz2"; };
	};

	if ( -e $tarball && `file $tarball | grep compressed` ) {
		if ( $self->yes_or_no("\n\nYou have a (possibly older) version already downloaded as $tarball. Shall I use it?: ") )
		{
			print "\nok, using existing archive: $tarball\n";
			return 1;
		} else {
			$self->file_delete($tarball);
		};
	};

	$tarball = "$package.tar.gz";     # reset to gzip

	print "sources_get: fetching as gzip $site$url/$tarball...";

	unless ( $self->file_get("$site$url/$tarball", $vals->{'debug'}) )
	{
		carp "install_from_source: couldn't fetch $site$url/$tarball\n";
	} else {
		print "done.\n";
	};

	if ( -e $tarball ) 
	{
		print "sources_get: testing $tarball ...";

		if ( `file $tarball | grep gzip` ) {
			print "sources_get: looks good!\n";
			return 1;
		} else {
			print "YUCK, is not gzipped data!\n";
			$self->file_delete($tarball);
		};
	};

	$tarball = "$package.tar.bz2";

	print "sources_get: fetching as bz2: $site$url/$tarball...";

	unless ( $self->file_get("$site$url/$tarball", $vals->{'debug'}) )
	{
		print "FAILED.\n";
		carp "install_from_source: couldn't fetch $site$url/$tarball\n";
	} else {
		print "done.\n";
	};

	print "sources_get: testing $tarball ...";
	if ( `file $tarball | grep bzip` ) {
		print "ok\n";
		return 1;
	} else {
		print "YUCK, is not bzipped data!!\n";
		$self->file_delete($tarball);
	}

	$tarball = "$package.tgz";

	print "sources_get: fetching as tgz: $site$url/$tarball...";

	unless ( $self->file_get("$site$url/$tarball", $vals->{'debug'}) )
	{
		print "FAILED.\n";
		carp "install_from_source: couldn't fetch $site$url/$tarball\n";
	} else {
		print "done.\n";
	};

	print "sources_get: testing $tarball ...";
	if ( `file $tarball | grep gzip` ) {
		print "ok\n";
		return 1;
	} else {
		print "YUCK, is not bzipped data!!\n";
		$self->file_delete($tarball);
	}

	print "sources_get: FAILED, I am giving up!\n";
	return 0;
}



=head2 source_warning

Just check to see if the sources are present. If they are, offer to remove them.

   $utility->source_warning("Mail-Toaster-4.01", 1, "/usr/local/etc");

returns 1 if removed.

Example: 

   unless ( $utility->source_warning($package, 1, $src) )
   { 
      carp "OK then, skipping install.\n";
      exit 0;
   };

=cut

sub source_warning($;$$)
{
	my ($self, $package, $clean, $src) = @_;

	$src ||= "/usr/local/src";

	print "\n$package sources are already present, indicating that you've already\n";
	print "installed $package. If you want to reinstall it, remove the existing\n";
	print "sources (rm -r $src/mail/$package) and re-run this script\n\n";

	return 0 unless $clean;

	if ( $self->yes_or_no("\n\tWould you like me to remove the sources for you? ") )
	{
		print "Deleting $package...";
		rmtree $package;
		print "done.\n";
		return 1;
	} 
	else 
	{
		return 0;
	};
};

=head2	sudo

   my $sudo = $utility->sudo();

	$utility->syscmd("$sudo rm /etc/root-owned-file");

Often you want to run a script as an unprivileged user. However, the script may need elevated privileges for a plethora of reasons. Rather than running the script suid, or as root, configure sudo allowing the script to run system commands with appropriate permissions.

If sudo is not installed and you're running as root, it'll offer to install sudo for you. This is recommended, as is properly configuring sudo.

=cut

sub sudo(;$)    
{
	my ($self, $debug) = @_;
	my $sudo;

	my $sudobin = $self->find_the_bin("sudo");

	if ( -x $sudobin ) {    # sudo is installed
		if ( $< eq 0 ) {    # we are root
			print "sudo: you are root, sudo isn't necessary.\n" if $debug;
			return $sudo;   # return an empty string for $sudo
		} 
		else 
		{
			print "sudo: sudo is set using $sudobin.\n" if $debug;
			return "$sudobin -p 'Password for %u@%h:'";
		}
	};

	if ( $< eq 0 )
	{
		print "\n\n\tWARNING: Couldn't find sudo. Some features require root ";
		print "permissions and will not work without it. You have been warned!\n\n";
		return $sudo;
	};

	# try installing sudo

	unless ( $self->yes_or_no("sudo is not installed, shall I try to install it?" ) )
	{
		print "very well then, skipping along.\n";
		return $sudo;
	}

	if ( $os eq "freebsd" )
	{
		eval { require Mail::Toaster::FreeBSD };
		if ($@) {
			print "couldn't load Mail::Toaster::FreeBSD!: $@\n";
			print "skipping port install attempt\n";
		} 
		else {
			my $freebsd = Mail::Toaster::FreeBSD->new();
			$freebsd->port_install("sudo", "security");
		};
	}; 

	unless ( -x $self->find_the_bin("sudo") ) 
	{
		# try installing from sources!
		my $vals = { package => 'sudo-1.6.8p2',
				site    => 'http://www.courtesan.com',
				url     => '/sudo/',
				targets => ['./configure', 'make', 'make install'],
				patches => '',
				debug   => 1,
		};
		$self->install_from_source(undef, $vals);
	};

	$sudobin = $self->find_the_bin("sudo");
	return "$sudobin -p 'Password for %u@%h:'" if ( -x $sudobin );
	carp "sudo installation failed!\n";

	return $sudo;
};


=head2 syscmd

Just a little wrapper around system calls, that returns any failure codes and prints out the error(s) if present.

   my $r = $utility->syscmd($cmd);
   $r ? print "not ok!\n" : print "ok.\n";

return is the exit status of the program you called.

=cut

sub syscmd($;$$)
{
	my ($self, $cmd, $fatal, $quiet) = @_;

	my $r = system $cmd;

	if ($? == -1) {
		print "syscmd: $cmd\nfailed to execute: $!\n";
	}
	elsif ($? & 127) {
		print "syscmd: $cmd\n";
		printf "child died with signal %d, %s coredump\n",
		($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
		# all is likely well
		#printf "child exited with value %d\n", $? >> 8;
	}

	if ($r != 0)
	{
		print "syscmd: $cmd\n" unless $quiet;

		if ( defined $fatal && $fatal ) { croak "syscmd: result: $r\n"; } 
		else                            { print "syscmd: result: $r\n" unless $quiet; };
	};

	return $r;
};


=head2 yes_or_no

   my $r = $utility->yes_or_no("Would you like fries with that?");

	$r ? print "fries are in the bag\n" : print "no fries!\n";

There are two optional arguments that can be passed. The first is a string which is the question to ask. The second is an integer representing how long (in seconds) to wait before timing out.

returns 1 on yes, 0 on negative or null response.

=cut

sub yes_or_no(;$$)
{
	my ($self, $question, $timer) = @_;
	my $ans;

	if ($question) {;
		return 1 if ( $question eq "test");
		print "\n\t\t$question";
	};

	print "\n\nYou have $timer seconds to respond: " if $timer;

	# should check for Term::Readkey and use it

	if ($timer) {
		eval {
			local $SIG{ALRM} = sub { die "alarm\n" };
			alarm $timer;
			do {
				print "(y/n): ";
				$ans = lc(<STDIN>); chomp($ans);
			} until ( $ans eq "n" || $ans eq "y" );
			alarm 0;
		};

		if ($@) { 
			($@ eq "alarm\n") ? print "timed out!\n" : carp;  # propagate unexpected errors
		};

		$ans eq "y" ? return 1 : return 0;
	};

	do {
		print "(y/n): ";
		$ans = lc(<STDIN>); chomp($ans);
	} until ( $ans eq "n" || $ans eq "y" );

	$ans eq "y" ? return 1 : return 0;
};


1;
__END__


=head1 AUTHOR

Matt Simerson <matt@cadillac.net>

=head1 BUGS

None known. Report any to author.

=head1 TODO

=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://matt.simerson.net/computing/mail/toaster/


=head1 COPYRIGHT

Copyright 2003-2005, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

