#!/usr/bin/perl
use strict;
use warnings;

#
# $Id: Passwd.pm, matt Exp $
#

package Mail::Toaster::Passwd;

use Carp;

use vars qw/$VERSION/;
$VERSION = '5.07';

use Params::Validate qw( :all );
use English qw( -no_match_vars );

use lib "lib";
use Mail::Toaster::Utility 5; my $utility = Mail::Toaster::Utility->new();
use Mail::Toaster::Perl 5;    my $perl = Mail::Toaster::Perl->new;

sub new {
    my ( $class, $name ) = @_;
    my $self = { name => $name };
    bless $self, $class;
    return $self;
}

sub show {

    my ( $self, $vals ) = @_;

    unless ( $utility->is_hashref($vals) ) {
        print "invalid parameter(s) passed to \$passwd->show\n";
        return {
            'error_code' => 500,
            'error_desc' => 'invalid parameter passed'
        };
    }

    my $user = $vals->{'user'};
    return { 'error_code' => 100, 'error_desc' => 'all is well' }
      if ( $user eq "int-testing" );
    unless ($user) {
        return { 'error_code' => 500, 'error_desc' => 'invalid user' };
    }

    print "user_show: $user show function...\n" if $vals->{'debug'};
    my $sudo = $utility->find_the_bin( bin => "sudo" );
    $utility->syscmd( command => "$sudo quota $user" );
    return { 'error_code' => 100, 'error_desc' => 'all is well' };
}

sub delete {

    my ( $self, $vals ) = @_;

    my $r;

    my $user = $vals->{'user'};
    my $sudo = $utility->sudo();
    my $pw   = $utility->find_the_bin( bin => "pw" );

    if ( $self->exist($user) )    # Make sure user exists
    {
        my $cmd = "$sudo $pw userdel -n $user -r";
        if ( $utility->syscmd( command => $cmd ) ) {
            $r = {
                'error_code' => 200,
                'error_desc' => "delete: success. $user has been deleted."
            };
            return $r;
        }
        else {
            $r = {
                'error_code' => 500,
                'error_desc' => "delete: FAILED. $user not deleted."
            };
            return $r;
        }
    }
    else {
        return {
            'error_code' => 100,
            'error_desc' => "delete: $user does not exist."
        };
    }
}

sub disable {

    my ( $self, $vals ) = @_;

    my $r;

    my $user = $vals->{'user'};
    my $sudo = $utility->sudo();
    my $pw   = $utility->find_the_bin( bin => "pw" );

    if ( getpwnam($user) && getpwnam($user) > 0 )    # Make sure user exists
    {
        my $cmd = "$sudo $pw usermod -n $user -e -1m";
        if ( $utility->syscmd( command => $cmd ) ) {
            $r = {
                'error_code' => 200,
                'error_desc' => "disable: success. $user has been disabled."
            };
            return $r;
        }
        else {
            $r = {
                'error_code' => 500,
                'error_desc' => "disable: FAILED. $user not disabled."
            };
            return $r;
        }
    }
    else {
        return {
            'error_code' => 100,
            'error_desc' => "disable: $user does not exist."
        };
    }
}

sub enable {

    my ( $self, $vals ) = @_;

    my $r;

    my $user = $vals->{'user'};
    my $sudo = $utility->sudo();
    my $pw   = $utility->find_the_bin( bin => "pw" );

    if ( getpwnam($user) && getpwnam($user) > 0 )    # Make sure user exists
    {
        my $cmd = "$sudo $pw usermod -n $user -e ''";
        if ( $utility->syscmd( command => $cmd ) ) {
            $r = {
                'error_code' => 200,
                'error_desc' => "enable: success. $user has been enabled."
            };
            return $r;
        }
        else {
            $r = {
                'error_code' => 500,
                'error_desc' => "enable: FAILED. $user not enabled."
            };
            return $r;
        }
    }
    else {
        return {
            'error_code' => 100,
            'error_desc' => "disable: $user does not exist."
        };
    }
}

sub encrypt {

    my ( $self, $pass, $debug ) = @_;

    $perl->module_load(
            module     => "Crypt::PasswdMD5",
            port_name  => "p5-Crypt-PasswdMD5",
            port_group => "security"
    );

    my $salt   = rand;
    my $pass_e = Crypt::PasswdMD5::unix_md5_crypt( $pass, $salt );

    print "encrypt: pass_e = $pass_e\n" if $debug;
    return $pass_e;
}

sub exist {

    my ( $self, $user ) = @_;
    $user = lc($user);

    if ( getpwnam($user) && getpwnam($user) > 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub sanity {

    my ( $self, $pass, $user ) = @_;
    my %r = ( error_code => 400 );

    # min 6 characters
    if ( length($pass) < 6 ) {
        $r{'error_desc'} =
          "Passwords must have at least six characters. $pass is too short.";
        return \%r;
    }

    # max 128 characters
    if ( length($pass) > 128 ) {
        $r{'error_desc'} =
          "Passwords must have no more than 128 characters. $pass is too long.";
        return \%r;
    }

    # not purely alpha or numeric
    if ( $pass =~ /a-z/ or $pass =~ /A-Z/ or $pass =~ /0-9/ ) {
        $r{'error_desc'} = "Passwords must contain both letters and numbers!";
        return \%r;
    }

    # does not match username
    if ( $pass eq $user ) {
        $r{'error_desc'} = "The username and password must not match!";
        return \%r;
    }

    if ( -r "/usr/local/etc/passwd.badpass" ) {
        my @lines =
          $utility->file_read( file => "/usr/local/etc/passwd.badpass" );
        foreach my $line (@lines) {
            chomp $line;
            if ( $pass eq $line ) {
                $r{'error_desc'} =
                  "$pass is a weak password. Please select another.";
                return \%r;
            }
        }
    }

    $r{'error_code'} = 100;
    return \%r;
}

sub BackupMasterPasswd {

    my ( $self, $file ) = @_;

    $file ||= "/etc/master.passwd";

    my $sudo = $utility->sudo();
    my $cp   = $utility->find_the_bin( bin => "cp", debug => 0 );
    my $cmd  = $sudo;
    $cmd .= "$cp $file $file.bak";

    $utility->syscmd( command => $cmd, debug => 0 );

    #   this only works if we have root permissions
    #	use File::Copy;
    #	copy($file, "$file.bak")
    #		or carp "FATAL: Couldn't back up $file: $!\n";
}

sub VerifyMasterPasswd {

    my ( $self, $passwd, $change, $debug ) = @_;
    my %r;

    my $new = ( stat($passwd) )[7];
    my $old = ( stat("$passwd.bak") )[7];

    # do we expect it to change?
    if ($change) {
        if ( $change eq "grow" ) {
            if ( $new > $old ) {

                # yay, it grew. response with a success code
                print
                  "VerifyMasterPasswd: The file grew ($old to $new) bytes.\n"
                  if $debug;
                $r{'error_code'} = 200;
                $r{'error_desc'} =
                  "Success: the file grew from $old to $new bytes.";
                return \%r;
            }
            else {

                # boo, it didn't grow. return a failure code and
                # make an archived copy of it for recovery
                print
"VerifyMasterPasswd: WARNING: new $passwd size ($new) is not larger than $old and we expected it to $change.\n"
                  if $debug;
                $utility->file_archive( file => "$passwd.bak" );
                $r{'error_code'} = 500;
                $r{'error_desc'} =
"new $passwd size ($new) is not larger than $old and we expected it to $change.\n";
                return \%r;
            }
        }
        elsif ( $change eq "shrink" ) {
            if ( $new < $old ) {

                # yay, it shrank. response with a success code
                print
                  "VerifyMasterPasswd: The file shrank ($old to $new) bytes.\n"
                  if $debug;
                $r{'error_code'} = 200;
                $r{'error_desc'} = "The file shrank from $old to $new bytes.\n";
                return \%r;
            }
            else {

                # boo, it didn't shrink. return a failure code and
                # make an archived copy of it for recovery
                print
"VerifyMasterPasswd: WARNING: new $passwd size ($new) is not smaller than $old and we expected it to $change.\n"
                  if $debug;
                $r{'error_code'} = 500;
                $r{'error_desc'} =
"new $passwd size ($new) is not smaller than $old and we expected it to $change.\n";
                $utility->file_archive( file => "$passwd.bak" );
                return \%r;
            }
        }
    }

    # just report
    if ( $new == $old ) {
        print "VerifyMasterPasswd: The files are the same size ($new)!\n"
          if $debug;
    }
    else {
        print
"VerifyMasterPasswd: The files are different sizes new: $new old: $old!\n"
          if $debug;
    }
}

sub creategroup {

    my $self = shift;

    # parameter validation

    my %p = validate( @_, {
            'group'   => { type=>SCALAR },
            'gid'     => { type=>SCALAR,  optional=>1, },
            'fatal'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'debug'   => { type=>BOOLEAN, optional=>1, default=>1 },
            'test_ok' => { type=>BOOLEAN, optional=>1, },
        },
    );

    my ( $group, $gid, $fatal, $debug, $test_ok )
        = ( $p{'group'}, $p{'gid'}, $p{'fatal'}, $p{'debug'}, $p{'test_ok'} );

    # see if the group exists
    my $r = getgrnam($group);

    if ($r) {
        $self->_formatted( "creategroup: $group installed (gid: $r)",
            "ok (exists)" )
          if $debug;
        return 2;
    }

    if ( $OSNAME eq "freebsd" ) {

        # use the pw tool to add the user
        my $pw = $utility->find_the_bin( bin => "pw", debug => 0 );

        my $cmd = "$pw groupadd -n $group";
        $cmd .= " -g gid" if $gid;

        $utility->syscmd( command => $cmd, debug => $debug );
    }
    elsif ( $OSNAME eq "darwin" ) {
        print "creategroup: $group on detected MacOS (Darwin)\n" if $debug;

        my $niutil = $utility->find_the_bin( bin => "niutil" );
        $utility->syscmd( command => "$niutil -create . /groups/$group" );
        $utility->syscmd(
            command => "$niutil -createprop . /groups/$group gid $gid" )
          if $gid;
        $utility->syscmd(
            command => "$niutil -createprop . /groups/$group passwd '*'" );
    }
    else {

        $self->_formatted(
            "creategroup: adding group $group on $OSNAME OS: no support!",
            "FAILED" );
        print
          "creategroup: You must add the group $group (gid: $gid) manually.\n"
          if $debug;
        return 0;
    }

    $self->_formatted( "creategroup: installing $group on $OSNAME OS", "ok" )
      if $debug;
}

sub user_add {

    my ( $self, $vals ) = @_;

    my ( $r, $sudo );

    my $user    = $vals->{'username'};
    my $shell   = $vals->{'shell'};
    my $homedir = $vals->{'homedir'};
    my $debug   = $vals->{'debug'};
    my $uid     = $vals->{'uid'};
    my $gid     = $vals->{'gid'};

    print "user_add: begin..." if $debug;

    # make sure we got passed a username
    unless ($user) {
        carp "user_add: no valid username!\n";
        return {
            'error_code' => 400,
            'error_desc' => "user_add: you must pass a username!"
        };
    }

    print "testing username validity..." if $debug;
    $r = $self->user_sanity($user);
    if ( ! $r->{'error_code'} == 200 ) {
        carp "user_add: username invalid!\n";
        return $r;
    }
    print "ok..." if $debug;

    # set a default shell
    $shell ||= "/sbin/nologin";

    # finally, create the user
    if ( $OSNAME eq "freebsd" ) {

        print "OS is FreeBSD..." if $debug;

        # use sudo if we're not running as root
        unless ( $< eq 0 ) {
            $sudo = $utility->find_the_bin( bin => "sudo",debug=>0 );
            unless ( -x $sudo ) {
                $r = {
                    'error_code' => 401,
                    'error_desc' =>
"user_add: adding users requires root or sudo and you have neither!"
                };
                return $r;
            }
        }
        print "root or sudo passed for uid $>..." if $debug;

        # pw creates accounts using defaults from /etc/pw.conf
        # values passed to user_add will override the defaults

        my $pw    = $utility->find_the_bin( bin => "pw",debug=>0 );
        my $pwcmd = "$sudo $pw useradd -n $user ";

        $pwcmd .= "-d $homedir "                    if $homedir;
        $pwcmd .= "-u $uid "                        if $uid;
        $pwcmd .= "-g $gid "                        if $gid;
        $pwcmd .= "-c $vals->{'gecos'} "            if $vals->{'gecos'};
        $pwcmd .= "-u 89 -g 89 -c Vpopmail-Master " if ( $user eq "vpopmail" );
        $pwcmd .= "-n $user -d /nonexistent -c Clam-AntiVirus "
          if ( $user eq "clamav" );
        $pwcmd .= "-s $shell ";
        $pwcmd .= "-m ";

        print "\npw command is: \n$pwcmd\n" if $debug;

        if ( $vals->{'pass'} ) {
            print "\npw command is: \n$pwcmd -h 0 (****)\n" if $debug;

            ## no critic
            my $FH;
            unless ( open $FH, "| $pwcmd -h 0" ) {
                $r = {
                    'error_code' => 401,
                    'error_desc' => "user_add: opening pw failed for $user."
                };
                return $r;
            }
            print $FH "$vals->{'pass'}\n";
            close $FH;
            ## use critic
        }
        else {
            print "\npw command is: \n$pwcmd -h-\n" if $debug;
            $utility->syscmd( command => "$pwcmd -h-",debug=>0 );
        }

        print "user_add: user add passed..." if $debug;

        # verify that it's now in the pw database
        if ( $self->exist($user) ) {
            print "yay, verified addition..." if $debug;
            $r = {
                'error_code' => 200,
                'error_desc' => "user_add: added $user."
            };
            return $r;
        }
        else {

            # the user add failed for some reason
            $r = {
                'error_code' => 500,
                'error_desc' => "user_add: FAILED to add $user."
            };
            return $r;
        }
    }
    elsif ( $OSNAME eq "darwin" ) {
        print "user_add: $user on detected MacOS (Darwin)\n";

        my $niutil = $utility->find_the_bin( bin => "niutil", debug => 0 );
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -create . /users/$user"
        );
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -createprop . /users/$user uid $uid"
        ) if $uid;
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -createprop . /users/$user gid $gid"
        ) if $gid;
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -createprop . /users/$user shell $shell"
        );
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -createprop . /users/$user home $homedir"
        ) if $homedir;
        $utility->syscmd(
            debug   => 0,
            command => "$niutil -createprop . /users/$user passwd '*'"
        );
        $utility->syscmd( debug => 0, command => "chown -R $user $homedir" )
          if $homedir;
    }
    else {
        $r = {
            'error_code' => 403,
            'error_desc' =>
"user_add: $user on detected $OSNAME FAILED! There is no support for adding users on $OSNAME yet!"
        };

        print "user_add: $user on detected $OSNAME \n";
        print "FAILED: I don't (yet) know how to add users on your platform!\n";
        return $r;
    }

    $r = {
        'error_code' => 200,
        'error_desc' => "user_add: user $user added successfully."
    };
    return $r;
}

sub user_archive {

    my ( $self, $user, $debug ) = @_;

    my $tar  = $utility->find_the_bin( bin => "tar" );
    my $sudo = $utility->find_the_bin( bin => "sudo" );
    my $rm   = $utility->find_the_bin( bin => "rm" );

    unless ( $self->exist($user) ) {
        $utility->graceful_exit( "400", "That user does not exist!" );
    }

    my $homedir = ( getpwnam($user) )[7];
    unless ( -d $homedir ) {
        $utility->graceful_exit( "400", "The home directory does not exist!" );
    }

    my ( $path, $userdir ) = $utility->path_parse($homedir);

    unless ( chdir($path) ) {
        $utility->graceful_exit( "400", "couldn't cd to $path: $!\n" );
    }

    if ( -e "$path/$user.tar.gz" && -d "$path/$user" ) {
        carp "user_archive:\tReplacing old tarfile $path/$user.tar.gz.\n";
        system "$sudo $rm $path/$user.tar.gz";
    }

    print "\tArchiving $user\'s files to $path/$user.tar.gz...." if $debug;
    print "$sudo $tar -Pzcf $homedir.tar.gz $userdir\n";
    system "$sudo $tar -Pzcf $homedir.tar.gz $userdir";

    if ( -e "${homedir}.tar.gz" ) {
        print "done.\n" if $debug;
        return 1;
    }
    else {
        carp "\nFAILED: user_archive couldn't complete $homedir.tar.gz.\n\n";
        return 0;
    }
}

sub user_sanity {

    my ( $self, $user, $disallow ) = @_;

    # set this to fully define your username restrictions. It will
    # get returned every time an invalid password is submitted.

    my $error =
"Usernames must be 2 to 16 lower case alpha or numeric characters. The username must begin with an alpha character.";

    # min 2 characters
    # max 16 characters
    # only lower case letters
    # only lower case letters and numbers
    # begin with an alpha character

    unless ( $user =~ /^[a-z][a-z0-9]{1,15}$/ ) {
        return {
            error_code => 400,
            error_desc => "$error. $user is not a valid username."
        };
    }

    if ($disallow) {
        if ( defined $disallow->{$user} ) {
            return {
                error_code => 400,
                error => "$user is a reserved username. Please select another.",
                error_desc =>
                  "$user is a reserved username. Please select another."
            };
        }
    }

    if ( -r "/usr/local/etc/passwd.reserved" ) {
        my @lines =
          $utility->file_read( file => "/usr/local/etc/passwd.reserved" );
        foreach my $line (@lines) {
            chomp $line;
            if ( $user eq $line ) {
                return {
                    error_code => 400,
                    error      =>
                      "$user is a reserved username. Please select another.",
                    error_desc =>
                      "$user is a reserved username. Please select another."
                };
            }
        }
    }

    if ( $self->exist($user) ) {

        # get the users uid (if exists)
        my $uid_exist = getpwnam($user);

        print "user $user (uid: $uid_exist) already exists\n";
        return {
            error_code => 400,
            error      =>
              "user sanity: user $user already exists (uid: $uid_exist)!",
            error_desc =>
              "user sanity: user $user already exists (uid: $uid_exist)!"
        };
    }

    return { 'rc' => 1, error_code => 200, error_desc => 'no error' };
}

sub _formatted {
    my ( $self, $mess, $result ) = @_;

    my $dots;
    my $len = length($mess);
    if ( $len < 65 ) {
        until ( $len == 65 ) { $dots .= "."; $len++ }
    }
    print "$mess $dots $result\n";
}


1;
__END__


=head1 NAME

Mail::Toaster::Passwd - add/delete entries from Unix /etc/passwd database


=head1 SYNOPSIS

Common Unix Passwd functions

=head1 DESCRIPTION

A grouping of frequently used functions I've written for interacting with /etc/passwd entries.

=head1 DEPENDENCIES

Crypt::PasswdMD5 - /usr/ports/security/p5-Crypt-PasswdMD5

=head1 METHODS

=over

=item new

Before calling any of the methods, you must create a password object:

  use Mail::Toaster::Passwd;
  my $pass = Mail::Toaster::Passwd->new;


=item show

Show user attributes. Right now it only shows quota info.

   $pass->show( {user=>"matt"} );

input is a hashref

returns a hashref with error_code and error_desc


=item delete

Delete an /etc/passwd user.

  $pass->delete( {user=>"matt"} );

input is a hashref

returns a hashref with error_code and error_desc


=item disable

Disable an /etc/passwd user by expiring their account.

  $pass->disable( {user=>"matt"} );

input is a hashref

returns a hashref with error_code and error_desc


=item enable

Enable an /etc/passwd user by removing the expiration date.

  $pass->enable( {user=>"matt"} );

input is a hashref

returns a hashref with error_code and error_desc


=item encrypt

	$pass->encrypt ($pass, $debug)

encrypt (MD5) the plain text password that arrives at $pass.


=item exist

Check to see if a user exists

	$pass->exist($user);

I use this before adding a new user (easy error trapping) and again after adding a user (to verify success). 

	unless ( $pass->exist($user) ) {
		$pass->user_add( {user=>$user} );
	};

$user is the username you are adding. 

returns 1 if exists, 0 otherwise


=item sanity

Check a password for sanity.

    use Mail::Toaster::Passwd;
    my $pass = Mail::Toaster::Passwd->new();

    $r =  $pass->sanity($password, $username);

    if ( $r->{'error_code'}==100 ) {  print "success"    }
    else                           {  print $r->{'error' };


$password  is the password the user is attempting to use.

$username is the username the user has selected. 

Checks: 

    Passwords must have at least 6 characters.
    Passwords must have no more than 128 characters.
    Passwords must not be the same as the username
    Passwords must not be purely alpha or purely numeric
    Passwords must not be in reserved list 
       (/usr/local/etc/passwd.badpass)

$r is a hashref that gets returned.

$r->{'error_code'} will contain a result code of 100 (success) or (4-500) (failure)

$r->{'error_desc'} will contain a string with a description of which test failed.


=item BackupMasterPasswd

	$pass->BackupMasterPasswd($file)

Back up the /etc/master.passwd database. This copies $file to a new file named $file.bak.


=item VerifyMasterPasswd

    my $r = $pass->VerifyMasterPasswd ($passwd, $change, $debug)

    $r->{'error_code'} == 200 ? print "success" : print $r->{'error_desc'}; 

Verify that new master.passwd is the right size. I found this necessary on some versions of FreeBSD as a race condition would cause the master.passwd file to get corrupted. Now I verify that after I'm finished making my changes, the new file is a small amount larger (or smaller) than the original.

$passwd is the filename of your master.passwd file.

$change is whether the file should "shrink" or "grow"


=item creategroup

Installs a system group. The $gid is optional.

    $r = $pass->creategroup($group, $gid)

    $r->{'error_code'} == 200 ? print "success" : print $r->{'error_desc'}; 


=item user_add

Installs a system user. Expects a hashref to be passed containing at least: user. Optional values can be set for: pass, shell, homedir, gecos, quota, uid, gid, expire, domain.

    my $r = $pass->user_add( {user=>"sample"} );

    $r->{'error_code'} == 200 ? print "success" : print $r->{'error_desc'}, "\n";

returns a HTTP style result code (200 success, 400 bad, 401 unauthorized, 500 error)


=item user_archive

Create's a tarball of the users home directory. Typically done right before you rm -rf their home directory as part of a de-provisioning step.

    if ( $prov->user_archive("user") ) 
    {
        print "user archived";
    };

returns a boolean.


=item user_sanity

   $r = $pass->user_sanity($user, $denylist);

   if ( $r->{'error_code'} eq 200 ) {  print "success"    }
   else                             {  print $r->{'error_desc' };

$user is the username. Pass it along as a scalar (string).

$denylist is a optional hashref. Define all usernames you want reserved (denied) and it'll check to make sure $user is not in the hashref.

Checks:

   * Usernames must be between 2 and 16 characters.
   * Usernames must have only lower alpha and numeric chars
   * Usernames must begin with an alpha character
   * Username must not be defined in $denylist hash
   * If the file /usr/local/etc/passwd.reserved exists, 
     the username must not exist in that file. 

The format of passwd.reserved is simply one username per line.
	
A hashref gets returned that will contain at least error_code, and error_desc. 

$r->{'error_code'} will contain a result code of 0 (failure) or a positive number for (success). 

$r->{'error_desc'} will contain a string with a description of which test failed.


=back


=head1 AUTHOR

Matt Simerson <matt@tnpi.net>


=head1 BUGS

None known. Report any to author.


=head1 TODO

Don't export any of the symbols by default. Move all symbols to EXPORT_OK and explicitely pull in the required ones in programs that need them. - done!


=head1 SEE ALSO

The following are all man/perldoc pages: 

 Mail::Toaster 
 Mail::Toaster::Conf
 toaster.conf
 toaster-watcher.conf

 http://mail-toaster.org/


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2003-2006, The Network People, Inc. All Rights Reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

Neither the name of the The Network People, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
