#!/usr/bin/perl

=head1

   This script compares flags on Octane 2.1.

   It would typically be used in the following way:
      ./compare-octane.pl --out my-output-directory --run-benchs

   A few command line flags can customize the behavior, see below.
   The two you should use more than others are:
      --out <out_dir>: tells this script where to put the results
      --run-benchs: tells this script to run the benchmarks and not 
                    only show results of a previous run.
   
   Hopefully however, the only configuration you will have to to is 
   change the content of the variable @opts, in order to chose which
   flags to use.

   To adapt this to another benchmark than Octane, see comments around
   line 130.

=cut


use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Getopt::Long;
use List::Util qw( max sum product );
use File::Path qw( make_path );
use File::Copy qw( copy );
use Cwd;

use FindBin;
use lib $FindBin::Bin;
use Analyze;


# ---------------------------------------------------------------------- #
#                            FLAGS                                       #
# ---------------------------------------------------------------------- #
# Boolean flag can be preceded with 'no' to negate them.
my $nb_run = 40;          # How many executions to run
my $d8     = './d8';      # Where to find d8
my $runner = 'run.js';    # What script to run
my $cp_d8  = 1;           # If true, the cp d8 from ../../../../out/x64.release
my $ref;                  # Flag to use as reference
my $out_dir;              # Where to put the results
my $run_benchs = 0;       # If true, the run the benchmarks; otherwise, just show results
my $js_flags = "";        # Additional js flags to use for all benchnarks

# ---------------------------------------------------------------------- #
#                                                                        #
#       Beginner: Just change this line with the flags you want          #
#                                                                        #
# ---------------------------------------------------------------------- #
my @opts = map { "--gc-freelist-strategy=$_" } 0, 3, 4, 5, 7, 8, 9;


GetOptions("nb-run=i",   \$nb_run,
           "d8=s",       \$d8,
           "cp-d8",      \$cp_d8,
           "runner=s",   \$runner,
           "out=s",      \$out_dir,
           "js_flags=s", \$js_flags,
           "ref=s",      \$ref,
           "run-benchs", \$run_benchs,
           "opts=s",     \@opts);
@opts = split(/,/, join(',', @opts), -1);


# Preparing out directory
if (! $out_dir) {
  die "Output director not specified. --out flag is mandatory. Exiting."
}
chdir $FindBin::Bin;
make_path $out_dir;
make_path "$out_dir";

# Copy d8 executable
if ($cp_d8) {
  copy $_, "." for glob "../../../../out/x64.release/{d8,natives_blob.bin,snapshot_blob.bin}";
  $d8 = './d8';
  $ENV{D8_PATH} = getcwd();
} else {
  $ENV{D8_PATH} = dirname $d8;
}

# Setting up $ref if needed
$ref //= $opts[0];


# ------------------------------------------------------------------ #
#  Main processing

if ($run_benchs) {
  run_benchmarks();
}
my $data = collect_data();
Analyze::process_data($data, $ref);



sub run_benchmarks {
  for my $n (1 .. $nb_run) {
    for my $opt (@opts) {
      my $opt_name = ($opt || 'none') =~ s/ /_/gr;
      progress("Running benchmarks... opt:$opt_name ($n/$nb_run)");
      
      my $cmd = "$d8 $runner --predictable-gc-schedule --trace-gc $opt -- --predictable > $out_dir/$opt_name-$n.txt";
      system $cmd;
    }
  }
  progress("Running benchmarks... done\n");
}

sub collect_data {
  my %data;
  for my $file (glob("$out_dir/*.txt")) {
    my ($opt_name, $n) = $file =~ m{/(.+)-(\d+)\.txt};
    progress("Collecting traces... opt:$opt_name ($n/$nb_run)");

    my $trace = do {
      local $/;
      open my $FH, '<', $file;
      <$FH>;
    };

    
    # Computing perf
    # ---------------------------------------------------------------------- #
    #                                                                        #
    #  Just change the following line to make this script work on another    #
    #   benchmark than Octane                                                #
    #                                                                        #
    # ---------------------------------------------------------------------- #
    my $time = sum ($trace =~ /\(Score\):\s*(\d+)/g);
    # JetStream: my $time = sum ($trace =~ /^\S+:\s*(\d+(?:\.\d+)?)\b/gm);
    # Web tooling: my ($time) = /Geometric mean:\s*(\d+(?:\.\d+)?)/;
    push @{$data{$opt_name}->{score}->{'Octane2.1'}->{values}}, $time;
    $data{$opt_name}->{score}->{'Octane2.1'}->{higher_is_better} = 1;

    # Computing memory
    my @memory = $trace =~ /Scavenge \S+ \((\S+)\)/g;
    my $max_mem = max @memory;
    push @{$data{$opt_name}->{'memory (max)'}->{'Octane2.1'}->{values}}, $max_mem;
    my $avg_mem = mean(\@memory);
    push @{$data{$opt_name}->{'memory (avg)'}->{'Octane2.1'}->{values}}, $avg_mem;
  }
  progress("Collecting traces... done\n");
  return \%data;
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
