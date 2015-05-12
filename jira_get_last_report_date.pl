#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use JIRA::Client::Automated;
use Date::Calc qw(Decode_Date_US Delta_Days);

use Data::Dumper;
use POSIX;

use Term::ANSIColor;

use YAML;
use File::Slurp;

my ($verbose, $debug, $dry, $help, $quiet);
my ($archive, $create);
my ($parent, $project, $summary, $description);
my $test;
my ($dparent, $dproject, $dsummary, $ddescription);
my $yorn;
my @k; # id keys
my @s; # summaries
my %ks; # keys => summaries
my %sk; # summaries => keys
my $summary_only;

GetOptions(
	   "verbose" => \$verbose,
	   "debug=i" => \$debug,
	   "archive" => \$archive,
	   "create" => \$create,
	   "help" => \$help,
	   "parent=s" => \$parent,
	   "project=s" => \$project,
	   "summary=s" => \$summary,
	   "description=s" => \$description,
	   "test" => \$test,
	   "dry-run" => \$dry,
	   "quiet" => \$quiet,
	   "summary-only" => \$summary_only,
);

if ($debug) { $verbose = $debug; } else { $debug = 0; }

if ($help) { usage(); exit;}

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)};

my $username = $yh{"username"};
my $password = $yh{"password"};
my $jira_domain = $yh{"jira_domain"};

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $month = $abbr[$mon];
my $day = $mday;
$year += 1900;

if ($test) {

  $dparent = "TP-8";
  $dproject = "TP";
  $dsummary = "Test $hour:$min:$sec";
  $ddescription = "Testing Creation";

} else {

  $dparent = $yh{"dparent"};
  $dproject = $yh{"dproject"};
  $dsummary = "Weekly Report - $month $day, $year";
  $ddescription = "Weekly Report";

}

# for ANSIColor
my $bugcol = "cyan on_black";
my $vercol = "green on_black";
my $drycol = "white on_blue";
my $errcol = "bold white on_red";
my $warncol = "black on_yellow";
my $okcol = "green";
my $normcol = "white";

my $jca_url = "https://$jira_domain/";

my $jira = JIRA::Client::Automated->new($jca_url, $username, $password);

$dparent = $yh{"dparent"};

my $jql = "key=\"$dparent\"";

my @results = $jira->all_search_results($jql, 1); # if there are more than 1 something is horribly wrong.

# we need to go through the subtasks, and pick the one with the
# highest number or get the most recent date in the
# description/summary or we could look each one up and find the last
# time it was updated or had the status set to done or whatever.  I'm
# going just assume the highest number or more recent date will be ok

my $st = $results[0]->{"fields"}{"subtasks"};

print Dumper \$st if $debug > 2;

# we're interested either in $element->{'key'} or $element->{'fields'}{'summary'}

foreach my $task (@{$st}) {

  pc ("KEY: " . $task->{'key'}, $bugcol)  if $debug;
  pc ("\tSUMMARY: " . $task->{'fields'}{'summary'}, $bugcol) if $debug;

  my $tk = $task->{'key'};
  my $ts = $task->{'fields'}{'summary'};

  push (@k, $tk);
  push (@s, $ts);
  $ks{$tk} = $ts;
  $sk{$ts} = $tk;

}

print Dumper \@k if $debug > 1;
print Dumper \@s if $debug > 1;
print Dumper \%ks if $debug > 1;
print Dumper \%sk if $debug > 1;

my $highest = 0;
my $highest_key = 0;

if (!$summary_only) {

  foreach my $key (@k) {

    pc("Processing $key", $vercol) if $verbose;

    my ($prefix, $number) = $key =~ /([A-Za-z]*)-([0-9]*)/;

    # my @captured = $key =~ /([A-Za-z]*)-([0-9]*)/;

    # print Dumper \@captured;

    pc("PREFIX: $prefix, NUMBER: $number", $bugcol) if $debug;

    if ($number > $highest) {

      $highest = $number;
      $highest_key = $key;

    }

  }

  pc("Highest key: $highest_key", $vercol) if $verbose;

}

my ($max_yr, $max_mo, $max_day) = ('1')x3;
my $max_summary;

foreach my $summary (@s) {

  pc("Processing $summary", $vercol) if $verbose;

  my ($date, $month, $day, $year) = $summary =~ /Weekly Report - (([A-Za-z]*) ([0-9]{0,2}), ([0-9]{4}))/;

  if (!$date) { next; }

  pc("\t$date: YEAR: $year, MONTH: $month, DAY: $day", $bugcol) if $debug;

  my ($yr, $mo, $da)  = Decode_Date_US($date);

  pc("\tDATE::CALC: $yr, $mo, $da", $bugcol) if $debug;

  my $Dd = Delta_Days($max_yr, $max_mo, $max_day, $yr, $mo, $da);
  # $Dd = Delta_Days($year1,$month1,$day1, $year2,$month2,$day2);
  # This function returns the difference in days between the two given dates.
  # The result is positive if the two dates are in chronological order, i.e., if date #1 comes chronologically BEFORE date #2, and negative if the order of the two dates is reversed.
  # The result is zero if the two dates are identical.

  if ($Dd > 0) {

    ($max_yr, $max_mo, $max_day) = ($yr, $mo, $da);
    $max_summary = $summary;

  }

  # for kicks lets break it
  if ($test) {
    pc("TESTING SETTING MAX_SUMMARY etc TO TEST VALUES", $warncol);
    $max_summary = 'Processing Weekly Report - Feb 12, 2015';
    ($max_yr, $max_mo, $max_day) = ('2015', '2', '12');
  }


}

pc("MAX DATE: $max_yr-$max_mo-$max_day", $bugcol) if $debug;
pc("Max Summary: $max_summary", $vercol) if $verbose;

# now if $max_summary and $highest_key agree....

if (!$summary_only) {

  if ( ($ks{$highest_key} eq $max_summary) && ($sk{$max_summary} eq $highest_key)) {

    pc("HIGHEST KEY: $highest_key MATCHES MAX SUMMARY: $max_summary", $vercol) if $verbose;

    ## Now print out the results in YAML

    print_yaml();

  } else {

    pc("HIGHEST KEY: $highest_key is " . $ks{$highest_key} . " BUT MAX SUMMARY, $max_summary is " . $sk{$max_summary}, $errcol);
    exit 255;

  }

} else {

  print_yaml();

}


sub print_yaml {

  print <<EOF;
---
max_yr: $max_yr
max_mo: $max_mo
max_day: $max_day
max_summary: $max_summary
max_key: $highest_key

EOF

}


sub pc {

  my ($txt, $color) = @_;

  print colored($txt, $color) . "\n";

}

sub usage {

  print "USAGE: $0\n";

}
