#!/usr/bin/perl

=head1

  This script is an old version of compare_octane.pl.
  It doesn't depend on Analyze.pm, and doesn't store the results on file.

  DO NOT USE! Use compare_octane.pl instead.

  I'm leaving it here, just in case it might be useful in the future,
  for whatever reason.

=cut

use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Getopt::Long;
use List::Util qw( sum product );

my $nb_run = 20;
my $d8     = './d8';
my $runner = 'run.js';
my $cp_d8  = 1;
my $ref;
my $out_dir;
my $js_flags = "";

my @opts = maps { "--gc-freelist-strategy=$_" } 0 .. 13;

GetOptions("nb-run=i",   \$nb_run,
           "d8=s",       \$d8,
           "cp-d8",      \$cp_d8,
           "runner=s",   \$runner,
           "out=s",      \$out_dir,
           "js_flags=s", \$js_flags,
           "opts=s",     \@opts);
@opts = split(/,/, join(',', @opts), -1);


# Preparing out directory
if (! $out_dir) {
  die "Output director not specified. --out flag is mandatory. Exiting."
}
chdir $FindBin::Bin;
make_path $out_dir;
make_path "$out_dir/logs";

# Copy d8 executable
if ($cp_d8) {
  copy $_, "." for glob "../../../../out/x64.release/{d8,natives_blob.bin,snapshot_blob.bin}";
  $d8 = './d8';
  $ENV{D8_PATH} = getcwd();
} else {
  $ENV{D8_PATH} = dirname $d8;
}

my (%timings, %mem);

for my $n (1 .. $nb_run) {
  for my $opt (@opts) {
    my $opt_name = $opt || 'none';
    say "opt: $opt_name ($n/$nb_run)...";
    my $cmd = "$d8 $runner --predictable-gc-schedule --trace-gc $opt";
    my $res = `$cmd`;
    
    # Computing perf
    my $time = 0;
    $time += $_ for $res =~ /\(Score\):\s*(\d+)/g;
    push @{$timings{$opt}}, $time;

    # Computing memory
    my $mem_used     = 0;
    my $mem_reserved = 0;
    my $measure_cnt  = 0;
    while ($res =~ /Scavenge (\S+) \((\S+)\)/g) {
      $mem_used     += $1;
      $mem_reserved += $2;
      $measure_cnt++;
    }
    $mem_used     /= $measure_cnt;
    $mem_reserved /= $measure_cnt;
    push @{$mem{used}->{$opt}}, sprintf "%.2f", $mem_used;
    push @{$mem{reserved}->{$opt}}, sprintf "%.2f", $mem_reserved;

    # Short stats
    printf "Perf:  %d\n", $time;
    printf "Mem :  %d (%d)\n", $mem_used, $mem_reserved;
  }

  say "\n", "-"x10;
  say "\nPerformances:";
  print_res_short(\%timings);
  say "Memory reserved:";
  print_res_short($mem{reserved});
  say "\n", "-"x30, "\n";
}


say "\n", "*"x80;
say " "x30, "Overall\n";

for my $fn (\&print_res, \&print_res_short) {
  say "Performances:";
  $fn->(\%timings);

  # say "\nMemory Used:";
  # $fn->($mem{used});

  say "\nMemory Reserved:";
  $fn->($mem{reserved});

  say "\n\n";
}



sub print_res {
  my $data = shift;
  
  my $padding = 0;
  for (keys %$data) {
    $padding = length > $padding ? length : $padding
  }
  
  for my $opt (keys %$data) {
    printf "%*s: [%s]\n", $padding, $opt, join ',', @{$data->{$opt}};
  }
  
  print_res_short();
}

sub print_res_short {
  my $data = shift;
  
  my $padding = 0;
  for (keys %$data) {
    $padding = length > $padding ? length : $padding
  }

  # Arithmetic mean
  for my $opt (keys %$data) {
    my $u = sum(@{$data->{$opt}})/@{$data->{$opt}}; # mean
    my $s = ( sum( map {($_-$u)**2} @{$data->{$opt}} ) / @{$data->{$opt}} ) ** 0.5; # standard deviation
    printf "[ari-mean] %*s: %.2f +-%.2f\n", $padding, $opt, $u, $s;
  }

  # Geometric mean
  # for my $opt (keys %$data) {
  #   my $u = product(@{$data->{$opt}}) ** (1 / @{$data->{$opt}}); # mean
  #   my $s = exp( (sum( map { log($_/$u)**2 } @{$data->{$opt}} ) / @{$data->{$opt}} ) ** 0.5); # geo standard deviation
  #   printf "[geo-mean] %*s: %.2f +-%.2f\n", $padding, $opt, $u, $s;
  # }
}

# Compute Wilcoxon Rank-Sum test between two datasets.
sub wilcoxon {
  my ($dataset1, $dataset2) = @_;
  my $wilcox_test = Statistics::Test::WilcoxonRankSum->new({ exact_upto => 10 });
  $wilcox_test->load_data($dataset1, $dataset2);
  return $wilcox_test->probability();
}

# Compute the arithmetic mean of an arrayref
sub mean {
  return sum(@{$_[0]}) / @{$_[0]};
}

# Print a progression message
sub progress {
  my $msg = sprintf $_[0], @_[1 .. $#_];
  print "\r\e[K", $msg;  
}
