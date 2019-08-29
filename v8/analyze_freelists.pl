#!/usr/bin/perl


=head1

   This script isolates memory usage and freelists data from traces of
   `d8 ... --trace-gc-freelists`. It should typically be piped into
   from a run of d8.

   For instance:,
       ./d8 run.js --trace-gc-freelists | ./analyze_freelists.pl

=cut

use strict;
use warnings;
use v5.14;
use List::Util qw(sum);
use Data::Printer;

$SIG{INT} = sub {};

my $cat_stats_re = qr/\[\s*(?<cat>\d+):\s*(?<length>\d+)\s*\|\|\s*(?<sum>\d+(?:\.\d+)?)\s*KB\s*\]/;

my @stats;
my %current;
my ($obj, $mem, $cnt) = (0,0,0);
say "Pages usage:";
while (<>) {
  if (/(\d+)\s*pages\./) {
    $current{pages} = $1;
  } elsif (/\[[^\]]+\]\s*$cat_stats_re(,\s*$cat_stats_re)+\s*$/) {
    while (/$cat_stats_re/g) {
      push @{$current{freelists}}, { length => $+{length}, sum => $+{sum} };
    }
    push @stats,  { %current };
    %current = ();
  } elsif (/Scavenge (\S+) \((\S+)\)/) {
    $obj += $1;
    $mem += $2;
    $cnt++;
  }
  if (@stats && @stats % 2 == 0) {
    my $before = $stats[0];
    my $after  = $stats[1];

    printf "Before: %4d pages; %9d free KB\n", $before->{pages},
      sum map $_->{sum}, @{ $before->{freelists} };
    printf "After : %4d pages; %9d free KB\n", $after->{pages},
      sum map $_->{sum}, @{ $after->{freelists} };
    @stats = ();
  }
}


say "\nAverage memory used:";
printf "%d (%d)\n", $obj/$cnt, $mem/$cnt;
