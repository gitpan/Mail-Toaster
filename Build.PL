#!/usr/bin/perl

use strict;
use inc::Module::Install;

name               'Mail-Toaster';
abstract_from      'lib/Mail/Toaster.pm';
author_from        'lib/Mail/Toaster.pm';
version_from       'lib/Mail/Toaster.pm';
license            'bsd';
perl_version       '5.008';

# modules required at run time
requires           'Params::Validate' => '0.8';
requires           'Date::Parse'      => '2.0'; 
requires           'Digest::SHA1'     => 2;           # needed by HMAC_MD5
requires           'Digest::HMAC_MD5' => 1;           # needed by Net::DNS
requires           'Net::IP'          => 1.25;        # needed by Net::DNS
requires           'Net::DNS'         => 0.5;
requires           'Digest::MD5'      => 2;           # needed by files_diff
#requires           'vpopmail'         => 0; 

#auto_bundle       ();   # bundles all required modules
#auto_bundle_deps  ();   # same but includes dependencies

# bundle CPAN dists
#bundle              ('Date::Parse',     '2.0');
#bundle              ('Test::More',        '0');

# same but with depencencies
bundle_deps         ('Params::Validate',  '0.8');
#bundle_deps         ('Digest::SHA1',     '0');
#bundle_deps         ('Net::DNS',         '0.5)';

# modules used only during building
build_requires     'Test::More'         => '0';
build_requires     'Test::Pod'          => '0';
build_requires     'Test::Pod::Coverage'=> '0';
build_requires     'Test::Perl::Critic' => '0';
build_requires     'HTML::Template'     => '0';   # deprecated

#requires_external_bin 'dig';

#install_script    'bin/maillogs';
#install_script    'bin/qqtool.pl';
#install_script    'bin/toaster-watcher.pl';
#install_script    'bin/toaster_setup.pl';
#install_script    'bin/mailadmin';
#install_script    'bin/sysadmin';


# inc and t are automatically not indexed
no_index           ( directory => 'contrib');


include           ('ExtUtils/AutoInstall.pm');
include           ( 'Module::AutoInstall'   );


feature             'Authentication Testing',
                        -default     => '1',
                        'IO::Socket::SSL'  => '1',
                        'Mail::IMAPClient' => '1',
                        'Net::SMTP_auth'   => '1',
                        'Mail::Send'       => '1';


#requires           'Quota'            => 0;
feature             'Provisioning Agent',
                        -default     => '0',
                        'Quota'      => '1';

#requires           'HTML::Template'   => 1;
feature             'Old Web Interface',
                        -default          => '0',
                        'HTML::Template'  => '1';

#requires           'Mail::Ezmlm'      => 0;
feature             'Ezmlm Batch CGI',
                        -default         => '0',
                        'Mail::Ezmlm'    => '1',
                        'Email::Valid'   => '0'; 

#requires           'DBI'              => 1; 
#feature             'MySQL Database Backend',
#                        -default    => '1',
#                        'DBI'       => '1';

auto_include_deps ( );
auto_install      ( -do_once => 1,  );
#WriteMakefile     ( PL_FILES => {}, );
WriteAll();

print "\n", '-'x78, "\n\n";

exit;
