#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use JIRA::Client::Automated;

use Data::Dumper;
use POSIX;

use Term::ANSIColor;

my ($verbose, $debug, $dry, $help);
my ($archive, $create);
my ($parent, $project, $summary, $description);
my $test;
my ($dparent, $dproject, $dsummary, $ddescription);

GetOptions(
	   "verbose" => \$verbose,
	   "debug" => \$debug,
	   "archive" => \$archive,
	   "create" => \$create,
	   "help" => \$help,
	   "parent=s" => \$parent,
	   "project=s" => \$project,
	   "summary=s" => \$summary,
	   "description=s" => \$description,
	   "test" => \$test,
	   "dry-run" => \$dry,
);

if ($help) { usage(); exit;}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $month = $abbr[$mon];
my $day = $mday;
$year += 1900;

require "jira_weekly.conf";
my $username = username();
my $password = password();
my $jira_domain = getjiradomain();

if ($test) {

  $dparent = "TP-8";
  $dproject = "TP";
  $dsummary = "Test $hour:$min:$sec";
  $ddescription = "Testing Creation";

} else {

  $dparent = get_dparent();
  $dproject = get_dproject();
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

my $filename = $ARGV[0] || "/tmp/done.txt";

if ((!$archive) && (!$create)) {
  pc("Neither --archive nor --created given, exiting", $errcol);
  exit;
}

if ($archive) {
  pc("Using $filename", $normcol) if $debug;

  my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);

  my $days = ceil((time() - $mtime)/(60*60*24));

  if ($days > 1) {

    pc("$filename is $days days old", $warncol);

  } else {

    pc("$filename is $days days old", $normcol);

  }

  pc("Display contents (Y/n)?", $normcol);

  my $yorn = <>;
  chomp($yorn);
  if ($yorn ne "n") {
    print "\n";
    display_file($filename);
  }

  pc("Proceed to Archive (Y/n)?", $normcol);
  $yorn = <>;
  chomp($yorn);
  if ($yorn eq "n") {
    pc("...Exiting\n", $normcol);
    exit;
  }

  open (FILE, "<$filename") or die("cannot open $filename: $!");

  while(<FILE>) {
    chomp;

    # fetch_issue($_) if $debug;

    if (!$dry) {
      pc("archiving $_", $bugcol) if $debug;
      $jira->transition_issue($_, "Archived");

    } else {

      pc("DRYRUN: would have moved $_ to Archived", $drycol);

    }

  }

  close (FILE);

}  # end archiving

if ($create) {

  $parent = $dparent unless $parent;
  $project = $dproject unless $project;
  $summary = $dsummary unless $summary;
  $description = $ddescription unless $description;

  pc("Creating $project, $summary, $description as subtask of $parent", $normcol);
  pc("Proceed? (Y/n)?", $normcol);

  my $yorn = <>;
  chomp($yorn);

  if ($yorn ne "n") {

    pc("ok I'm doing it -- you had your chance", $okcol);

  } else {

    die ("Whew that was a close one\n");

  }

  # my $issue = $jira->create_issue($project, $type, $summary, $description);

  my $subtask;

  if (!$dry) {
    $subtask = $jira->create_subtask($project, $summary, $description, $parent);
  } else {

    pc("DRYRUN: would have created $project, $summary, $description as subtask of $parent", $drycol);

  }

  # print Dumper \$issue;

  print Dumper \$subtask if $debug;

  # print "FETCH TP-9\n";
  # fetch_issue('TP-9');

  # now it should probably be updated to "done"


  if (!$dry) {
    pc("update to Done", $normcol);
    $jira->transition_issue($subtask->{'key'}, "Done");
  } else {
    pc("DRYRUN: would have transistioned the newly created task to Done", $drycol);
  }

}

sub display_file {
  my $filename = shift;

  open (FILE, "<$filename");

  my @lines = <FILE>;

  my @sorted = sort @lines;

  foreach (@sorted) {

    print $_;

  }

  close(FILE);

}

sub fetch_issue {
  my $key = shift;

  my $jql = "issue = $key";

  my @results = eval{ $jira->all_search_results($jql, 1) };

  if (@results) {

    print Dumper \@results;

  }


}


sub usage {

  print "$0 [--archive] [--create] [filename]\n";
  print "\tIf no filename given, will use /tmp/done.txt\n";

}


sub pc {

  my ($txt, $color) = @_;
  
  print colored($txt, $color) . "\n";

}
