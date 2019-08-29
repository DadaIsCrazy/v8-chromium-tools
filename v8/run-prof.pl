#!/usr/bin/perl


=head1

   This script run the profiler on Octane with different flags to
   compare. It then prints the significant differences between the
   two.

   It would typically be used in the following way:
      ./run-prof.pl --out my-output-directory --run-benchs

   A few command line flags can customize the behavior, see below.
   The two you should use more than others are:
      --out <out_dir>: tells this script where to put the results
      --run-benchs: tells this script to run the benchmarks and not 
                    only show results of a previous run.
   
   Hopefully however, the only configuration you will have to to is 
   change the content of the variable @opts, in order to chose which
   flags to use.

   To adapt this to another benchmark than Octane, change the value of
   the variable |$runner|.

=cut


use strict;
use warnings;
use v5.14;
use autodie qw( open close );

use Data::Printer;
use Data::Printer;
use Getopt::Long;
use List::Util qw( sum product );
use File::Path qw( make_path );
use Cwd;
use FindBin;
use File::Copy;
use File::Spec;
use File::Basename;
use Term::ANSIColor;
use Statistics::Test::WilcoxonRankSum;
use Sort::Key::Natural qw( rnatsort rnatkeysort natsort natkeysort );
$| = 1;

# ---------------------------------------------------------------------- #
#                            FLAGS                                       #
# ---------------------------------------------------------------------- #
my $nb_run = 20;            # How many executions to run
my $d8     = './d8';        # Where to find d8
my $runner = 'run.js';      # What script to run
my $out_dir;                # Where to store the results
my $cp_d8 = 1;              # if true, the cp d8 from ../../../../out/x64.release
my $ref;                    # Flag to use as reference
my $run_benchs;             # If true, the run the benchmarks; otherwise, just show results 
my $min_ticks = 1.1;        # Don't consider numbers smaller than this
my $pattern = "";           # Only consider functions that match this pattern

# ---------------------------------------------------------------------- #
#                                                                        #
#       Beginner: Just change this line with the flags you want          #
#                                                                        #
# ---------------------------------------------------------------------- #
my @opts = map { "--gc-freelist-strategy=$_" } 0,19;

GetOptions("nb-run=i",    \$nb_run,
           "d8=s",        \$d8,
           "cp-d8",       \$cp_d8,
           "runner=s",    \$runner,
           "opts=s",      \@opts,
           "out=s",       \$out_dir,
           "ref=s",       \$ref,
           "run-benchs",  \$run_benchs,
           "min-ticks=i", \$min_ticks,
           "pattern=s",   \$pattern
  );
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

# Setting reference opt if needed
$ref //= ($opts[0] || 'none');


# Collecting traces
if ($run_benchs) {
  for my $n (1 .. $nb_run) {
    for my $opt (@opts) {
      my $opt_name = $opt || 'none';
      progress("Collecting traces..... %2d/%-2d ($opt_name)", $n, $nb_run);

      chdir $FindBin::Bin;
      my $cmd = "$d8 $runner --prof --predictable-gc-schedule $opt -- --predictable";
      my $res = `$cmd`;

      system "../../../../tools/linux-tick-processor v8.log > '$out_dir/$opt_name-$n.perf'";
      move "v8.log", "$out_dir/logs/$opt_name-$n.log";
    }
  }
  progress("Collecting traces..... done.\n");
}

# Parsing traces
my %traces;
for my $n (1 .. $nb_run) {
  for my $opt (@opts) {
    my $opt_name = $opt || 'none';
    progress("Parsing traces..... %2d/%d ($opt_name)", $n, $nb_run);

    my $file = "$out_dir/$opt_name-$n.perf";

    open my $FH, '<', $file;
    while (<$FH>) {
      if (/^ \s* (\d+) \s* (\d+(?:\.\d+)?)% \s* (\d+(?:\.\d+)?)% \s* (.*) \s* $/x) {
        my ($ticks, $total, $nonlib, $fun) = ($1, $2, $3, $4);
        next unless $fun =~ /$pattern/;
        push @{$traces{$opt_name}->{$fun}->{ticks}},  $ticks;
        push @{$traces{$opt_name}->{$fun}->{total}},  $total,
        push @{$traces{$opt_name}->{$fun}->{nonlib}}, $nonlib;
      }
    }
  }
}
progress("Parsing traces..... done.\n");

# Computing means, padding with 0s if needed
{
  my $opt_cnt = 0;
  for my $opt_name (@opts) {
    my $fun_total = keys %{$traces{$opt_name}};
    my $fun_cnt = 0;
    for my $fun (keys %{$traces{$opt_name}}) {
      progress("Cleaning traces..... %2d/%d ($opt_name)... %3d/%d", $opt_cnt, scalar @opts, ++$fun_cnt, $fun_total);

      # Padding with 0s if needed
      for (qw(ticks total nonlib)) {
        push @{$traces{$opt_name}->{$fun}->{$_}}, 0
          while @{$traces{$opt_name}->{$fun}->{$_}} < $nb_run;
      }

      # Computing means
      $traces{$opt_name}->{$fun}->{means}->{ticks}  = mean($traces{$opt_name}->{$fun}->{ticks});
      $traces{$opt_name}->{$fun}->{means}->{total}  = mean($traces{$opt_name}->{$fun}->{total});
      $traces{$opt_name}->{$fun}->{means}->{nonlib} = mean($traces{$opt_name}->{$fun}->{nonlib});
    }
  }
  progress("Cleaning traces..... done.\n");
}

# Analyzing traces
my %ref_funs = map { $_ => 1 } grep { $traces{$ref}->{$_}->{means}->{ticks} >= $min_ticks } keys %{$traces{$ref}};
my %diff;
my $opt_cnt = 0;
for my $opt (@opts) {
  ++$opt_cnt;
  my $opt_name = $opt || 'none';

  my $fun_total = keys %{$traces{$opt_name}};
  my $fun_cnt = 0;
  for my $fun (keys %{$traces{$opt_name}}) {
    progress("Analyzing traces..... %2d/%d ($opt_name)... %3d/%d", $opt_cnt, scalar @opts, ++$fun_cnt, $fun_total);
    next unless $traces{$opt_name}->{$fun}->{means}->{ticks} >= $min_ticks;
    if (! exists $traces{$ref}->{$fun}) {
      # Function is here but not in reference traces
      $diff{$opt_name}->{$fun} = { why => 'not_in_ref',
                                   mean => $traces{$opt_name}->{$fun}->{means}->{ticks} };
    } else {
      # Function is both here and in reference traces
      my $proba = wilcoxon($traces{$opt_name}->{$fun}->{ticks},
                           $traces{$ref}->{$fun}->{ticks});
      if ($proba < 0.05) {
        # Significantly different
        my $diff = $traces{$ref}->{$fun}->{means}->{ticks} / $traces{$opt_name}->{$fun}->{means}->{ticks};
        $diff{$opt_name}->{$fun} = { why  => 'p_significant',
                                     mean => $traces{$opt_name}->{$fun}->{means}->{ticks},
                                     diff => $diff };
      }
    }
  }

  # Checking for functions from reference that aren't in current option.
  for my $fun (keys %ref_funs) {
    next if exists $traces{$opt_name}->{$fun};
    $diff{$opt_name}->{$fun} = { why => 'not_in_current' };
  }
}
progress("Analyzing traces..... done.\n");

# Outputting 
for my $opt (natsort keys %diff) {
  say "\n\n@@@@@@@@@@@@@@@@@@@@@@@@@ $opt @@@@@@@@@@@@@@@@@@@@@@@@@\n\n";

  
  say "--- Not in current ---";
  for (rnatkeysort { $traces{$ref}->{$_}->{means}->{ticks} }
       grep { $diff{$opt}->{$_}->{why} eq 'not_in_current'} keys %{$diff{$opt}}) {
    printf "%3.2f      $_\n", $traces{$ref}->{$_}->{means}->{ticks};
  }
  
  say "--- Not in ref ---";
  for (rnatkeysort { $diff{$opt}->{$_}->{mean} }
       grep { $diff{$opt}->{$_}->{why} eq 'not_in_ref'} keys %{$diff{$opt}}) {
    printf "%3.2f      $_\n", $diff{$opt}->{$_}->{mean};
  }
  
  say "--- p_significant ---";
  for (rnatkeysort { $diff{$opt}->{$_}->{mean} }
       grep { $diff{$opt}->{$_}->{why} eq 'p_significant'} keys %{$diff{$opt}}) {
    printf "%3.2f     x%.2f     $_ \n", $diff{$opt}->{$_}->{mean}, $diff{$opt}->{$_}->{diff};
  }
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
