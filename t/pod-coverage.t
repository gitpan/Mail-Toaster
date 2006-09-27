#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;

# we shall get around to this later
plan skip_all => "Test::Pod::Coverage not ready for release.";

all_pod_coverage_ok();
