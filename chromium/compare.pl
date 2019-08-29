#!/usr/bin/perl


=head1

   This script compares flags on various Chromium real-world benchmarks.

   It would typically be used in the following way:
      ./compare.pl --out my-output-directory --benchs=facebook,speedometer2

   A few command line flags can customize the behavior, see below.
   The two you should use more than others are:
      --name=<name>: tells this script where to put the results
      --benchs=<comma separated bench list>: sets which benchmarks to run.
         Change the variable %benchs_configs to customize available benchmarks.
      --nb-run=<number>: sets the number of time to run each benchmark
   
   Hopefully however, the only configuration you will have to to is 
   change the content of the variable @opts, in order to chose which
   flags to use, and select which benchmarks to run with --benchs

   Benchmark can be run in parallel, using --thread-benchs (default)
   and --thread-opts flags. See their description in the Flags Section
   below.
   This adds some noise, but also considerably reduces the runtime.

=cut


use strict;
use warnings;
use v5.14;
use autodie qw( open close );
use Cwd;

use Getopt::Long;
use File::Copy;
use File::Path qw( make_path remove_tree );
use threads;

# ---------------------------------------------------------------------- #
#                            FLAGS                                       #
# ---------------------------------------------------------------------- #
my $thread_benchs  = 1; # If true, runs benchmarks in parallel. Eg:
                        #    1- all benchmarks for options XXX
                        #    2- all benchmarks for options YYY
                        #    3- all benchmarks for options XXX
                        #    4- all benchmarks for options YYY
                        # etc.
my $thread_opts    = 0; # If true, runs flags in parallel. Eg:
                        #    1- benchmark A for options XXX and YYY
                        #    2- benchmark B for options XXX and YYY
                        #    3- benchmark A for options XXX and YYY
                        #    4- benchmark B for options XXX and YYY
                        # etc.
my $nb_run         = 40; # How many time to run each bench
my $xvfb           = './xvfb-wrap-safe'; # What xvfb command to invoke
my $runner         = './tools/perf/run_benchmark'; # How to run the benchmarks
my $browser        = getcwd() . '/out/Default/chrome'; # Where Chrome is
my $extra_args     = '--browser=exact --output-format=html --show-stdout --pageset-repeat=1 --also-run-disabled-tests'; # Some additional arguments
my @benchs         = (); # What benchs (eg, facebook, twitter, speedometer, ...) to run
my $js_args_base   = '--predictable-gc-schedule'; # js flags to use for all benchs
my $name           = ''; # Benchmakr's name (will be the name of the output directory)
my $res_dir        = 'tools/perf/results'; # Where to put results (should be relative to current dir) ($name will be added)
my $keep_artifacts = 0; # if true, the keep artifacts (will use a lot of disk space)

# ---------------------------------------------------------------------- #
#                                                                        #
#       Beginner: Just change this line with the flags you want          #
#                                                                        #
# ---------------------------------------------------------------------- #
# -exp
# my @opts = (
#   "--gc-freelist-strategy=0",                  # baseline
#   "--gc-freelist-strategy=6",                  # single page
#   "--gc-freelist-strategy=6 --never-compact",  # single page, no compaction (expectation: fast, memory off the roof)
#   "--gc-freelist-strategy=7",                  # freelist legacy more smalls (expectation: identical as baseline)
#   "--gc-freelist-strategy=8",                  # freelist legacy, ignoring tinys (expectation: identical as baseline)
#   "--gc-freelist-strategy=3",                  # FreeListManyCached, for comparison with 9
#   "--gc-freelist-strategy=9",                  # FreeListLegacySlowPathRetry (expactation: similar memory, lower perf than 14)
#   map {"--gc-freelist-strategy=$_"} 10 .. 24
#   );
# -exp-2
# my @opts = (
#   "--gc-freelist-strategy=0",                  # FreeListLegacy, for comparison just in case
#   "--gc-freelist-strategy=5",                  # FreeListManyCachedOrigin, for comparison just in case
#   "--gc-freelist-strategy=3",                  # FreeListManyCached, for comparison with 9 and 20
#   "--gc-freelist-strategy=9",                  # FreeListLegacySlowPathRetry (expactation: similar memory, lower perf than 14)
#   "--gc-freelist-strategy=20",                 # FreeListManyMoreFastPath, for comparison with 25 (expectation: similar to 9)
#   "--gc-freelist-strategy=25",                 # FreeListManyMoreFastPathNoCache (expectation: slower than 20)
#   "--gc-freelist-strategy=23",                 # FreeListManyMore2kWholeRegion, to compare with 3 and 5.
#   );
# -exp-3
# my @opts = (
#   # To measure memory impact of less categories but precise
#   "--gc-freelist-strategy=2",                    # FreeListMany,          for comparison between 2-31-32
#   "--gc-freelist-strategy=31",                   # FreeListHalfSmallMany           //
#   "--gc-freelist-strategy=32",                   # FreeListHalfMany                //

#   # To measure perf/memory of linear vs exponential large categories
#   "--gc-freelist-strategy=0",                    # FreeListLegacy, for comparison with stuffs
#   "--gc-freelist-strategy=4",                    # FreeListManyCachedFastPath            comparison 0-4-33-34-28
#   "--gc-freelist-strategy=33",                   # FreeListHalfSmallManyCachedFastPath             //
#   "--gc-freelist-strategy=34",                   # FreeListHalfManyCachedFastPath                  //
#   "--gc-freelist-strategy=28",                   # FreeListManyMore2kFastPath                      //

#   # To measure fast path +128 bytes vs fast path +2k
#   "--gc-freelist-strategy=35",                   # FreeListManyCachedFastPath256 for comparison with 4
#   );
# -exp-4
# my @opts = (
#   # to measure benefits of O(1) SelectFreeListCategoryType
#   "--gc-freelist-strategy=10",                   # FreeListManyMore for comparison with 29 and 30
#   "--gc-freelist-strategy=29",                   # FreeListManyMoreLoopSelect (expectation: slower than 10 and 30)
#   "--gc-freelist-strategy=30",                   # FreeListManyMoreLoopSelectLarge (expectation: fast than 30, slower than 10)

#   # to measure stress/no compaction
#   "--gc-freelist-strategy=0",                    # FreeListLegacy, for comparison: [0-never/always] and [0-4-33-34-28]
#   "--gc-freelist-strategy=0 --never-compact",    # FreeListLegacy, to evaluate stress compact
#   "--gc-freelist-strategy=0 --always-compact",   # FreeListLegacy, to evaluate no compact

#   # To measure iterating whole categories vs precise categories
#   "--gc-freelist-strategy=9",                    # FreeListLegacySlowPathRetry (to compare with 26)
#   "--gc-freelist-strategy=26",                   # FreeListLegacyMoreSmallsSlowPath (to compare with 9)
#   "--gc-freelist-strategy=2",                    # FreeListMany
#   );
# -exp-5
my @opts = (
  # to compare FreeList strategies
  "--gc-freelist-strategy=6",             # FreeListFullPages
  "--gc-freelist-strategy=1",             # FreeListFastAlloc
  "--gc-freelist-strategy=0",             # FreeListLegacy
  "--gc-freelist-strategy=7",             # FreeListLegacyMoreSmalls
  "--gc-freelist-strategy=39",            # FreeListHalfManyFastPath
  "--gc-freelist-strategy=38",            # FreeListManyFastPath
  "--gc-freelist-strategy=41",            # FreeListManyMore2kFastPathNoCache
  "--gc-freelist-strategy=40",            # FreeListManyOrigin
  "--gc-freelist-strategy=32",            # FreeListHalfMany
  "--gc-freelist-strategy=2",             # FreeListMany
  "--gc-freelist-strategy=27",            # FreeListManyMore2k
  "--gc-freelist-strategy=10",            # FreeListManyMore(1k)
  );


GetOptions("nb-run=i",       \$nb_run,
           "runner=s",       \$runner,
           "benchs=s",       \@benchs,
           "browser=s",      \$browser,
           "extra-args=s",   \$extra_args,
           "js-args-base",   \$js_args_base,
           "res-dir",        \$res_dir,
           "name=s",         \$name,
           "opts=s",         \@opts,
           "thread-benchs",  \$thread_benchs,
           "thread-opts",    \$thread_opts,
           "keep-artifacts", \$keep_artifacts);
@opts = split(/,/, join(',', @opts), -1);
@benchs = split(/,/, join(',', @benchs), -1);
{ 
  my %unique_benchs;
  for (@benchs) {
    if ($unique_benchs{$_}++) {
      say "Duplicate benchmark $_. Exiting.";
      exit 0;
    }
  }
}

# To make this script supports additional benchmarks, add them here.
my %benchs_configs =
  map { $_ => { benchmark => 'v8.browsing_desktop', story  => $_ } }
      qw(cnn earth facebook maps nytimes twitter_infinite_scroll 
         youtube google_india reddit tumblr_infinite_scroll flipboard discourse);
$benchs_configs{speedometer2} = { benchmark => 'speedometer2' };

# Making sure $name is provided
if (!$name) {
  say "Parameter name is mandatory. Use --name=<string>. Exiting.";
  exit 0;
}
# Making sure $name doesn't contain spaces
if ($name =~ /\s/) {
  say "Please don't use spaces in --name. Exiting.";
  exit 0;
}
# Updating result directory
$res_dir = getcwd() . "/$res_dir/$name";

# Making sure every benchmarks are known
for my $bench (@benchs) {
  if (! exists $benchs_configs{$bench}) {
    say "Unknown benchmark '$bench'. Exiting";
    exit 0;
  }
}
# Making sure result directories don't exist yet
if (-d $res_dir) {
  for my $bench (@benchs) {
    if (-f "$res_dir/$bench.html" ||
        -d "$res_dir/$bench") {
      say "File '$res_dir/$bench.html' or directory '$res_dir/$bench' already exist. " .
        "Remove it/them or use another directory please. Exiting";
      exit 0;
    }
  }
}

# Creating output directory
make_path $res_dir;
my $path = getcwd();


# Actually running the benchmarks
if ($thread_opts) {
  parallelize_on_opts();
} elsif ($thread_benchs) {
  parallelize_on_benchs();
} else {
  sequential();
}



# Parallelization is done on the @benchs rather than on the @opts. A
# reason to do this would be if there are many @opts and not many
# @stories: it avoids running too many benchmark in parallel, that
# would interefer too much between each others.
sub parallelize_on_benchs {
  my $total = @opts * $nb_run;

  # Running the benchmarks
  my $count = 0;
  for my $n (1 .. $nb_run) {
    for my $opt (@opts) {
      my $opt_name =  ($opt // 'none') =~ s/ /_/gr;
      $count++;

      # Remember that benchmarks are actually two parts: first, the
      # benchmark is ran, and then only are the data collected. During
      # the first part, we don't want the user to run anything too
      # CPU-consuming => printing a warning message.
      system "notify-send", "Benchmarking in progress ($count/$total)",
        "Benchmarking starts; go easy on CPU-intensive applications";
      for my $bench (@benchs) {
        chdir $path; # Just because weirds stuffs happen around here
        my $out_dir = "$res_dir/$bench-$opt_name";
        
        my $cmd = build_cmd(
          reset    => $n == 1,
          label    => "$opt_name-$n",
          bench    => $bench,
          js_flags => $opt,
          out_dir  => $out_dir);

        threads->create( sub {
          # A small print; to help getting a sense of the progression
          say getcwd();
          say "$bench/$opt ($n/$nb_run) ", $cmd;
          # Running the benchmark
          system $cmd;
          
          if (! $keep_artifacts) {
            # Deleting the traces, since those takes _a lot_ of disk space.
            remove_tree "$out_dir/artifacts";
          }
       });
      }

      # Waiting for every thread to finish (they probably won't have
      # the same execution time -> we want them to be synchronized on
      # their start in order to make interference more fair between
      # runs/opts).
      $_->join for threads->list;
    }
  }

  # Collecting the results
  for my $bench (@benchs) {
    say "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
    system "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
  }
}


# Parallelization is done on the @opts rather than on the @benchs. A
# reason to do this would be if there are many @stories and not many
# @opts: it avoids running too many benchmark in parallel, that would
# interefer too much between each others.
sub parallelize_on_opts {
  my $total = @benchs * $nb_run;

  # Running the benchmarks
  my $count = 0;
  for my $n (1 .. $nb_run) {
    for my $bench (@benchs) {
      $count++;

      # Remember that benchmarks are actually two parts: first, the
      # benchmark is ran, and then only are the data collected. During
      # the first part, we don't want the user to run anything too
      # CPU-consuming => printing a warning message.
      system "notify-send", "Benchmarking in progress ($count/$total)",
        "Benchmarking starts; go easy on CPU-intensive applications";
      for my $opt (@opts) {
        my $opt_name =  ($opt // 'none') =~ s/ /_/gr;
        chdir $path; # Just because weirds stuffs happen around here
        my $out_dir = "$res_dir/$bench-$opt_name";
        
        my $cmd = build_cmd(
          reset    => $n == 1,
          label    => "$opt_name-$n",
          bench    => $bench,
          js_flags => $opt,
          out_dir  => $out_dir);

        threads->create( sub {
          # A small print; to help getting a sense of the progression
          say "$bench/$opt ($n/$nb_run) ", $cmd;
          # Running the benchmark
          system $cmd;
          
          if (! $keep_artifacts) {
            # Deleting the traces, since those takes _a lot_ of disk space.
            remove_tree "$out_dir/artifacts";
          }
       });
      }

      # Waiting for every thread to finish (they probably won't have
      # the same execution time -> we want them to be synchronized on
      # their start in order to make interference more fair between
      # runs/opts).
      $_->join for threads->list;
    }
  }

  # Collecting the results
  for my $bench (@benchs) {
    say "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
    system "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
  }
}

sub sequential {
  my $total = @opts * $nb_run;

  # Running the benchmarks
  my $count = 0;
  for my $bench (@benchs) {
    for my $n (1 .. $nb_run) {
      for my $opt (@opts) {
        my $opt_name =  $opt // 'none';
        $count++;
        
        system "notify-send", "Benchmarking in progress ($count/$total)",
          "Starting $bench $opt ($n/$nb_run)";

        my $out_dir = "$res_dir/$bench-$opt_name";
        
        my $cmd = build_cmd(
          reset    => $n == 1,
          label    => "$opt_name-$n",
          bench    => $bench,
          js_flags => $opt,
          out_dir  => $out_dir);

        # A small print; to help getting a sense of the progression
        say "$bench/$opt ($n/$nb_run) ", $cmd;
        # Running the benchmark
        system $cmd;
        
        if (! $keep_artifacts) {
          # Deleting the traces, since those takes _a lot_ of disk space.
          remove_tree "$out_dir/artifacts";
        } 
      }
    }
  }

  # Collecting the results
  for my $bench (@benchs) {
    say "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
    system "cat $res_dir/$bench-*/results.html > $res_dir/$bench.html";
  }

}

sub build_cmd {  
  my %args = @_;
  for (qw(reset label js_flags bench out_dir)) {
    die "build_cmd: missing mandatory parameter $_" unless defined $args{$_};
  }

  $args{label} =~ s/ /_/g;

  my $benchmark = $benchs_configs{$args{bench}};
  
  return join " ",
    ($xvfb,    # new X instance
     $runner,  # where to find run_benchmark
     'run',
     $benchmark->{benchmark}, # speedometer2 or v8.browsing_desktop
     $extra_args,
     "--browser-executable=$browser", # chromium path
     "--output-dir=$args{out_dir}", # where to put the results,
     ($benchmark->{story} ? ("--story-filter=$benchmark->{story}") : ()), # which story to run, only if v8.browsing_desktop
     ($args{reset} ? ("--reset-results") : ()), # cleaning results first
     "--results-label='$args{label}'", # label for the results
     "--also-run-disabled-tests", # because maps is disabled
     "--extra-browser-args=\"--js-flags='$js_args_base $args{js_flags}'\"");
}
