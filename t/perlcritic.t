#!perl

use Test::More;

eval "use Test::Perl::Critic";

Test::More::plan(
    skip_all => "Test::Perl::Critic required for testing PBP compliance",
) if $@;

all_critic_ok();
