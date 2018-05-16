#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;
use JIRA::Client::Automated;

use YAML;
use File::Slurp;

use Data::Dumper;

my ($verbose, $debug, $dry, $help, $quiet, $test);
my $display_comments = 1;
my $show_done;
my $bold_block;
# my $blocks_only; this requires relying on jql instead of what comes out of the issuelinks from the epic
# JQL: issue in linkedIssues("TP-3", "blocks")
my ($no_issues, $no_related, $no_jira);

my $jql;

GetOptions(
    "verbose" => \$verbose,
    "debug" => \$debug,
    "help" => \$help,
    "test" => \$test,
    "dry-run" => \$dry,
    "quiet" => \$quiet,
    "comments=i" => \$display_comments,
    "done" => \$show_done,
    "bold-block" => \$bold_block,
     #    "blocks-only" => \$blocks_only,
    "no-issues" => \$no_issues,
    "no-related" => \$no_related,
    "no-jira" => \$no_jira,
);

if ($no_jira) {
  $no_related = 1;
  $no_issues = 1;
}

if ($help) { usage(); exit;}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my @abbr = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

my $month = $abbr[$mon];
my $day = $mday;
$year += 1900;

my $rev = "<P>Revised $month $day, $year</P>\n";

my $yaml;
$yaml = read_file("jira_weekly.yaml");

my %yh = %{Load($yaml)};

print Dumper \%yh if $debug;

my $username = $yh{"username"};
my $password = $yh{"password"};
my $jira_domain = $yh{"jira_domain"};

my $jca_url = "https://$jira_domain/";

my $jira = JIRA::Client::Automated->new($jca_url, $username, $password);

# $jql needs to be constructed from %yh
my @project_leads = @{$yh{"projectleads"}};
my @assignees = @{$yh{"assignees"}};
my @excludeprojects = @{$yh{"excludeprojects"}};

# first get epics...

my $projectLeadByUser;
my $assignee;
my $notprojects;

foreach (@project_leads) {

    $projectLeadByUser .= "projectsLeadByUser($_), ";

}

$projectLeadByUser =~ s/, $//;
print "PROJECT-LEAD-BY-USER: $projectLeadByUser\n" if $debug;

foreach (@assignees) {

    $assignee .= "$_, ";

}
$assignee =~ s/, $//;

foreach (@excludeprojects) {

    $notprojects .= "\"$_\", ";

}

$notprojects =~ s/, $//;

$jql = "type = epic AND (project in ($projectLeadByUser) OR assignee in ($assignee) OR watcher in ($assignee)) AND project not in ($notprojects) AND status not in (Archived, Done) AND filter != \"done is archived\" ORDER BY Priority"; # filter should probably also be in the yaml config file

if ($show_done) {
    $jql = "type = epic AND (project in ($projectLeadByUser) OR assignee in ($assignee)) AND project not in ($notprojects) AND status = Done AND filter != \"done is archived\" ORDER BY Priority";
}

if ($test) {

    $jql = "type = epic AND project = \"Test Project\"";

}
print "JQL: $jql\n" if $debug;


# $results is a hash with keys: start total max issues
my $results = $jira->search_issues($jql, 0, 1000);

print Dumper \$results if $debug;

# we really only care about what is in the issues field
# @issues is an array of hashes in the "jira hash format"
# understanding this format leads to madness
# id fields self expand key
my @issues = @{$results->{issues}};

print Dumper \@issues if $debug;

foreach my $issue (@issues) {

    # note we are specifically interested in customfield_10900
    # what we need...key fields->{description} fields->status->name fields->customefield_10008 (that's the actual title) fields->id

    print Dumper \$issue->{"fields"} if $debug;

    print "\n\n<h2>";
    print $issue->{"fields"}->{"summary"};
    print "</h2>\n<P>";
    print $issue->{"key"};
    print " (Status: ";
    print $issue->{"fields"}->{"status"}->{"name"};
    print ") ";

    if ($issue->{"fields"}->{customfield_10900}) {
	print "<a href=\"";
	print $issue->{"fields"}->{customfield_10900};
	print "\">";
	print $issue->{"fields"}->{customfield_10900};
	print "</a>";
    } else {
	print "NOT TRACKED!";
    }

    print "</P>\n";

    print "<P>" . $issue->{"fields"}->{"description"} . "</P>\n" unless (!$issue->{"fields"}->{"description"});

    my @comments = @{$jira->get_issue_comments($issue->{"key"})};
    print Dumper \@comments if $debug;

    #we're going to assume that the comments are in the array in date order.  Display the last comment first
    if (($display_comments > 0) && (scalar(@comments) > 0)) {

	print "<ul><li>Comments:<ul>";
	for (my $i=$#comments; $i > $#comments-$display_comments; $i--) {

	    last if ($i < 0);
	    if (!$comments[$i]->{body}) {
		last;
	    }

	    print Dumper \@comments if $debug;

	    print "<li>";
	    print "<b><i>";
	    print $comments[$i]->{body};
	    print "</i></b> - ";
	    print $comments[$i]->{author}->{displayName};
	    print "</li>\n";

	}

	print "</ul></P></li></ul>\n";

    }


    # JIRA relations
    if ((!$no_jira) && (!$no_related) && ($issue->{"fields"}->{"issuelinks"})) {

      # print "ISSUELINKS LENGHT:" . scalar(@issuelinks) . "\n";
      my $relations = getRelations($issue);
      if ($relations) {
	print  "<ul><li>JIRA Relations and Blocks\n";
	print  $relations;
	print "</li></ul>";
      }

    }

    if ((!$no_jira) && (!$no_issues)) {

      # get all the subtasks of the epic and use parentEpic to get all the issues and subtasks of the epic
      my $jql2 = "(parent = " . $issue->{"key"} . ") or (parentEpic = " . $issue->{"key"} . " AND key != " . $issue->{"key"} . ")";

      print "JQL2: $jql2\n" if $debug;

      my $results2 = $jira->search_issues($jql2, 0, 1000);

      print Dumper \$results2 if $debug;

      my @epicsubtasks = @{$results2->{"issues"}};

      if (scalar(@epicsubtasks) > 0) {

	print "<ul><li>JIRA Issues in Epic\n";

	print "\n\n" . $#epicsubtasks . " EPIC SUBTASKS\n\n" if $verbose;

	print Dumper \@epicsubtasks if $debug;

	print "<ul>";
	foreach my $esubt (@epicsubtasks) {

	  print "\n\n=== esubt ===\n" if $debug;
	  print Dumper \$esubt if $debug;
	  print "\n===end esubt ===\n\n" if $debug;

	  print "<li>";
	  print $esubt->{"key"};
	  print " ";
	  print $esubt->{"fields"}->{"summary"};
	  print " (Status: ";
	  print $esubt->{"fields"}->{"status"}->{"name"};
	  print ")";
	  print getRelations($esubt);
	  print "</li>\n";

	}

	print "</ul>";

	print "</li></ul>\n";	# close JIRA

      }

      print "\n";

    }
  }

sub usage {

    # print "$0 [--project=projectID] [--epic=epicID] [--show-archived] \n";
    print "$0 [--test] [--done] [--comments=<number>] [OtherOptions] \n";
    print "\tGet activity on epics\n";
    print "OtherOptions:\n";
    print "\t--bold-block put blocking tasks in bold\n";
    print "\t--no-issues do not show JIRA issues in epic\n";
    print "\t--no-related do not show JIRA relations\n";
    print "\t--no-jira do not show anything JIRA (imples --no-issues and --no-related)\n";
    print "Note if you want no comments, set it to 0\n";

}



sub getRelations {

  my $rv;
  $rv .= "\n=== START getRelations ===\n" if $debug;
  my $theissue = shift;

    if ($theissue->{"fields"}->{"issuelinks"}) {

      my @issuelinks = @{$theissue->{"fields"}->{"issuelinks"}};
      # print "ISSUELINKS LENGHT:" . scalar(@issuelinks) . "\n";
      my $blocks_end = "";
      if (scalar(@issuelinks) > 0) {
	$rv .= "<ul>\n";
	$blocks_end = "</ul>\n";
      }

      foreach my $linked (@issuelinks) {
	# we don't know if it inward or outward without checking for the key
	# and we can't check for the key if it isn't a hashref

	# $rv .= Dumper \$linked;
	# $rv .= "REF:" . ref($linked) . "\n";

	if (ref $linked eq ref {}) {

	  if (exists($linked->{"inwardIssue"})) {
	    my $bold = 0;
	    if ($linked->{"type"}->{"inward"} =~ /block/) {
	      $bold = 1 if $bold_block;
	    }

	    $rv .= "<li>";
	    $rv .= "<B>" if $bold;
	    $rv .= $linked->{"inwardIssue"}->{"key"};
	    $rv .= " (" . $linked->{"inwardIssue"}->{"fields"}->{"summary"} . ") ";
	    $rv .= " " . $linked->{"type"}->{"inward"} . " ";
	    $rv .= $theissue->{"key"};
	    $rv .= "</B>" if $bold;
	    $rv .= "</li>\n";

	  }
	  if (exists($linked->{"outwardIssue"})) {

	    my $bold = 0;
	    if ($linked->{"type"}->{"outward"} =~ /block/) {
	      $bold = 1 if $bold_block;
	    }

	    $rv .= "<li>";
	    $rv .= "<B>" if $bold;
	    $rv .= $linked->{"outwardIssue"}->{"key"};
	    $rv .= " (" . $linked->{"outwardIssue"}->{"fields"}->{"summary"} . ") ";
	    $rv .= " " . $linked->{"type"}->{"outward"} . " ";
	    $rv .= $theissue->{"key"};
	    $rv .= "</B>" if $bold;
	    $rv .= "</li>\n";
	  }
	}

      }

      $rv .= $blocks_end;

    }
  $rv .= "\n=== END getRelations ===\n" if $debug;

  return $rv;
}
