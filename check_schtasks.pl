#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  schtasks.pl
#
#        USAGE:  ./schtasks.pl
#
#  DESCRIPTION: nagios plugin to check if the scheduled tasks have run fine
#               The script parses the output of schtasks.exe
#
#      OPTIONS:  ---
# REQUIREMENTS:  Text::CSV_XS must be installed
#         BUGS:  plenty, but not yet found
#        NOTES:  ---
#       AUTHOR:  nasenjo@asenjo.nl
#      COMPANY:
#      VERSION:  1.0
#      CREATED:  06-10-2010 13:47:51
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Text::CSV_XS;

# variables
my ( $version, $revision, $help, %lastresult_of, $checknow, %exclusions,
    %lastresult_excl );
my %ERRORS = (
    'OK'        => 0,
    'WARNING'   => 1,
    'CRITICAL'  => 2,
    'UNKNOWN'   => 3,
    'DEPENDENT' => 4,
);

$version = '1.1';

Getopt::Long::Configure( "no_ignore_case", "bundling" );
GetOptions(
    'c|checknow'  => \$checknow,
    'h|help|?'    => \$help,
    'V|version'   => \$revision,
#    'e|exclude=s%' => sub{ push ( @{$exclusions{$_[1]}}, $_[2] ) },
    'e|exclude=s%'=> \%exclusions,
);

# get version info if requested and exit
if ($revision) {
    print "$0 version: $version\n";
    exit $ERRORS{OK};
}
pod2usage( -verbose => 2, -noperldoc => 1, ) if $help;

pod2usage( -verbose => 1, -noperldoc => 1, ) unless $checknow;

use Data::Dumper;
print Dumper %exclusions;

#if ( $^O ne "MSWin32" ) {
#    print "Sorry, this is a MS Windows(TM) check, run it in a MS Windows(TM) host\n";
#    exit $ERRORS{UNKNOWN};
#}

# run schtaks, keep output in JOBS memory handle
# switches for schtasks.exe:
# /query: get the list of scheduled jobs
# /fo csv: dump the list as in csv format
# /v: verbose
#open (JOBS, "schtasks /query /fo csv /v |") or die "couldn't exec schtasks: $!\n";

open (JOBS, "<" , "/home/j.asenjo/Desktop/temp/tasks.csv") or die "$!\n";

my $csv = Text::CSV_XS->new( { binary => 1,
                               allow_loose_escapes => 1,
                             } );

# parse JOBS memory handle. The output is a csv file. The second column ($columns[1] is "Taskname",
# the 7th $columns[6] is "Last Result". I only need the values of "Last Result" which are NOT 0 (0 is good, it means it ran well).
# Because in windows 2008 the task scheduler has been revamped, there are a lot of new scheduled jobs that are not important, so I
# filter them in the next if statements

while ( my $line = <JOBS> ) {
    last if $line =~ /^INFO: There are no scheduled tasks.*$/;


    if ( $csv->parse($line) ) {
        my @columns = $csv->fields();

        # Skip lines

        # skip the header
        next if $columns[1] eq "TaskName";

        # skip if next run time is 'disabled'
        next if $columns[2] eq "Disabled"; 

        # skip if status column is 'disabled'
        next if $columns[3] eq "Disabled"; 

        # skip if the task is running now
        next if $columns[3] eq "Running";  

        # skip if last run time is empty
        next if $columns[5] eq "N/A";    

        # skip if 19th colum is 'At logon time"
        next if $columns[18] eq "At logon time";    

        # process the cli exclussions now
        # These are stored in a hash containing array references as values, so
        # first we check the value is an array ref, then we skip the line if
        # the exclusion matches with $columns[1] and $columns[6]. Thanks to
        # perlmonk Eliya for helping me out with this: http://www.perlmonks.org/?node_id=941495
        if ( $columns[6] != 0 ) {
            if ( ref ( my $excl = $exclusions{$columns[1]} ) eq "ARRAY") {
                next if grep $_ == $columns[6], @$excl;
                }
            }

        # if last result is other than 0, save taskname and last result
        # in the %lastresult_of
        if ( $columns[6] != 0 ) {
            $lastresult_of{ $columns[1] } = $columns[6];
        }
    }
}

# if the %lastresult_of is empty, this will be zero
if ( scalar keys %lastresult_of == 0 ) {
    print "OK: All scheduled tasks seem to have run fine\n";
    exit $ERRORS{OK};
}
else {
    while ( my ( $key, $value ) = each(%lastresult_of) ) {
        print "WARNING: scheduled task [$key] finished with error [$value]\n";
    }
    exit $ERRORS{WARNING};
}

=head1 NAME

check_schtasks

=head1 SYNOPSIS

check_schtasks -c [-e name_scheduled_job=exitvalue]

=head1 DESCRIPTION

Nagios plugin to check the status of Windows scheduled tasks.

This plugin *must* be run in a Windows hosts. Check it from NRPE.

The plugin requires Perl in the Windows hosts with the Text::CSV_XS
module. You can install this easily from activestate.com

The way the plugin works is running schtasks.exe /query /fo csv /v
and parsing its output.

Standard this plugin will skip disabled, running tasks or jobs that
run at logon time. I also skip the 'Customer Experience' tasks,
they mostly run incorrectly without an internet connection anyway
and in my modest opinion they should not be there in the first place.

You can also exclude scheduled tasks. If the name of the task has empty
spaces, enclose in inverted quotes ( --exclude "name with space"=3
). You can exclude multiple tasks, but only the same task once (I am
trying to work out that limitation).

This plugin has been tested in Windows 2003(r2) and 2008(r2), both 32
and 64 bit editions.

This plugin will probably not work in locales other that English without
changes to the script. As I only work with Windows versions in English,
I cannot help you if it does not work in a French, German, ..., locale.
Just adapt the script to your needs.

=head1 ARGUMENTS

-c | --checknow:        required

-V | --version:         prints the version of this program

-e | --exclude:         exclude tasks. This should be a key=value
combination, where key is the task name and value the task exit value.

-h | --help | -?:       print this help text

EXAMPLES:

To check all scheduled jobs without exceptions:

check_schtaks -c

To check all scheduled jobs except the task name "job with spaces in
it" with exit level 2:

check_schtasks -c --exclude "job with spaces in it"=2

=head1 AUTHOR

natxo asenjo in his spare time

=cut
