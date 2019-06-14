#!/usr/bin/perl

use strict;
use warnings;

use JIRA::Client::Automated;
use File::Slurp; 
use YAML;

use Data::Dumper;

if (!$ARGV[0]) { usage(); exit; }

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)};

# print Dumper \%yh if $debug;

my $username = $yh{"username"};
my $password = $yh{"password"};
my $jira_domain = $yh{"jira_domain"};

my $jca_url = "https://$jira_domain/";

my $jira = JIRA::Client::Automated->new($jca_url, $username, $password);

my $jql = "key = " . $ARGV[0];

print "JQL: $jql\n";

# $results is a hash with keys: start total max issues
my $results = $jira->search_issues($jql, 0, 1000);

# print Dumper \$results;
# exit;

my @issues = @{$results->{issues}};

foreach (@issues) {
    my $fields = $_->{"fields"};
#    print Dumper \$fields;

    if ($fields->{"issuelinks"}) {

      my @issuelinks = @{$fields->{"issuelinks"}};
      # print Dumper \@{$fields->{"issuelinks"}};
      print Dumper \@issuelinks;

  }
}

sub usage {

  print "$0 <JIRA Epic Key>\n";
  print "\tPrints the issuelinks hash from results->issues->fields->issuelinks\n";
  exit;

}
