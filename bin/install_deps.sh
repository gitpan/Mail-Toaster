#!/bin/sh

if [ -x /usr/bin/uname ];
then
        if [ `/usr/bin/uname` = "FreeBSD" ]; then
                I_AM_FREEBSD=1
                echo "detected FreeBSD, will install from ports"
        fi
fi

if [ ! $I_AM_FREEBSD ]; 
then
        /usr/bin/perl -MCPAN -e 'use CPAN; CPAN::install Params::Validate;'
        exit
fi

INSTALLED=`/usr/sbin/pkg_info | /usr/bin/grep Params-Val`
if [ -z "$INSTALLED" ]; then
        echo "installing p5-Params-Validate"
        cd /usr/ports/devel/p5-Params-Validate
        make install distclean
else
    echo "Params::Validate is installed."
fi

INSTALLED=`/usr/sbin/pkg_info | /usr/bin/grep Mail-Tools`
if [ -z "$INSTALLED" ]; then
        echo "installing p5-Mail-Tools"
        cd /usr/ports/mail/p5-Mail-Tools
        make install distclean
else
    echo "Mail::Tools is installed."
fi
