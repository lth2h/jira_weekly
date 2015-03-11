#!/usr/bin/perl

# TODO: --no-sub
#       --group-by-sub=done --group-by-sub=active

# use jira_archive.pl to archive and create the Weekly Report task.

use strict;
use warnings;

binmode STDOUT, ":utf8";

use LWP::UserAgent;
use Data::Dumper;

# use URI;
use XML::Feed;
use HTML::Strip;
use Lingua::EN::Sentence qw(get_sentences);
use Date::Calc qw(Delta_Days);
use JIRA::Client::Automated;
use Sort::Naturally;

use Getopt::Long;

my ($verbose, $debug, $dry);
my $max_days = 0;
my $ignore_level = 0;
my ($no_items, $short_items, $no_done);
my ($rss_file, $write_rss);

GetOptions(
	   "verbose" => \$verbose,
	   "debug" => \$debug,
	   "days=i" => \$max_days,
	   "ignore_weekly=i" => \$ignore_level,
	   "no-items" => \$no_items,
	   "short-items" => \$short_items,
	   "no-export-done" => \$no_done,
	   "use-rss-file=s" => \$rss_file,
	   "dry-run" => \$dry,
	   "write-rss" => \$write_rss,
);

# my $max_days = $ARGV[0] || 14;

my $hs = HTML::Strip->new();

#TODO: make conf file simpler
require "jira_weekly.conf";

my $username = username();
my $password = password();
my %staff = getstaff(); # should return a hash like {"Employee Name" => "Initials", }
my $filter = getfilter(); # the string for the streams filter in the jira url
my $jira_domain = getjiradomain();

# the real one
my $url = "https://$username:$password\@$jira_domain/activity?maxResults=1000&streams=$filter&os_authType=basic&title=undefined";

if ($write_rss) {

  my $ua = LWP::UserAgent->new;
  my $response = $ua->get($url);

  my $dc = $response->decoded_content;  # this needs to go into a file for XML::RSS::Parser

  open (FILE, "+>/tmp/jira_dc.rss") or die("kaboom: /tmp/jira_dc.rss $!");

  print FILE $dc;

  close (FILE);

}

# print Dumper \$dc;

my $feed;
if ($rss_file) {
  $feed = XML::Feed->parse($rss_file);
} else {
  $feed = XML::Feed->parse(URI->new($url));  # This cannot be given a $url directly
}

# print Dumper \$feed;

my @entries = $feed->entries;

my $jca_url = "https://$jira_domain/";
my $jira = JIRA::Client::Automated->new($jca_url, $username, $password);

my %items;
my %actions;
my $ignored;
my %done;
my %resolutions;
my %doneby;
my %subtasks;
my %issubtask;
my %titles;
my %keys;
my %parents;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year+=1900;
$mon+=1;
# print "\nTODAY: M/D/Y: $mon/$mday/$year\n";
my $range = " to $mon/$mday/$year\n";
my $last_date = "$mon/$mday/$year";

foreach my $entry (@entries) {

  # print "\n######\n";
  # print Dumper \$entry;

  my $content = $entry->content;
  my $title = $entry->title;
  my $id = $entry->id;
  my $issued = $entry->issued;
  my @links = $entry->link;  # doesn't work as advertised
  # my $summary = $entry->summary;
  # print Dumper \$content;
  # print Dumper \$title;
  # print Dumper \$summary;
  # print Dumper \$issued;
  # print Dumper \@links;

  my $item_year = $issued->year();
  my $item_month = $issued->month();
  my $item_month_n = $issued->month_name();
  my $item_month_a = $issued->month_abbr();
  my $item_day = sprintf("%02d", $issued->day());

  # print "\nM/D/Y: $item_month_a/$item_day/$item_year\n";

  my $Dd = Delta_Days($item_year, $item_month, $item_day,$year, $mon, $mday);

  # print "\tDelta Days: $Dd\n";

  if ($max_days > 0) {
    if ($Dd > $max_days) {
      print "DD gt MXD == $Dd gt $max_days\n";
      $range = "Includes items from $last_date" . $range;
      last;
    }
  }

  $last_date = "$item_month/$item_day/$item_year";

  my $body = $content->body;
  my $action;
  my $resolution;
  my $by;
  my $key;
  #   print Dumper \$body;

  # print "TITLE: \"$title\"\n";
  # print "CONTENT: $content\n";
  # print "BODY: \"$body\"\n";

  $title = $hs->parse($title);
  # $content = $hs->parse($content);

  if ($title =~ m/Weekly Report/) {

    $ignored++;
    print "is weekly report...Ignored:$ignored,Ignorelevel: $ignore_level\n";
    if ($ignored >= $ignore_level) {
      $range = "Includes items from $last_date" . $range;
      last;
    }

  }

  next if ($title =~ m/linked \d* issues/);

  if ($body) {
    $body = $hs->parse($body);
  } else {
    $body = "";
  }

  $body =~ s/^\s+|\s+$//g;
  $title =~ s/^\s+|\s+$//g;
  $title =~ s/\n//g;

  # print "STRIPPED TITLE: $title\n";
  # print "STRIPPED CONTENT: $content\n";
  # print "STRIPPED BODY: $body\n";

  # Title seems to be in the form of <NAME><ACTION>     <ACTIVTY TITLE>

  ($title, $by, $action, $resolution, $key) = munge_title($title);

  if (!defined($done{$title})) {
    $done{$title} = 0;
  }

  if ($resolution eq "Done") {

    $done{$title} = 1;

  } elsif ($done{$title} < 1) {

    $done{$title} = 0;

  }

  # print "TITLE: '$title'\n";
  # print "\t$body\n" unless $body eq "";
  # print "\t$resolution\n" unless $resolution eq "";
  # print "\tBY: $by\n" unless $by eq "";
  # print "\tKEY: $key\n";
  # print "BODY: '$body'\n";

  if ($short_items) {
    my $sentences=get_sentences($body);
    $body = @$sentences[0];
  }

  # print "BODY AFTER GET SEN: '$body'\n";

  # we don't want forwarded emails...
  if (($body) && ($body =~ m/---------- Forwarded message ----------/))  {
    $body = "";
  }

  ## now to figure out if it is a subtask or has subtasks.
  if (!$titles{$key}) {
    # we haven't seen this title before, so it needs to be checked.

    $titles{$key} = $title;
    $keys{$title} = $key;
    # print "key => titles: $key => " . $titles{$key} . "\n";
    my $parent = getparent($key);

    # problem  if we haven't seen the parent yet
    if (!$titles{$parent}) {
      $titles{$parent} = gettitle($parent);
    }

    # print "title:$title, key:$key, parent:$parent\n";
    # print "title of parent: " . $titles{$parent} . "\n";

    if (($parent) && !($parent =~ m/No/))  {
      $issubtask{$title} = 1;
      $parents{$title} = $parent;
      push(@{$subtasks{$titles{$parent}}}, $title);
      # push(@{$subtasks{$titles{$key}}}, $title);
    }

  }

  $body =~ s/\n//g;
  $body =~ s/^\s+|\s+$//g;
  # print "BODY:'$body'\n";

  if ($body) {
    $items{$title} .= "\n\t$body";
  } else {
    $items{$title} .= "";
  }

  $actions{$title} .= $action;
  $resolutions{$title} .= $resolution;
  # push(@{$doneby{$title}}, $by);
  $doneby{$title}{$by}++;

  ## TODO: Move Done Tasks to Archived
}

# print Dumper \$doneby{'AUD-7 - Create IT Strategy Roadmaps'};
# exit
# print Dumper \%doneby;
# exit;
# print Dumper \%done;

if (!($range =~ m/Includes/)) {
  $range = "Includes items from $last_date" . $range;
}


### THE ACTUAL REPORT ####

print "\n\n$range";

# print_report("Heading", Done_Val, %items_or_done_hash, group_by_parent_task)
print_report("JIRA DONE TASKS", 1, \%done, 0);
print_report("JIRA ACTIVE TASKS", 0, \%items, 0);

if (!$no_done) {

  export_done();

}

sub export_done {

  open (DONE, "+>/tmp/done.txt");

  foreach my $t (keys %keys) {
    # print "Checking: $t\n";
    # print "TITLES(k): " . $titles{$k} . "\n";
    # print "DONE(TITLES(k)): " . $done{$titles{$k}} . "\n";
    #   print "KEYS(t): " . $keys{$t} . "\n";
    # print "DONE(t): " . $done{$t} . "\n";
    if ($done{$t} == 1) {
      print DONE $keys{$t} . "\n";
    }

  }

#   print Dumper \%done;
#   print Dumper \%keys;
#   print Dumper \%titles;

  close(DONE);

  print "Written to /tmp/done.txt\n";

}

sub print_report {

  my $heading = shift;
  my $done_val = shift;
  my $tasks = shift;
  my $group = shift;  # TODO: actually use this

  # print "HEADING: $heading\n";
  # print "DONEVAL: $done_val\n";
  # print Dumper \$tasks;

  # print "SUBTASKS: \n";
  # print Dumper \%subtasks;

  # print "\n##########\n";
  print $heading . "\n";
  # print "Grouping: $group\n";
  foreach my $title (nsort keys $tasks) {

    next unless $done{$title} == $done_val;

    # giving up on grouping by parent for now.
    if ($group == 1) {
      print "grouping by parent not supported yet";
    } else {
      # don't group by parent tasks

      print $title;
      print_doneby($title);
      if ($issubtask{$title}) {
	print " (subtask of " . $parents{$title} . ")";
      }
      print_items($title);

    }

  }

}

sub print_items {

  my $title = shift;

  if (!$no_items) {
    print "\t" . $items{$title} . "\n" unless !$items{$title};
  } else {
    print "\n";
  }

}

sub print_doneby {

  my $title = shift;

  print " [";
  print join(",", sort keys %{$doneby{$title}});
  print "]";

}


# print "\n########\n";
# print Dumper \%actions;

#print Dumper \@foo;

sub munge_title {

  my $title = shift;

  # print "##Munging Title: '$title'##\n";

  chomp($title);

  # who

  my $regex = "^(";
  $regex .= join "|", keys(%staff);
  $regex .= ")";

  # print "REGEX: $regex\n";

  $title =~ s/$regex//;

  # print "NEW TITLE(1): $title\n";
  my $staff1 = $1;
  # print "DOLLAR1: $staff, STAFF: " . $staff{$staff} . "\n" unless $staff eq "";

  # action

  $title =~ s/(.*?\s{2,})//;
  my $action = $1;

  $title =~ s/with a resolution of '(.*)'//;
  my $resolution = $1;

  my $timespent;
  if ($action =~ m/Time Spent/) {

    $title =~ s/(by '[0-9]* day')//;
    $timespent = $1;

  }

  # print "ACTION: $action\n";
  # print "RESOLUTION: $resolution\n";
  # print "TIME SPENT: $timespent\n" unless !$timespent;

  # remove trailing whitespace

  $title =~ s/\s*$//;

  my ($key) = $title =~ m/([A-Z]+-[0-9]+)/;

  # print "##Returning Munged Title##\n";
  # print "\tTitle: $title\n";
  # print "\tSTAFF1: $staff1\n";

  return ($title,$staff{$staff1},$action,$resolution,$key);

}

sub gettitle {

  my $t;
  my $k = shift;
  my $jql = "issue = $k";

  my @results = eval{ $jira->all_search_results($jql, 1) } ;

  if (@results) {

    $t = $results[0] ->{"fields"}->{"summary"};
    $t = $k . " - " . $t;

  } else {

    # print "NO RESULT FOR: $jql\n";

  }

  return $t;

}


sub getparent {

  my $parent;
  my $k = shift;

  # print "Getting Parent for $k\n";

  my $jql = "issue = $k";

  my @results = eval{ $jira->all_search_results($jql, 1) } ;

  if (@results) {

    $parent = $results[0]->{"fields"}->{"parent"}->{"key"} || "No Parent";

  } else {

    $parent = "No Result";

  }

  # print "\tParent: $parent\n";

  return $parent;

}
