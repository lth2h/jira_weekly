#!/usr/bin/perl

#######

# use jira_archive.pl to archive and create the Weekly Report task.

## TO DO: Make it so you can override what is in the yaml

use strict;
use warnings;

use LWP::UserAgent;
use Data::Dumper;

use Date::Calc qw(Delta_Days Add_Delta_Days);
use Sort::Naturally;
use JIRA::REST::Class;

use YAML;
use File::Slurp qw(read_file);

use Getopt::Long;
use POSIX qw(strftime);

my ($verbose, $debug, $dry, $quiet);
my $max_days;
my $mdt = 1;
my $no_done;
my $yorn;
my $fdate;
my $yes;

my $last_item = 0;

GetOptions(
	   "verbose" => \$verbose,
	   "quiet" => \$quiet,
	   "debug" => \$debug,
	   "days=i" => \$max_days,
	   "no-export-done" => \$no_done,
	   "dry-run" => \$dry,
	   "fdate=i" => \$fdate,
	   "y" => \$yes,
) or usage();

# my $max_days = $ARGV[0] || 14;
if (!defined($max_days)) {
  # max days wasn't given on the command line so don't run the max days test
  $mdt = 0;
  # however max days does need to be 0 and not undef so set that now
  $max_days = 0;

}

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)}; # the yaml hash

print Dumper \%yh if $debug;

my $username = $yh{"api_user"};
my $password = $yh{"api_token"};
my %staff = %{$yh{"staff"}};
my @verbs = @{$yh{"verbs"}};
my $filter = $yh{"filter"};
my $jira_domain = $yh{"jira_domain"};

# because of https://ecosystem.atlassian.net/browse/STRM-2140 and other bugs, a date range needs to be applied. Date format is JavaScript's miliseconds since the Epoch.
# THIS IS DIFFERENT FROM the --days=x option AND THE SHORTER OF THE TWO WILL CONTROL

my $jira2 = JIRA::REST::Class->new({
    url             => "https://$jira_domain",
    username        => $username,
    password        => $password,
});

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $now_string = strftime("%Y-%m-%d_%H%M%S", ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst));

$year+=1900;
$mon+=1;
my $lzmon = sprintf('%02d', $mon);
my $lzmday = sprintf('%02d', $mday);

## check last report

my $last_day;
my $last_mo;
my $last_yr;
my $last_key;
my $last_summary;

if ( -e "./jira_get_last_report_date.pl") {

  # get last report date from the summary only instead of both summary and highest key
  # maybe this should be an option
  my $last_report_yaml = `./jira_get_last_report_date.pl --summary-only`;

  if (!ck_exit_status($?)) {

    print "get last report date failed\n";
    exit;

  }

  ### TO DO:
  ### check exit status or fix jira_get_last_report_date.pl

  my %lr_yh = %{Load($last_report_yaml)};

  # print Dumper \%lr_yh;

  $last_day = sprintf("%02d", $lr_yh{"max_day"});
  $last_mo  = sprintf("%02d", $lr_yh{"max_mo"});
  $last_yr  = $lr_yh{"max_yr"};
  $last_key = $lr_yh{"max_key"};
  $last_summary = $lr_yh{"max_summary"};

  print "Last report on $last_mo/$last_day/$last_yr: $last_key - $last_summary\n" unless $quiet;

  # check if --days=x ($max_days) or $fdate comes after date of last report (and therefore you'll be missing stuff)

  my ($ymd, $mmd, $dmd) = Add_Delta_Days($year, $mon, $mday, -1*$max_days);

  print "YEAR:$year,Month:$mon,Day:$mday -$max_days days = $ymd, $mmd, $dmd\n" if $debug;

  my ($yfd, $mfd, $dfd) = Add_Delta_Days($year, $mon, $mday, -1*$fdate);

  print "YEAR:$year,Month:$mon,Day:$mday -$fdate days = $yfd, $mfd, $dfd\n" if $debug;

  # calcudate Dd for both *md and *fd, if either are after the last weekly report, give warning

  my $Ddmd = Delta_Days($last_yr, $last_mo, $last_day, $ymd, $mmd, $dmd);

  print "LAST REPROT: $last_mo/$last_day/$last_yr, MAX_DAYS: $mmd/$dmd/$ymd, DELTA: $Ddmd\n" if $debug;

  my $Ddfd = Delta_Days($last_yr, $last_mo, $last_day, $yfd, $mfd, $dfd);

  print "LAST REPROT: $last_mo/$last_day/$last_yr, FDATE: $mfd/$dfd/$yfd, DELTA: $Ddfd\n" if $debug;

  # if $Dd is positive Date #1 comes BEFORE Date #2, and negative if Date #1 comes AFTER Date #2
  # so as long as $Dd is negative, all new items since the last report will be found
  my $dderr = 0;
  # don't warn if max days wasn't set on the command line
  if (($Ddmd > 0) && ($mdt)) {
    print "Warning: Max Days set to $max_days, does not go back far enough for previous report on $last_mo/$last_day/$last_yr.\n";
    $dderr = 1;
  }
  if ($Ddfd > 0) {
    print "Warning: Filter Days set to $fdate, does not go back far enough for previous report on $last_mo/$last_day/$last_yr.\n";
    $dderr = 1;
  }

  if ($dderr) {
    if ($yes) {
      print "y option given, proceeding\n";
    } else {
      print "Do you want to proceed (y/n)?";
      $yorn = <>;
      chomp($yorn);
      if ($yorn ne "y") {
	print "You didn't type \"y\" ... exiting\n";
	exit;
      }
    }
  }

} else {

  print "jira_get_last_report_date.pl doesn't exist not checking date of last report\n";

}

my $updatedDateStr = "$last_yr-$last_mo-$last_day";

if ($max_days > 0) {
  # this should probably an "AND"
  $updatedDateStr = "-" . $max_days . "d";

}

my $jql = "(project in (projectsLeadByUser(ltharris), projectsLeadByUser(jjtoth), projectsLeadByUser(mtmartin)) OR assignee in (ltharris, jjtoth, mtmartin)) and updatedDate > '$updatedDateStr' AND status != Archived ORDER BY updatedDate ASC";

print "JQL:$jql\n" if $debug;

my @entries;
# my @entries = $jira2->issues({ jql => $jql });
my $search = $jira2->iterator({ jql => $jql }, 1);
if ($search->issue_count) {
  while (my $issue = $search->next) {
    push (@entries, $issue);
  }
}


my %items;
my %done;

my $range = " to $mon/$mday/$year\n";
my $last_date = "$mon/$mday/$year";

foreach my $entry (@entries) {

  print "\n######\n" if $debug;
  print Dumper \$entry  if $debug;
  print "\n######\n" if $debug;

  my $key = $entry->{"data"}{"key"};
  my $title = $entry->{"data"}{"fields"}{"summary"};
  my $status = $entry->{"data"}{"fields"}{"status"}{"name"};
  # displayname instead of key or name so we don't have to change staff in the yaml
  my $assignee = $entry->{"data"}{"fields"}{"assignee"}{"displayName"} || $entry->{"data"}{"fields"}{"assignee"}{"key"}; 
  my $reporter = $entry->{"data"}{"fields"}{"reporter"}{"displayName"} || $entry->{"data"}{"fields"}{"reporter"}{"key"};
  my $initials;

  if (!$assignee) { $assignee = $reporter;}

  if ($staff{$assignee}) {
    $initials = $staff{$assignee};
  } elsif ($assignee) {
    $initials = $assignee;
  } elsif ($staff{$reporter}) {
    $initials = $staff{$reporter};
  } elsif ($reporter) {
    $initials = $reporter;
  } else {
    $initials = "PROBLEM WITH $key";
  }

  if ($debug) {
    print "####\n";
    print Dumper \$entry;
    print "KEY: '$key'\n";
    print "TITLE: '$title'\n";
    print "STATUS: '$status'\n";
    print "ASSIGNEE: '$assignee'\n";
    print "REPORTER: '$reporter'\n";
    print Dumper \%staff;
    print "STAFF[ASSIGNEE]: '" . $staff{$assignee} . "'\n";
    print "INITIALS: '$initials'\n";
    print "####\n";

  }

  if ($status =~ /[Dd]one/) {

    $done{$key} = "$key - $title [$initials]";

  } else {

    $items{$key} = "$key - $title [$initials]";

  }

}

  if ($debug) {
    print "### DONE ###\n";
    print Dumper \%done;
    print "### ITEMS ###\n";
    print Dumper \%items;
    print "###\n";
#    exit;
  }

if (!($range =~ m/Includes/)) {
  $range = "Includes items from $last_date" . $range;
}

### THE ACTUAL REPORT ####

print "\n\n$range";

print_report("JIRA DONE TASKS", \%done);
print_report("JIRA ACTIVE TASKS", \%items);

if ((!$no_done) && (!$dry)) {

  export_done();

} elsif ((!$no_done) && ($dry)) {

  print "DRYRUN: would have exported done\n";

}

sub export_done {

  open (DONE, "+>/tmp/done.txt");

  foreach my $t (keys %done) {
    print DONE $t . "\n";

  }

  close(DONE);

  print "Written to /tmp/done.txt\n";

}

sub print_report {

  my $heading = shift;
  my $tasks = shift;

  print $heading . "\n";

  foreach my $title (nsort keys $tasks) {

    print $tasks->{$title} . "\n";

  }

}

sub ck_exit_status {

  my $excode = shift;
  my $rv = 1;

  print "Checking exit code $excode\n" if $debug;

  if ($excode != 0) {
    $rv = 0;
  }

  return $rv;

}

sub usage {

  print "Usage: $0 [--days=x] [--no-export-done] \n";
  exit;

}
