#!/usr/bin/perl

=head1

  This simple script parses traces produced with
  --trace-allocation-origins, and prints nice summaries.  

  (careful: it's not compatible with ToT --trace-allocation-origins,
  because it assumes that each print of allocation origins resets
  them)

=cut

use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Data::Printer;
use List::Util qw( max );
use FindBin;
$| = 1;

chdir $FindBin::Bin;

# Reading files to get the data
my %origins;
for my $file (glob("*.txt")) {
  open my $FP, '<', $file;
  my ($benchmark) = $file =~ /(.*)\.txt/;

  my ($generated_code, $runtime, $gc) = (0, 0, 0);
  while (<$FP>) {
    if (/Allocations Origins(?!.*(?:map|code|new)_space).*: GeneratedCode:(\d+) - Runtime:(\d+) - GC:(\d+)/) {
      $generated_code += $1;
      $runtime        += $2;
      $gc             += $3;
    }
  }

  $origins{$benchmark} = { generated_code => $generated_code,
                           runtime        => $runtime,
                           gc             => $gc };
}

# Outputing nicely formatted data
my $name_padding    = max map { length } keys %origins;
my $origins_padding = max map { length } keys %{$origins{(keys %origins)[0]}};
printf " %-*s | %-*s | %-*s | %-*s\n", $name_padding, 'Benchmark',
  map { $origins_padding, $_ } qw( generated_code runtime gc );
printf "%s+%s+%s+%s\n", map { "-" x (2+$_) } $name_padding, ($origins_padding)x3;
for my $benchmark (sort keys %origins) {
  printf " %-*s | %-*s | %-*s | %-*s\n", $name_padding, $benchmark,
    map { $origins_padding, format_num($origins{$benchmark}{$_}) }
      qw( generated_code runtime gc );
}


sub format_num {
  return $_[0] =~ s/\d\K(?=(\d{3})+$)/,/rg;
}
