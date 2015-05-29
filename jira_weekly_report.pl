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
use Date::Calc qw(Delta_Days Add_Delta_Days);
use JIRA::Client::Automated;
use Sort::Naturally;

use YAML;
use File::Slurp; # is this actually needed???
# use Test::YAML::Valid;
# use Kwalify qw(validate);

use Getopt::Long;

my ($verbose, $debug, $dry, $quiet);
my $max_days;
my $mdt = 1;
my $ignore_level = 0;
my ($no_items, $short_items, $no_done);
my ($rss_file, $write_rss, $write_rss_only);
my $yorn;

GetOptions(
	   "verbose" => \$verbose,
	   "quiet" => \$quiet,
	   "debug" => \$debug,
	   "days=i" => \$max_days,
	   "ignore_weekly=i" => \$ignore_level,
	   "no-items" => \$no_items,
	   "short-items" => \$short_items,
	   "no-export-done" => \$no_done,
	   "use-rss-file=s" => \$rss_file,
	   "dry-run" => \$dry,
	   "write-rss" => \$write_rss,
	   "only-write-rss" => \$write_rss_only,
) or usage();

if ($write_rss_only) {
  $write_rss = 1;
}

# my $max_days = $ARGV[0] || 14;
if (!defined($max_days)) {
  # max days wasn't given on the command line so don't run the max days test
  $mdt = 0;
  # however max days does need to be 0 and not undef so set that now
  $max_days = 0;

}

my $hs = HTML::Strip->new();

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)}; # the yaml hash

my $username = $yh{"username"};
my $password = $yh{"password"};
my %staff = %{$yh{"staff"}};
my $filter = $yh{"filter"};
my $jira_domain = $yh{"jira_domain"};

# because of https://ecosystem.atlassian.net/browse/STRM-2140 and other bugs, a date range needs to be applied. Date format is JavaScript's miliseconds since the Epoch.
# THIS IS DIFFERENT FROM the --days=x option AND THE SHORTER OF THE TWO WILL CONTROL
my $fdate = $yh{"fdate"};
my $first_fdate = 1000*(time() - $fdate*24*60*60); #we'll try two months
my $last_fdate = 1000*(time());
my $date_filter="&streams=update-date+BETWEEN+$first_fdate+$last_fdate";

my $url = "https://$username:$password\@$jira_domain/activity?maxResults=1000&streams=$filter$date_filter&os_authType=basic&title=Activity%20Stream";
print $url . "\n" if $debug;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year+=1900;
$mon+=1;

if ($write_rss) {

  my $ua = LWP::UserAgent->new;
  my $response = $ua->get($url);

  my $dc = $response->decoded_content;  # this needs to go into a file for XML::RSS::Parser

  $rss_file = "/tmp/jira_dc.rss" unless $rss_file;

  open (FILE, "+>$rss_file") or die("kaboom: $rss_file $!");

  print FILE $dc;

  close (FILE);

  print "RSS file written to $rss_file\n" unless $quiet;

  if ($write_rss_only) { exit; }

}

# print Dumper \$dc;


## check last report
if ( -e "./jira_get_last_report_date.pl") {

  # get last report date from the summary only instead of both summary and highest key
  # maybe this should be an option
  # my $last_report_yaml = `./jira_get_last_report_date.pl`;
  my $last_report_yaml = `./jira_get_last_report_date.pl --summary-only`;

  if (!ck_exit_status($?)) {

    print "get last report date failed\n";
    exit;

  }

  ### TO DO:
  ### check exit status or fix jira_get_last_report_date.pl

  my %lr_yh = %{Load($last_report_yaml)};

  # print Dumper \%lr_yh;

  my $last_day = $lr_yh{"max_day"};
  my $last_mo  = $lr_yh{"max_mo"};
  my $last_yr  = $lr_yh{"max_yr"};
  my $last_key = $lr_yh{"max_key"};
  my $last_summary = $lr_yh{"max_summary"};

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
    print "Do you want to proceed (y/n)?";
    $yorn = <>;
    chomp($yorn);
    if ($yorn ne "y") {
      print "You didn't type \"y\" ... exiting\n";
      exit;
    }
  }

} else {

  print "jira_get_last_report_date.pl doesn't exist not checking date of last report\n";

}

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

  # print "STRIPPED TITLE: $title\n" if $debug;
  # print "STRIPPED CONTENT: $content\n";
  # print "STRIPPED BODY: $body\n";

  # Title seems to be in the form of <NAME><ACTION>     <ACTIVTY TITLE>

  ($title, $by, $action, $resolution, $key) = munge_title($title);

  if (!$key) {

    print "No key found for $title, skipping\n";
    next;

  }

  if (!defined($done{$title})) {
    $done{$title} = 0;
  }

  if ($resolution eq "Done") {

    $done{$title} = 1;

  } elsif ($done{$title} < 1) {

    $done{$title} = 0;

  }

  # if ($debug) {
  #   print "TITLE: '$title'\n";
  #   # print "\t$body\n" unless $body eq "";
  #   print "\tRESOLUTION: $resolution\n" unless $resolution eq "";
  #   print "\tBY: $by\n" unless $by eq "";
  #   print "\tKEY: $key\n";
  #  #  print "BODY: '$body'\n";
  # }

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

if ((!$no_done) && (!$dry)) {

  export_done();

} elsif ((!$no_done) && ($dry)) {

  print "DRYRUN: would have exported done\n";

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
  # print "DOLLAR1: \"$staff1\", STAFF: " . $staff{$staff1} . "\n" unless $staff1 eq "";

  # action

  $title =~ s/(.*?\s{2,})//;
  my $action = $1;
  if ($action =~ m/changed the Summary of/) {
    # need to remove the first 'to' from the title
    # print "Summary change\n" if $debug;
    $title =~ s/([A-Z]*-[0-9]*)\s*to.*?'(.*)'/$1 - $2/;
    # print "New Title (Summary Change): $title\n" if $debug;
  }

  $title =~ s/with a resolution of '(.*)'//;
  my $resolution = $1;

  # for simplity we're going to consider a status change a resolution
  if (($resolution) && ($resolution =~ m/changed the status to (.*) on/)) {
    # print "Status change not resolution\n" if $debug;
    $resolution = $1;
  }

  ## if $resolution is still null at this point, make it equal to action
  if (!$resolution) { $resolution = $action; } # not the best idea but it works

  my $timespent;
  if ($action =~ m/Time Spent/) {

    $title =~ s/(by '[0-9]* day')//;
    $timespent = $1;

  }

  # print "ACTION: $action\n";
  # print "RESOLUTION: $resolution\n" if $resolution;
  # print "TIME SPENT: $timespent\n" unless !$timespent;

  # remove trailing whitespace

  $title =~ s/\s*$//;

  my ($key) = $title =~ m/([A-Z]+-[0-9]+)/;

  # print "##Returning Munged Title##\n\n";
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

  print "Usage: $0 [--days=x] [--ignore_weekly=x] [--no-tiems] [--short-items] [--no-export-done] [--use-rss-file=/path/to/filename.rss] [--write-rss]\n";
  exit;

}
