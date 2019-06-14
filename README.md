# jira_weekly
Stuff for getting things out of that steaming pile known as JIRA 

Use the sample yaml file as a guide for configuration

Files:
- jira_weekly_report.pl -- extracts a weekly report of sorts from the "Activity Stream"
- jira_archive.pl -- moves items from Done to Archived and creates a weekly report task
- jira_get_last_report_date.pl -- guesses the date of the last "Weekly Report"
- jira_epic_report.pl -- extracts a report based on epics.
- get-issue-links.pl -- Prints the issuelinks hash from results->issues->fields->issuelinks

Might possibly need to install some extra Perl Modules including but not limited to:
  - JIRA::Client::Automated
  - Term::ANSIColor
  - File::Slurp
  - HTML::Strip
  - Lingua::EN::Sentence
  - XML::Feed
  
