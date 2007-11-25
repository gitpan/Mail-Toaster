#!/usr/bin/perl
use strict;
use warnings;
use Cwd;
use English qw( -no_match_vars );

use Test::More 'no_plan';

use lib "inc";
use lib "lib";

BEGIN { 
    use_ok( 'Mail::Toaster::Apache' );
    use_ok( 'Mail::Toaster::Utility' );
}
require_ok( 'Mail::Toaster::Apache' );
require_ok( 'Mail::Toaster::Utility' );

# basic OO mechanism
	my $apache = Mail::Toaster::Apache->new;  # create an object
	ok ( defined $apache, 'get Mail::Toaster::Apache object' ); # check it
	ok ( $apache->isa('Mail::Toaster::Apache'), 'check object class' ); # the right class?

	my $utility = Mail::Toaster::Utility->new;
	my $conf = $utility->parse_config(
            file  => "toaster-watcher.conf",
            debug => 0,
        );


# install_apache1

# install_apache2

# startup


# freebsd_extras

    my $apachectl = $utility->find_the_bin(bin=>"apachectl", fatal=>0,debug=>0);
    if ( $apachectl && -x $apachectl ) {
        ok ( -x $apachectl, 'apachectl exists' );

# apache2_fixups
    # icky...this sub needs to be cleaned up
        #$apache->apache2_fixups($conf, "apache22");


# conf_get_dir
        my $httpd_conf = $apache->conf_get_dir(conf=>$conf);
        print "httpd.conf: $httpd_conf \n";
        ok ( -f $httpd_conf, 'find httpd.conf' );

# apache_conf_patch
        ok( $apache->apache_conf_patch(
            conf    => $conf, 
            test_ok => 1, 
            debug   => 0,
        ), 'apache_conf_patch');


# install_ssl_certs
        ok( $apache->install_ssl_certs(conf=>$conf, test_ok=>1, debug=>0), 'install_ssl_certs');

    };

# restart

# vhost_create

# vhost_enable

# vhost_disable

# vhost_delete

# vhost_exists

# vhost_show

# vhosts_get_file

# vhosts_get_match

# RemoveOldApacheSources

# openssl_config_note
    # just prints a notice, no need to test
    ok( $apache->openssl_config_note(), 'openssl_config_note');

# install_dsa_cert

# install_rsa_cert
    ok( $apache->install_rsa_cert( 
        crtdir => "/etc/httpd", 
        keydir => "/etc/httpd", 
        test_ok=> 1,
        debug  => 0,
    ), 'install_rsa_cert');
 
