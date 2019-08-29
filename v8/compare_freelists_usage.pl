#!/usr/bin/perl

=head1

   This script compares traces of `d8 ... --trace-gc-freelists`. It
   then prints nicely the results in a way that allow to see what are
   the freelists usage before each major GC (a tiny bit of
   customization will print the freelists after GC rather than before;
   see line ~57 or so).

   It can be invoked in two diffent ways :

     - with a trace on STDIN (typically from a pipe), or

     - with one ore more filenames as arguments.


   For instance:,
       ./d8 run.js --trace-gc-freelists | ./compare_freelists_usage.pl

   or 

       ./d8 run.js --gc-freelist-strategy=0 --trace-gc-freelists > trace-0.txt
       ./d8 run.js --gc-freelist-strategy=2 --trace-gc-freelists > trace-2.txt
       ./compare_freelists_usage.pl trace-0.txt trace-2.txt


   Warning: if you want to compare a lot of traces, you better have a
   wide terminal ;)

=cut

use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Cwd;
use Getopt::Long;
use Data::Printer;
use List::Util qw( sum max );

# Preveting sigint. Useful when running only partially a benchmark
# piped to this script.
$SIG{INT} = sub { };


# If ARGV not supplied, just looking ad STDIN (no comparison then)
if (!@ARGV) {
  my $stats = compute_avg(compute_fl_stats(\*STDIN));
  # say "After:";
  # print_data($stats->{after});
  say "Before:";
  print_data($stats->{before}, 'anonymous (stdin)');
  exit;
}

# ARGV supplied; comparing traces
my %data;
for my $filename (@ARGV) {
  my ($name) = $filename =~ m{ /? ([^/]+) (?:\.[^.]+) }x;
  $data{$name}->{raw} = compute_fl_stats_file($filename);
}

# Computing average
my @out;
for my $file (sort keys %data) {
  $data{$file}->{avg} = compute_avg($data{$file}->{raw});
  $data{$file}->{max} = compute_max($data{$file}->{raw});
  
# ---------------------------------------------------------------------- #
#                                                                        #
#       Beginner: Just change this 'before' by an 'after' if you want    #
#                                                                        #
# ---------------------------------------------------------------------- #
  push @out, sprint_data($data{$file}->{avg}->{before}, $file);
}

say side_by_side(@out);


sub compute_fl_stats_file {
  open my $FH, '<', shift;
  return compute_fl_stats($FH);
}
sub compute_fl_stats {
  my $FH = shift;
  my %stats;
  while (<$FH>) {
    if (/after sweeping/ .. /before collection/) {
      while (/\[\s*(\d+)\s*:\s*(\d+)\s*\|\|\s*(\S*)\s*KB\]/g) {
        push @{$stats{after}->{$1}->{length}}, $2;
        push @{$stats{after}->{$1}->{size}}, $3;
      }
    }
    if (/before collection/ .. /after sweeping/) {
      while (/\[\s*(\d+)\s*:\s*(\d+)\s*\|\|\s*(\S*)\s*KB\]/g) {
        push @{$stats{before}->{$1}->{length}}, $2;
        push @{$stats{before}->{$1}->{size}}, $3;
      }
    }
  }
  return \%stats;
}

sub compute_avg {
  my ($stats) = @_;
  my %res;
  for my $when (qw(before after)) {
    for my $n (keys %{$stats->{$when}}) {
      $res{$when}->{$n}->{length} = sprintf '%.2f', sum(@{$stats->{$when}->{$n}->{length}}) / @{$stats->{$when}->{$n}->{length}};
      $res{$when}->{$n}->{size}   = sprintf '%.2f', sum(@{$stats->{$when}->{$n}->{size}})   / @{$stats->{$when}->{$n}->{size}};
    }
  }
  return \%res;
}

sub compute_max {
  my ($stats) = @_;
  my %res;
  for my $when (qw(before after)) {
    for my $n (keys %{$stats->{$when}}) {
      # Warning: max and sum could be from different items
      $res{$when}->{$n}->{length} = sprintf '%.2f', max(@{$stats->{$when}->{$n}->{length}});
      $res{$when}->{$n}->{size}   = sprintf '%.2f', max(@{$stats->{$when}->{$n}->{size}});
    }
  }
  return \%res;
}

sub sprint_data {
  my ($data, $name) = @_;
  my $res = '';
  my ($length, $size) = (0,0);
  $res .= sprintf "-----------+--------------+-------------\n";
  $res .= sprintf "  $name  \n";
  $res .= sprintf "-----------+--------------+-------------\n";
  $res .= sprintf " Freelist  |    length    |     size    \n";
  $res .= sprintf "-----------+--------------+-------------\n";
  for my $n (sort {$a <=> $b} keys %$data) {
    $res .= sprintf " %8d  |  %10.2f  |  %10.2f\n", $n, $data->{$n}->{length}, $data->{$n}->{size};
    $length += $data->{$n}->{length};
    $size   += $data->{$n}->{size};
  }
  $res .= sprintf "-----------+--------------+-------------\n";  
  $res .= sprintf "   Total   |  %10.2f  |  %10.2f\n", $length, $size;
  return $res;
}

sub print_data {
  print sprint_data(@_);
}

sub side_by_side {
  my @texts = @_;
  my $sep = "        @@@        ";
  my @lines = map { [ split /\n/ ] } @texts;
  my @paddings = map { max map { length } @$_ } @lines;
  my @res_lines;
  for my $line (0 .. max map { $#$_ } @lines) {
    push @res_lines, join $sep, map { sprintf "%-*s", $paddings[$_], $lines[$_][$line] || "" } 0 .. $#lines;
  }
  return join "\n", @res_lines
}
