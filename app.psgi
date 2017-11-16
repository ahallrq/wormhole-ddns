#!/usr/bin/perl

use strict;
use warnings;

use Wormhole::Wormhole;

my $app_or_middleware = \&Wormhole::run_wormhole;