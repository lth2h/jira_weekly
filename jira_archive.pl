#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use JIRA::Client::Automated;

use Data::Dumper;
use POSIX;

use Term::ANSIColor;

use YAML;
use File::Slurp;

my ($verbose, $debug, $dry, $help, $quiet);
my ($archive, $create, $both);
my ($parent, $project, $summary, $description);
my $test;
my ($dparent, $dproject, $dsummary, $ddescription);
my $yorn;

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
	   "quiet" => \$quiet,
	   "both" => \$both,
);

if ($help) { usage(); exit;}

if ($both) {$create = $archive = 1;}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $month = $abbr[$mon];
my $day = $mday;
$year += 1900;

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)};

my $username = $yh{"username"};
my $password = $yh{"password"};
my $jira_domain = $yh{"jira_domain"};

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

my $filename = $ARGV[0] || "/tmp/done.txt";

if ((!$archive) && (!$create)) {
  pc("Neither --archive nor --created given, exiting", $errcol);
  exit;
}

if ($archive) {
  pc("Using $filename", $normcol) if $debug;

  if (!(-f $filename)) { 
    pc("$filename doesn't exist", $errcol); 
    exit;
  }

  my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);

  my $days = ceil((time() - $mtime)/(60*60*24));

  if ($days > 1) {

    pc("$filename is $days days old", $warncol);

  } else {

    pc("$filename is $days days old", $normcol);

  }

  pc("Display contents (Y/n)?", $normcol);

  $yorn = <>;
  chomp($yorn);
  if ($yorn ne "n") {
    print "\n";
    display_file($filename);
  }


  pc("Proceed to Archive (Y/n)?", $normcol);
  pc("DRYRUN: will not actually archive if you choose Y", $drycol) if $dry;
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
      pc("archiving $_", $vercol) unless $quiet;
      # $jira->transition_issue($_, "Archived");
      eval { $jira->transition_issue($_, "Archived") };
      # warn $@ if $@;
      if ($@) {
	open (F2, ">>$filename" . "_errors") or die("Could not open $filename" . "_errors: $!");
	print F2 $_;
	close(F2);
	warn $@;
      }

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
  pc("DRYRUN: will not actually archive if you choose Y", $drycol) if $dry;

  $yorn = <>;
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
    pc("Created " . $subtask->{'key'} . " as a subtask of $parent", $vercol) unless $quiet;

  } else {

    pc("DRYRUN: would have created $project, $summary, $description as subtask of $parent", $drycol);

  }

  # print Dumper \$issue;

  print Dumper \$subtask if $debug;

  # print "FETCH TP-9\n";
  # fetch_issue('TP-9');

  # now it should probably be updated to "done"


  if (!$dry) {
    $jira->transition_issue($subtask->{'key'}, "Done");
    pc("updated " . $subtask->{'key'} . " to Done", $vercol) unless $quiet;
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
