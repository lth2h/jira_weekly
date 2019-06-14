#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

use YAML;
use File::Slurp;

use Data::Dumper;

my ($verbose, $debug, $dry, $help, $quiet, $test);

GetOptions(
    "verbose" => \$verbose,
    "debug" => \$debug,
    "help" => \$help,
);

if ($help) { usage(); exit;}

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)};

print Dumper \%yh;

