#!/usr/bin/perl

package Analyze;


=head1

  This modules takes raw data as input, compares them, and prints
  them, nicely formatted. In particular, it runs wilcoxon's rank-sum
  test to find out whether the various dataset have distinguisable
  distributions or not.

  If you are "a user", you probably don't need to understand how this
  work and should look at the scripts using it rather.

=cut


use strict;
use warnings;
use v5.14;
use autodie qw( open close );
use Carp;

use Data::Printer;
use Data::Dumper;
use Getopt::Long;
use List::Util qw( max sum );
use Term::ANSIColor;
use Statistics::Test::WilcoxonRankSum;
use Sort::Key::Natural qw( natsort natkeysort );
$| = 1;

# If true, then when printing, uses numbers as column headers rather than experiment names.
our $SHORT_NAMES = 0;

# Sizes of the column (adds 2 for left and right padding)
our $COL_SIZE = 15;

# Keeping track of a bench of stuffs to facilitate printing
my (%benchs, %metrics);

sub process_data {
  my ($data, $ref) = @_;
  compare_data($data, $ref);
  output_data($data, $ref);
}

# compare_data(
#   {
#     "ref" => {
#       "old_space:effective_size (max)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#       "JS:duration (avg)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#     },
#     "--never-compact" => {
#       "old_space:effective_size (max)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#       "JS:duration (avg)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#     },
#     "--always-compact" => {
#       "old_space:effective_size (max)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#       "JS:duration (avg)" => {
#         "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#         "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] }
#       },
#     }
#   },
#   ...
#   );

# $data should be organized in the folowing way:
#   { <experiment> : <metric> : <benchmark> : { values => [ values ] } }
# For Instance, the folowing input is valid:
#   { "--never-compact" =>
#       { "old_space:effective_size (max)" =>
#             { "facebook"     => { values => [ "89M", "87M", "92M", "93M", "85M", "87M" ] },
#               "speedometer2" => { values => [ "31M", "28M", "31M", "30M", "36M", "35M" ] },
#       { "JS:duration (avg)" =>
#             { "facebook"     => { values => [ ... ] },
#               "speedometer2" => { values => [ ... ] } } },
#    "--always-compact" => ... ,
#    ...
#   }


# Computes wilcoxon, arithmetic means, and difference with the reference.
# $ref is the experiment to use as reference.
sub compare_data {
  my ($data, $ref) = @_;
  if (!$ref || !exists $data->{$ref}) {
    croak "Missing or invalid \$ref";
  }

  # For each experiment
  my $total_exp_count   = keys %$data;
  my $current_exp_count = 0;
  for my $exp (natsort keys %$data) {
    $current_exp_count++;

    # For each metric
    my $total_metric_count   = keys %{$data->{$exp}};
    my $current_metric_count = 0;
    for my $metric (natsort keys %{$data->{$exp}}) {
      $current_metric_count++;
      $metrics{$metric} = 1;

      # For each benchmark
      my $total_bench_count   = keys %{$data->{$exp}->{$metric}};
      my $current_bench_count = 0;
      for my $bench (natsort keys %{$data->{$exp}->{$metric}}) {
        $current_bench_count++;
        $benchs{$bench} = 1;
        
        progress("Computing statistics...... %d/%d - %d/%d - %d/%d    ($exp - $metric - $bench)",
                 $current_exp_count, $total_exp_count, $current_metric_count, $total_metric_count,
                 $current_bench_count, $total_bench_count);

        my $current = $data->{$exp}->{$metric}->{$bench};
        my $ref     = $data->{$ref}->{$metric}->{$bench};
        
        # Computing wilcoxon
        $current->{proba} = wilcoxon($current->{values}, $ref->{values});

        # Computing average
        $current->{mean} = mean($current->{values});
        $ref->{mean}   //= mean($ref->{values});

        # Computing difference with ref
        if (defined $current->{higher_is_better}) {
          $current->{diff} = $current->{mean} / $ref->{mean};
        } else {
          $current->{diff} = $ref->{mean} / $current->{mean};
        }
      }
    }
  }

  progress("Computing statistics..... done\n");
}

# Nicely format and outputs some data
sub output_data {
  my ($data, $ref) = @_;

  # Computing new column names 
  my %headers;
  if ($SHORT_NAMES) {
  short_names:
    $SHORT_NAMES = 1;
    my $header_cnt = 0;
    for my $exp (natsort keys %$data) {
      $headers{$exp} = $header_cnt++;
    }
  } else {
    for my $exp (natsort keys %$data) {
      goto short_names if length $exp > $COL_SIZE;
      $headers{$exp} = $exp;
    }
  }

  # Computing firt column (benchmark) padding
  my $bench_padding = compute_padding();

  # Outputing the results
  for my $metric (natsort keys %metrics) {
    # First line (metric name)
    say "\n*************** $metric ***************";

    # Second line (headers)
    say join " | ", (" " x ($bench_padding+1)), map { sprintf "%-*s", $COL_SIZE, $headers{$_} } natsort keys %$data;

    # Third line (separation)
    say join "-+-", ("-" x ($bench_padding+1)), map { "-" x  $COL_SIZE } natsort keys %$data;

    # The data
    my %overall;
  bench_loop:
    for my $bench (natsort keys %benchs) {
      my @line = sprintf " %-*s", $bench_padding, $bench;
      for my $exp (natsort keys %$data) {
        my $current = $data->{$exp}->{$metric}->{$bench} || next bench_loop;
        push @{$overall{$exp}}, $current->{diff};
        my $color = $current->{diff} > 1 ? 'green' : $current->{diff} < 1 ? 'red' : 'yellow';
        $color = 'yellow' if $current->{proba} > 0.05;
        my $print = sprintf "%s (x%.2f)", add_gmk($current->{mean}), $current->{diff};
        push @line, sprintf "%s%-*s%s", color($color), $COL_SIZE, $print, color('reset');
      }
      say join " | ", @line;
    }

    # Separation line
    say join "-+-", ("-" x ($bench_padding+1)), map { "-" x  $COL_SIZE } natsort keys %$data;

    # Overall numbers
    my @line = sprintf " %-*s", $bench_padding, 'overall';
    for my $exp (natsort keys %$data) {
      my $mean = mean($overall{$exp});
      my $color = $mean > 1 ? 'green' : $mean < 1 ? 'red' : 'yellow';
      my $print = sprintf "x%.3f", $mean;
      push @line, sprintf "%s%-*s%s", color($color), $COL_SIZE, $print, color('reset');
    }
    say join " | ", @line;
    
    say "";
  }
  say "";

  if ($SHORT_NAMES) {
    for my $exp (natsort keys %$data) {
      printf "%2d: $exp\n", $headers{$exp};
    }
    say "";
  }
  
}

# Compute Wilcoxon Rank-Sum test between two datasets.
sub wilcoxon {
  my ($dataset1, $dataset2) = @_;
  my $wilcox_test = Statistics::Test::WilcoxonRankSum->new();
  $wilcox_test->load_data($dataset1, $dataset2);
  return $wilcox_test->probability();
}

# Remove G/M/K from the end of a number.
sub remove_gmk {
  no warnings 'numeric';
  my $val = shift;
  return $val * 1_000_000_000 if $val =~ /G/;
  return $val * 1_000_000     if $val =~ /M/;
  return $val * 1_000         if $val =~ /K/;
  return $val;
}

# Add G/M/K at the end of a number.
sub add_gmk {
  my $val = shift;
  return sprintf "%.2fG", $val / 1_000_000_000 if $val > 1_000_000_000;
  return sprintf "%.2fM", $val / 1_000_000     if $val > 1_000_000;
  return sprintf "%.2fK", $val / 1_000         if $val > 1_000;
  return sprintf "%.2f", $val;
}

# Compute the arithmetic mean of an arrayref
sub mean {
  return sum(@{$_[0]}) / @{$_[0]};
}

# Compute benchmark padding
sub compute_padding {
  return max map { length } keys %benchs;
}

# Print a progression message
sub progress {
  my $msg = sprintf $_[0], @_[1 .. $#_];
  print "\r\e[K", $msg;  
}

1;
