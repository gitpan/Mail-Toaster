#!/usr/bin/perl
#
# t/Utility.t - test suite written by Matt Simerson in 2006
#
use strict;
use warnings;

use lib "inc";
use lib "lib";

use Cwd;
use English qw( -no_match_vars );
use Test::More 'no_plan';

my $deprecated = 0;    # run the deprecated tests.
my $network = 0;       # run tests that require network
$network = 1 if $OSNAME =~ /freebsd|darwin/;
my $r;

BEGIN { use_ok('Mail::Toaster::Utility'); }
require_ok('Mail::Toaster::Utility');

# let the testing begin

# basic OO mechanism
my $util = new Mail::Toaster::Utility;    # create an object
ok( defined $util, 'get Mail::Toaster::Utility object' );    # check it
isa_ok( $util, 'Mail::Toaster::Utility' );    # is it the right class

# for internal use only
if ( -e "Utility.t" ) { chdir "../"; }

# we need this stuff during subsequent tests
my $debug = 0;
my ($cwd) = cwd =~ /^([\/\w\-\s\.]+)$/;          # get our current directory

print "\t\twd: $cwd\n" if $debug;

my $tmp = "$cwd/t/trash";
ok( $util->mkdir_system( dir => $tmp, debug => 0, fatal => 0 ), 'mkdir_system' );
ok( -d $tmp, "temp dir: $tmp" );
ok( $util->syscmd( cmd => "cp TODO $tmp/", debug => 0, fatal => 0 ), 'cp TODO' );

# answer - asks a question and retrieves the answer
SKIP: {
    skip "answer is an interactive only feature", 4 unless $util->is_interactive;
    ok( $r = $util->answer(
            q       => 'test yes answer',
            default => 'yes',
            timeout => 5
        ),
        'answer, proper args'
    );
    is( lc($r), "yes", 'answer' );
    ok( $r = $util->answer( q => 'test any (non empty) answer' ),
        'answer, tricky' );

    # multiline prompt
    ok( $r = $util->answer( 
            q => 'test any (non empty) answer',
            default => 'just hit enter',
        ),
        'answer, multiline' );

    # default password prompt
    ok( $r = $util->answer( 
            question => 'type a secret word',
            password => 1,
            default  => 'secret',
        ),
        'answer, password' );
}

# archive_expand
my $gzip = $util->find_the_bin( bin => "gzip", fatal => 0, debug => 0 );
my $tar  = $util->find_the_bin( bin => "tar",  fatal => 0, debug => 0 );

SKIP: {
    skip "gzip or tar is missing!\n", 6 unless ( -x $gzip and -x $tar );
    ok( $util->syscmd(
            cmd   => "$tar -cf $tmp/test.tar TODO",
            debug => 0,
            fatal => 0
        ), "tar -cf test.tar"
    );
    ok( $util->syscmd(
            cmd   => "$gzip -f $tmp/test.tar",
            debug => 0,
            fatal => 0
        ), 'gzip test.tar'
    );

    my $archive = "$tmp/test.tar.gz";
    ok( -e $archive, 'temp archive exists' );

    ok( $util->archive_expand(
            archive => $archive,
            debug   => 0,
            fatal   => 0
        ), 'archive_expand'
    );

    eval {
        ok( !$util->archive_expand(
                archie => $archive,
                debug  => 0,
                fatal  => 0
            ), 'archive_expand'
        );
    };

    # clean up behind the tests
    ok( $util->file_delete( file => $archive, fatal => 0, debug => 0 ),
        'file_delete' );
}

#	TODO: { my $why = "archive_expand, requires a valid archive to expand";
#			this way to run them but not count them as failures
#			local $TODO = $why if (! -e $archive);
#			this way to skip them entirely and mark as TODO
#			todo_skip $why, 3 if (! -e $archive); #}

# chdir_source_dir
# dir already exists
ok( $util->chdir_source_dir( dir => $tmp, debug => 0 ),
    'chdir_source_dir' );

# clean up after previous runs
if ( -f "$tmp/foo" ) {
    ok( $util->file_delete( file => "$tmp/foo", fatal => 0, debug => 0 ),
        'file_delete' );
}

# a dir to create
ok( $util->chdir_source_dir( dir => "$tmp/foo", debug => 0 ),
    'chdir_source_dir' );
print "\t\t wd: " . cwd . "\n" if $debug;

# go back to our previous working directory
chdir($cwd) or die;
print "\t\t wd: " . cwd . "\n" if $debug;

# check_homedir_ownership
TODO: {
    my $why = "check_homedir_ownership: only tested on FreeBSD & darwin.\n";
    local $TODO = $why unless ( $OSNAME eq "freebsd" or $OSNAME eq "darwin" );

    # will check to make sure each users home directory is owned by them
    ok( $util->check_homedir_ownership( test_ok=>1, debug => 0 ),
        'check_homedir_ownership' );

    # test in automatic repair mode
    ok( $util->check_homedir_ownership( test_ok=>1, auto => 1, debug => 0 ),
        'check_homedir_ownership' );

    ok( ! $util->check_homedir_ownership( test_ok=>0, auto => 1, debug => 0 ),
        'check_homedir_ownership' );
}

# chown_system
if ( $UID == 0 ) {
    # avoid the possiblity of a sudo call in testing
    ok( $util->chown_system( dir => $tmp, user => $<, debug => 0 ),
        'chown_system' );
};

# check_pidfile - deprecated (see pidfile_check)

# clean_tmp_dir
TODO: {
    my $why = " - no test written yet";
}
ok( $util->clean_tmp_dir( dir => $tmp, debug => 0 ), 'clean_tmp_dir' );

print "\t\t wd: " . cwd . "\n" if $debug;

# drives_get_mounted
ok( my $drives = $util->drives_get_mounted( debug => 0 ),
    'drives_get_mounted' );
ok( $util->is_hashref($drives), 'drives_get_mounted' );
isa_ok( $drives, 'HASH' );

# example code working with the mounts
#foreach my $drive (keys %$drives) {
#	print "drive: $drive $drives->{$drive}\n";
#}

# file_* tests

TODO: {
    my $why = " - user may not want to run extended tests";

    # this way to run them but not count them as failures
    local $TODO = $why if ( -e '/dev/null' );

#$extra = $util->yes_or_no( question=>"can I run extended tests?", timeout=>5 );
#ok ( $extra, 'yes_or_no' );
}


# file_read
my $rwtest = "$tmp/rw-test";
ok( $util->file_write(
        file  => $rwtest,
        lines => ["erase me please"],
        debug => 0
    ),
    'file_write'
);
my @lines = $util->file_read( file => $rwtest );
ok( @lines == 1, 'file_read' );


# file_append
# a typical invocation
ok( $util->file_write(
        file   => $rwtest,
        lines  => ["more junk"],
        append => 1,
        debug  => 0
    ),
    'file_append'
);


# file_archive
# a typical invocation
my $backup
    = $util->file_archive( file => $rwtest, debug => 0, fatal => 0 );
ok( -e $backup, 'file_archive' );
ok( $util->file_delete( file => $backup, debug => 0, fatal => 0 ),
    'file_delete' );

ok( !$util->file_archive( file => $backup, debug => 0, fatal => 0 ),
    'file_archive' );

#    eval {
#        # invalid param, will raise an exception
#	    $util->file_archive( fil=>$backup, debug=>0,fatal=>0 );
#    };
#	ok( $EVAL_ERROR , "file_archive");

# file_check_[readable|writable]
# typical invocation
ok( $util->is_readable( file => $rwtest, fatal => 0, debug => 1 ),
    'is_readable' );

# an invocation for a non-existing file (we already deleted it)
ok( !$util->is_readable( file => $backup, fatal => 0, debug => 0 ),
    'is_readable - negated'
);

ok( $util->is_writable( file => $rwtest, debug => 0, fatal => 0 ),
    'is_writable' );

# file_get
SKIP: {
    skip "avoiding network tests", 2 if (! $network);

    ok( $util->chdir_source_dir( dir => $tmp, debug => 0 ),
        'chdir_source_dir' );

    ok( $util->file_get(
            url =>
                "http://mail-toaster.org/etc/maildrop-qmail-domain",
            debug => 0
        ), 'file_get'
    );
}

chdir($cwd);
print "\t\t  wd: " . Cwd::cwd . "\n" if $debug;

# file_chown
my $uid = getpwuid($UID);
my $gid = getgrgid($GID);

SKIP: {
    skip "the temp file for file_ch* is missing!", 4 if ( !-f $rwtest );

    # try one that should work
    ok( $util->file_chown(
            file  => $rwtest,
            uid   => $uid,
            gid   => $gid,
            debug => 0, sudo  => 0, fatal => 0 ), 'file_chown uid'
    );

    if ( $UID == 0 ) {
        ok( $util->file_chown(
                file  => $rwtest,
                uid   => "root",
                gid   => "wheel",
                debug => 0, sudo  => 0, fatal => 0 ), 'file_chown user'
        );
    };

    # try a user/group that does not exist
    ok( !$util->file_chown(
            file  => $rwtest,
            uid   => 'frobnob6i',
            gid   => 'frobnob6i',
            debug => 0, sudo  => 0, fatal => 0 ), 'file_chown nonexisting uid'
    );

    # try a user/group that I may not have permission to
    if ( $UID != 0 ) {
        ok( !$util->file_chown(
                file  => $rwtest,
                uid   => 'root',
                gid   => 'wheel',
                debug => 0, sudo  => 0, fatal => 0), 'file_chown no perms'
        );
    }
}


# tests system_chown because sudo is set, might cause testers to freak out
#		ok ($util->file_chown( file => $rwtest,
#			uid=>$uid, gid=>$gid, debug=>0, sudo=>1, fatal=>0 ), 'file_chown');
#		ok ( ! $util->file_chown( file => $rwtest,
#			uid=>'frobnob6i', gid=>'frobnob6i', debug=>0, sudo=>1, fatal=>0 ), 'file_chown');
#		ok ( ! $util->file_chown( file => $rwtest,
#			uid=>'root', gid=>'wheel',debug=>0, sudo=>1,fatal=>0), 'file_chown');


# file_chmod
# get the permissions of the file in octal file mode
use File::stat;
my $st = stat($rwtest) or warn "No $tmp: $!\n";
my $before = sprintf "%lo", $st->mode & 07777;

#$util->syscmd( command=>"ls -al $rwtest" );   # use ls -al to view perms

# change the permissions to something slightly unique
ok( $util->file_chmod(
        file_or_dir => $rwtest,
        mode        => '0700',
        debug       => 0
    ),
    'file_chmod'
);


# file_mode
my $result_mode = $util->file_mode(
    file => $rwtest,
    debug => 0,
);
cmp_ok( $result_mode, '==', 700, 'file_mode');


#$util->syscmd( command=>"ls -al $rwtest" );

# and then set them back
ok( $util->file_chmod(
        file_or_dir => $rwtest,
        mode        => $before,
        debug       => 0
    ),
    'file_chmod'
);

#$util->syscmd( command=>"ls -al $rwtest" );

# file_write
ok( $util->file_write(
        file  => $rwtest,
        lines => ["17"],
        debug => 0,
        fatal => 0
    ),
    'file_write'
);

#$ENV{PATH} = ""; print `/bin/cat $rwtest`;
#print `/bin/cat $rwtest` . "\n";

# files_diff
# we need two files to work with
$backup = $util->file_archive( file => $rwtest, debug => 0 );

# these two files are identical, so we should get 0 back from files_diff
ok( !$util->files_diff( f1 => $rwtest, f2 => $backup, debug => 0 ),
    'files_diff' );

# now we change one of the files, and this time they should be different
$util->file_write(
    file   => $rwtest,
    lines  => ["more junk"],
    debug  => 0,
    append => 1
);
ok( $util->files_diff( f1 => $rwtest, f2 => $backup, debug => 0 ),
    'files_diff' );

# make it use md5 checksums to compare
$backup = $util->file_archive( file => $rwtest, debug => 0 );
ok( !$util->files_diff(
        f1    => $rwtest,
        f2    => $backup,
        debug => 0,
        type  => 'binary'
    ),
    'files_diff'
);

# now we change one of the files, and this time they should be different
sleep 1;
$util->file_write(
    file   => $rwtest,
    lines  => ["extra junk"],
    debug  => 0,
    append => 1
);
ok( $util->files_diff(
        f1    => $rwtest,
        f2    => $backup,
        debug => 0,
        type  => 'binary'
    ),
    'files_diff'
);

# file_is_newer
#

# find_the_bin
# a typical invocation
my $rm = $util->find_the_bin( program=>"rm", debug=>0,fatal=>0 );
ok( $rm && -x $rm, 'find_the_bin' );

# a test that should fail
ok( ! $util->find_the_bin(bin=>"globRe", fatal=>0, debug=>0 ), 'find_the_bin' );

# a shortcut that should work
$rm = $util->find_the_bin( bin => "rm", debug => 0 );
ok( -x $rm, 'find_the_bin' );

# fstab_list
my $fs = $util->fstab_list( debug => 1 );
if ($fs) {
    ok( $fs, 'fstab_list' );

    #foreach (@$fs) { print "\t$_\n"; };
}

# get_dir_files
my (@list) = $util->get_dir_files( dir => "/etc" );
ok( -e $list[0], 'get_dir_files' );


# get_my_ips
SKIP: {
    skip "avoiding network tests", 1 if (! $network);

    # need to update this so it works on netbsd & solaris
    ok( $util->get_my_ips(exclude_internals=>0), 'get_my_ips');
}


# get_the_date
my $mod = "Date::Format";
if ( eval "require $mod" ) {

    ok( @list = $util->get_the_date( debug => 0 ), 'get_the_date' );

    my $date = $util->find_the_bin(bin=>"date", debug=>0);
    cmp_ok( $list[0], '==', `$date '+%d'`, 'get_the_date day');
    cmp_ok( $list[1], '==', `$date '+%m'`, 'get_the_date month');
    cmp_ok( $list[2], '==', `$date '+%Y'`, 'get_the_date year');
    cmp_ok( $list[4], '==', `$date '+%H'`, 'get_the_date hour');
    cmp_ok( $list[5], '==', `$date '+%M'`, 'get_the_date minutes');
    # this will occasionally fail tests
    #cmp_ok( $list[6], '==', `$date '+%S'`, 'get_the_date seconds');

    @list = $util->get_the_date( bump => 1, debug => 0 );
    cmp_ok( $list[0], '!=', `$date '+%d'`, 'get_the_date day');
    cmp_ok( $list[1], '==', `$date '+%m'`, 'get_the_date month');
    cmp_ok( $list[2], '==', `$date '+%Y'`, 'get_the_date year');
    cmp_ok( $list[4], '==', `$date '+%H'`, 'get_the_date hour');
    cmp_ok( $list[5], '==', `$date '+%M'`, 'get_the_date minutes');
}
else {
    ok( 1, 'get_the_date - skipped (Date::Format not installed)' );
}

exit;

# graceful_exit

# install_if_changed
$backup = $util->file_archive( file => $rwtest, debug => 0, fatal => 0 );

# call it the new way
ok( $util->install_if_changed(
        newfile  => $backup,
        existing => $rwtest,
        mode     => '0644',
        debug    => 0,
        notify   => 0,
        clean    => 0,
    ),
    'install_if_changed'
);

# install_from_sources_php
# sub is incomplete, so are the tests.

# install_from_source
ok( $util->install_from_source(
        conf           => { foo     => 1 },
        package        => "ripmime-1.4.0.6",
        site           => 'http://www.pldaniels.com',
        url            => '/ripmime',
        targets        => [ 'make', 'make install' ],
        bintest        => 'ripmime',
        debug          => 0,
        source_sub_dir => 'mail',
        test_ok        => 1,
    ),
    'install_from_source'
);

ok( !$util->install_from_source(
        conf    => { x => 1 },
        debug   => 0,
        package => "mt",
        site    => "mt",
        url     => "dl",
        fatal   => 0,
        test_ok => 0
    ),
    'install_from_source'
);

# is_arrayref
# should succeed
ok( $util->is_arrayref( ['test'] ), 'is_arrayref' );

# should fail
ok( !$util->is_arrayref('boo'), 'is_arrayref - negated' );

# is_hashref
# should succeed
ok( $util->is_hashref( { test => 1 } ), 'is_hashref' );

# should fail
ok( !$util->is_hashref('string'), 'is_hashref - negated' );

# is_process_running
ok( $util->is_process_running("syslogd"), 'is_process_running' );
ok( !$util->is_process_running("nonexistent"), 'is_process_running' );

# is_tainted

# logfile_append

$mod = "Date::Format";
if ( eval "require $mod" ) {
    ok( $util->logfile_append(
            file  => $rwtest,
            prog  => $0,
            lines => ['running tests'],
            debug => 0
        ),
        'logfile_append'
    );

    #print `/bin/cat $rwtest` . "\n";

    ok( $util->logfile_append(
            file  => $rwtest,
            prog  => $0,
            lines => [ 'test1', 'test2' ],
            debug => 0
        ),
        'logfile_append'
    );

    #print `/bin/cat $rwtest` . "\n";

    ok( $util->logfile_append(
            file  => $rwtest,
            prog  => $0,
            lines => [ 'test1', 'test2' ],
            debug => 0
        ),
        'logfile_append'
    );
}

# mailtoaster
#

# mkdir_system
my $mkdir = "$tmp/bar";
ok( $util->mkdir_system( dir => $mkdir, debug => 0 ), 'mkdir_system' );
ok( $util->file_chmod( file_or_dir => $mkdir, mode => '0744', debug => 0 ),
    'file_chmod' );
ok( rmdir($mkdir), 'mkdir_system' );

# path_parse
my $pr = "/usr/bin";
my $bi = "awk";
ok( my ( $up1dir, $userdir ) = $util->path_parse("$pr/$bi"),
    'path_parse' );
ok( $pr eq $up1dir,  'path_parse' );
ok( $bi eq $userdir, 'path_parse' );

# find_config
ok( $util->find_config( file => 'services', debug => 0, fatal => 0 ),
    'find_config valid' );

# same as above but with etcdir defined
ok( $util->find_config(
        file   => 'services',
        etcdir => '/etc',
        debug  => 0,
        fatal  => 0
    ),
    'find_config valid'
);

# this one fails because etcdir is set incorrect
ok( !$util->find_config(
        file   => 'services',
        etcdir => '/ect',
        debug  => 0,
        fatal  => 0
    ),
    'find_config invalid dir'
);

# this one fails because the file does not exist
ok( !$util->find_config(
        file  => 'country-bumpkins.conf',
        debug => 0,
        fatal => 0
    ),
    'find_config non-existent file'
);

# parse_config
#chdir($cwd);
# this works because find_config will check for -dist in the local dir
my $conf;
ok( $conf = $util->parse_config(
        file  => 'toaster-watcher.conf',
        debug => 0,
        fatal => 0
    ),
    'parse_config correct'
);

ok( $conf->{'install_maildrop'} eq "1", 'parse_config value');

ok( $conf->{'install_maildrop'} == 1, 'parse_config int value');

# this fails because the filename is wrong
ok( !$util->parse_config(
        file  => 'toaster-wacher.conf',
        debug => 0,
        fatal => 0
    ),
    'parse_config invalid filename'
);

# this fails because etcdir is set (incorrectly)
ok( !$util->parse_config(
        file   => 'toaster-watcher.conf',
        etcdir => "/ect",
        debug  => 0,
        fatal  => 0
    ),
    'parse_config invalid filename'
);

# parse_line
my ( $foo, $bar ) = $util->parse_line(
    line => ' localhost1 = localhost, disk, da0, disk_da0 ' );
ok( $foo eq "localhost1", 'parse_line lead & trailing whitespace' );
ok( $bar eq "localhost, disk, da0, disk_da0", 'parse_line lead & trailing whitespace' );

( $foo, $bar ) = $util->parse_line(
    line => 'localhost1=localhost, disk, da0, disk_da0' );
ok( $foo eq "localhost1", 'parse_line no whitespace' );
ok( $bar eq "localhost, disk, da0, disk_da0", 'parse_line no whitespace' );

( $foo, $bar )
    = $util->parse_line( line => ' htmldir = /usr/local/rrdutil/html ' );
ok( $foo && $bar, 'parse_line' );

( $foo, $bar )
    = $util->parse_line(
    line => ' hosts   = localhost lab.simerson.net seattle.simerson.net ' );
ok( $foo eq "hosts", 'parse_line' );
ok( $bar eq "localhost lab.simerson.net seattle.simerson.net", 'parse_line' );


# pidfile_check
# will fail because the file is too new
ok( !$util->pidfile_check( pidfile => $rwtest, debug => 0, fatal => 0 ),
    'pidfile_check' );

# will fail because the file is a directory
ok( !$util->pidfile_check( pidfile => $tmp, debug => 0, fatal => 0 ),
    'pidfile_check' );

# proper invocation
ok( $util->pidfile_check(
        pidfile => "${rwtest}.pid",
        debug   => 0,
        fatal   => 0
    ),
    'pidfile_check'
);

# verify the contents of the file contains our PID
my ($pid)
    = $util->file_read( file => "${rwtest}.pid", debug => 0, fatal => 0 );
ok( $PROCESS_ID == $pid, 'pidfile_check' );

# regext_test
ok( $util->regexp_test(
        exp    => 'toast',
        string => 'mailtoaster rocks',
        debug  => 0
    ),
    'regexp_test'
);

# sources_get
# do I really want a test script download stuff? probably not.

# source_warning
ok( $util->source_warning( package => 'foo', debug => 0 ),
    'source_warning' );

# sudo
if ( !$< == 0 && -x $util->find_the_bin( program => 'sudo', debug => 0 ) )
{
    ok( $util->sudo( debug => 0 ), 'sudo' );
}
else {
    ok( !$util->sudo( debug => 0 ), 'sudo' );
}

# syscmd
ok( $util->syscmd(
        command => "$rm $tmp/maildrop-qmail-domain",
        fatal   => 0,
        debug   => 0
    ),
    'syscmd'
) if $network;

# file_delete
ok( $util->file_delete( file => $backup, debug => 0 ), 'file_delete' );
ok( !$util->file_delete( file => $backup, debug => 0, fatal => 0 ),
    'file_delete' );

ok( $util->file_delete( file => $rwtest, debug => 0, ), 'file_delete' );
ok( $util->file_delete( file => "$rwtest.md5", debug => 0, ),
    'file_delete' );

ok( $util->clean_tmp_dir( dir => $tmp, debug => 0 ), 'clean_tmp_dir' );

# validate_params: working example
ok( $util->validate_params(
        {   sub      => 'validate_params',
            min      => 1,
            max      => 1,
            debug    => 0,
            required => [ 'sub', 'min', 'max' ],
            optional => [ 'fatal', 'required', 'optional', 'debug' ],
            params   => [ { sub => 1, min => 1, max => 1, debug => 1 } ],
        }
    ),
    'validate_params - ok'
);

# validate_params: too few params
ok( !$util->validate_params(
        {   sub      => 'validate_params',
            min      => 2,
            max      => 2,
            required => [ 'sub', 'min', 'max', 'params' ],
            optional => [ 'fatal', 'required', 'optional', 'debug' ],
            params   => [ { foo => 1, debug => 0 } ],
            debug    => 0,
            fatal    => 0,
        }
    ),
    'validate_params - too few'
);

# validate_params: too many params
ok( !$util->validate_params(
        {   sub      => 'validate_params',
            min      => 2,
            max      => 2,
            required => [ 'sub', 'min', 'max', 'params' ],
            params   => [ { foo => 1, debug => 0 }, 'bar', 'blargh' ],
            debug    => 0,
            fatal    => 0,
        }
    ),
    'validate_params - too many'
);

# validate_params: invalid parameter
ok( !$util->validate_params(
        {   sub      => 'validate_params',
            min      => 1,
            max      => 1,
            debug    => 0,
            fatal    => 0,
            required => [ 'sub', 'min', 'max' ],
            optional => [ 'fatal', 'required', 'optional', 'debug' ],
            params   =>
                [ { sub => 1, min => 1, max => 1, debug => 1, foo => 0 } ],
        }
    ),
    'validate_params - invalid param'
);

# yes_or_no
ok( $util->yes_or_no( question => "test", timeout => 5, debug => 0 ),
    'yes_or_no' );

