#!/usr/bin/perl


=head1

   This script is the glue between parse_res.pl and Analyze.pm: it
   takes a directory name as argument, and calls parse_res.pl on all
   the .html files in the directory. It parses the output of
   parse_res.pl, and builds a datastructure suitable for Analyze.pm,
   which is then called, thus printing results nicely formatted.

   A simple way to use it is:
      ./summarize_results.pl --dir my-dir

   A useful flag is '--ref': it sets which flag to use as reference:
      ./summarize_results.pl --dir my-dir --ref=--gc-freelist-strategy=2

   Another useful flag is --labels, provided that %labels is up to
   date with the benchmark: it uses labels for the flags. (it was very
   useful for me because I was comparing stuffs like
   "--gc-freelist-strategy=0" vs "--gc-freelist-strategy=1" etc., but
   if you have more descriptive flags, you shouldn't need it).

=cut

use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Data::Printer;
use Getopt::Long;
use List::Util qw( max );
use Term::ANSIColor;
use Statistics::Test::WilcoxonRankSum;
use Sort::Key::Natural qw( natsort natkeysort );
$| = 1;

use FindBin;
use lib $FindBin::Bin;
use Analyze;


# ---------------------------------------------------------------------- #
#                            FLAGS                                       #
# ---------------------------------------------------------------------- #
my ($dir, $ref, $out, $filter, $use_labels, $filter_before_labels);
GetOptions("dir=s",    \$dir,    # What directory summarize
           "ref=s",    \$ref,    # What flag to use as reference
           "filter=s", \$filter, # Regex filter to apply to chose which flag to keep
           "labels",   \$use_labels, # If true, uses labels for flags
           "filter-before-labels", \$filter_before_labels); # If true, applies filter before label conversion

# Just add your new labels here. Analyze's output will be nicer if you
# can keep the label's size under 15 characters.
my %labels = (
  "--gc-freelist-strategy=0"  => "Legacy",
  "--gc-freelist-strategy=4"  => "ManyFast",
  "--gc-freelist-strategy=33" => "HalfSmallManyF",
  "--gc-freelist-strategy=34" => "HalfManyF",
  "--gc-freelist-strategy=28" => "ManyMore2k",
  "--gc-freelist-strategy=10" => "ManyMore",
  "--gc-freelist-strategy=29" => "MMoreLoop",
  "--gc-freelist-strategy=30" => "MMoreLoopLarge",
  "--gc-freelist-strategy=9"  => "LegaSlowRetry",
  "--gc-freelist-strategy=26" => "LegaSlowSmalls",
  "--gc-freelist-strategy=2"  => "Many"
  );


if (!defined $dir) {
  say "Usage: $0 --dir <dir> --ref <ref_column> (--out <out_file>)";
  exit 0;
}

# Acquiring the data.
my (%data, @files);
my @all_files = glob("$dir/*.html");
my $file_cpt = 0;
for my $file (@all_files) {
  my ($name) = $file =~ m{([^/]+)\.html};
  printf "\rReading files....... %d/%d ($name)          ", ++$file_cpt, scalar @all_files;
  push @files, $name;
  my $output = `perl parse_res.pl --file $file --details`;
  my @chunks = split /\n\n/, $output;
  for my $chunk (@chunks) {
    my ($metric) = $chunk =~ /^([^-].*\))$/m;
    while ($chunk =~ /(--\S+): (\S+)(?: (\S+))?(?: \[(.*)\])/g) {
      my ($exp, $val, $stdev, $values) = ($1, $2, $3, $4);
      if ($filter_before_labels && $filter && $exp !~ /$filter/) {
        next;
      }
      $exp = $labels{$exp} // $exp if $use_labels;
      if (!$filter_before_labels && $filter && $exp !~ /$filter/) {
        next;
      }
      $ref //= $exp;
      $data{$exp}->{$metric}->{$name} = { #val     => remove_gmk($val),
                                          #stdev   => $stdev,
                                         values => [ split /,/, $values]};
    }
  }
}
print "\rReading files....... done.", " "x30, "\n";

Analyze::process_data(\%data, $ref);
