#!/usr/bin/perl


=head1

   This script parses an HTML execution trace of a Chromium benchmark,
   and prints some metrics (averages and standart deviation; + details
   of all numbers with --details flag) found in this trace.

   To customize what metrics to show, change the variable %metrics.

   Usage example:
      ./parse_res.pl --file <filename.html>

   Note that you might not need to use this script by hand:
   summarize_results.pl implicitely calls it and is more powerful to
   compare multiple benchmarks.

=cut

use strict;
use warnings;
use v5.14;
use autodie qw( open close );
use Cwd;

use Getopt::Long;
use Data::Printer;
use List::Util qw( max sum product );
use File::Copy;
use File::Path qw( make_path );
use JSON::XS;
use Statistics::Test::WilcoxonRankSum;

sub avg { return sum(@_)/@_ }

# return average with standard deviation
sub avg_stdev {
  my $u = sum(@_)/@_; # mean
  my $s = ( sum( map {($_-$u)**2} @_ ) / @_ ) ** 0.5; # standard deviation
  return ($u, $s)
}

# ---------------------------------------------------------------------- #
#                                                                        #
#       Beginner: Just change this variable with the metrics you want    #
#                                                                        #
# ---------------------------------------------------------------------- #
# Available metrics: avg, max, count, total
my %metrics = (
  'Total' => {
    name    => 'total',
    metrics => [ 'avg' ]
  },
  'V8 C++:duration' => {
    name    => 'C++:duration',
    metrics => [ 'avg' ]
  },
  'JavaScript:duration' => {
    name    => 'JS:duration',
    metrics => [ 'avg' ]
  },
  'memory:chrome:renderer_processes:reported_by_chrome:v8:heap:old_space:effective_size' => {
    name    => 'old_space:effective_size',
    metrics => [ 'max' ]
  },
  'GC-slow-path-allocate:duration' => {
    name    => 'slow-path-allocate',
    metrics => [ 'avg' ]    
  },

  'v8-gc-latency-mark-compactor-evacuate' => {
    name    => 'v8-gc-evacuate',
    metrics => [ 'avg', 'max' ]
  },
  'v8-gc-total' => {
    name    => 'v8-gc-total',
    metrics => [ 'avg' ]
  },
  'v8-gc-scavenger' => {
    name    => 'v8-gc-scavenger',
    metrics => [ 'avg' ]
  },
  );

# Add handlers here to add more metrics
my %compute_metric = (
  total => \&compute_total,
  max   => \&compute_max,
  avg   => \&compute_avg,
  count => \&compute_count
  );
# Those handlers return all the data needed to compute a metric.
# For instance, get_data_max returns only the max of each dataset,
# while get_data_avg returns all data.
my %get_type_data = (
  total => \&get_data_total,
  max   => \&get_data_max,
  avg   => \&get_data_avg,
  count => \&get_data_count
  );

my ($filename, $details, @show);
my @show_types;
  
# ---------------------------------------------------------------------- #
#                            FLAGS                                       #
# ---------------------------------------------------------------------- #
GetOptions("file=s",       \$filename,   # Input filename
           "show=s",       \@show,       # What metrics to show (leave empty when in doubt)
           "show-types=s", \@show_types, # I don't remember what this dose
           "details",      \$details);   # If true, print all numbers, not just averages.
@show = split(/,/, join(',', @show), -1);
my %show = map { $_ => 1 } @show;
@show_types = split(/,/, join(',', @show_types), -1);

unless ($filename) {
  say "Parameter --file=<string> is mandatory. Exiting.";
  exit 0;
}

my $data = parse_file($filename);

if (@show) {
  @show_types = ('avg') unless @show_types;
  for my $metric (@show) {
    my $padding = compute_padding(keys %{$data->{$metric}});
    
    for my $type (@show_types) {
      say "$metric ($type)";
      
      for my $expe (sort keys %{$data->{$metric}}) {
        printf "%*s:", $padding, $expe;
        my @data = $get_type_data{$type}->(@{$data->{$metric}->{$expe}});
        if (ref $data[0]) {
          say '';
          for my $dataset (@data) {
            printf "%s  [%s]\n", " "x$padding, join ", ", map { sprintf "%.3f", $_ } @$dataset;
          }
        } else {
          printf " [%s]\n", join ", ", map { sprintf "%.3f", $_ } @data;
        }
      }
      say '';
    }
  }
} else {
  print_data($data);
}



# Gets raw data from a file.
sub parse_file {
  my $filename = shift;
  open my $FP, '<', $filename;
  
  my (%data, $current, $current_n);
  while (<$FP>) {
    my $guard = /<div id="histogram-json-data" style="display:none;">/ ... m|--!></div>|;
    next if !$guard || $guard =~ /(^1|E0)$/;

    # Note that the regex is a bit complicated because there was a
    # change in the HTML file's formating recently, and the regex must
    # support both old and new traces.
    
    # Checking if the line contains the benchmark name
    # Use that line for older benchmarks
    # if (/file.*(?:(?:cnn|facebook|nytimes|twitter|youtube)(?:_\d{4})?|[Ss]peedometer2?|earth|maps)[_-]([^\/\s]+?)[ -]?(\d+)?(?:_\d{4}-\d{2}-\d{2}|\/[Aa]rtifact)/) {
    if (/file.*(?:(?:cnn|facebook|nytimes|twitter(?:_infinite_scroll)?|youtube|google_india|reddit|tumblr_infinite_scroll|flipboard|discourse)(?:_\d{4})?|[Ss]peedometer2?|earth|maps)[_-]([^\/\s]+?)[ -]?(?:\d+_\d{4}-\d{2}-\d{2}|\/[Aa]rtifact)/) {
      $current = $1;
      $current_n = $2;
      next;
    }
    next unless $current;
    
    my $line = JSON::XS->new->utf8->allow_nonref->decode($_);
    my $label = $line->{name} || next;
    next unless exists $metrics{$label} || exists $show{$label};

    my $values = $line->{sampleValues};
    push @{$data{$label}->{$current}}, $values;
  }

  return \%data;
}

# Compute and print interesting metrics from raw data
sub print_data {
  my $data = shift;

  for my $metric (sort keys %metrics) {
    for my $type (@{$metrics{$metric}->{metrics}}) {
      say "$metrics{$metric}->{name} ($type)";

      if (0) {
        my $wilcox_test = Statistics::Test::WilcoxonRankSum->new();

        my ($e1, $e2) = sort keys %{$data->{$metric}};
        $wilcox_test->load_data([get_data_total(@{$data->{$metric}->{$e1}})],
                                [get_data_total(@{$data->{$metric}->{$e2}})]);
        my $p = $wilcox_test->probability();
        
      } else {
        my $padding = compute_padding(keys %{$data->{$metric}});
        for my $expe (sort keys %{$data->{$metric}}) {
          my @vals = $compute_metric{$type}->(@{$data->{$metric}->{$expe}});
          my $all_data = $details ? sprintf "[%s]", join ",", $get_type_data{$type}->(@{$data->{$metric}->{$expe}}) : "";
          if (@vals == 3) {
            printf "%*s: %.4f%s +-%.4f %s\n", $padding, $expe, @vals, $all_data
          } elsif (@vals == 2) {
            printf "%*s: %.4f%s %s\n", $padding, $expe, @vals, $all_data
          } elsif (@vals == 1) {
            printf "%*s: %.4f %s\n", $padding, $expe, @vals, $all_data          
          } else {
            die "Error."
          }
        }
      }
      say '';
    }
  }
}

sub compute_total {
  return compute_avg(map {[ sum @$_ ]} @_)
}
sub compute_avg {
  my ($u, $s) = avg_stdev(map { @$_ } @_);
  ($u, my $order) = format_unit($u);
  return ($u, order_to_str($order), $s/$order);
}
sub compute_max {
  return compute_avg(map { [ max @$_ ] } @_ )
}
sub compute_count {
  return compute_avg(map {[ scalar @$_ ]} @_)
}




sub get_data_total {
  return map { sum @$_ } @_
}
sub get_data_avg {
  return map { @$_ } @_
}
sub get_data_max {
  return map { max @$_ } @_
}
sub get_data_count {
  return map { scalar @$_ } @_
}

sub compute_padding {
  return max map length, @_;
}

sub format_unit {
  my $v = shift;
  my @orders = (1_000_000_000, 1_000_000, 1_000);
  for my $order (@orders) {
    if ($v > $order) {
      return ($v/$order, $order);
    }
  }
  return ($v, 1)
}

sub order_to_str {
  my $order = shift;
  my %convert = (1_000_000_000 => 'G', 1_000_000 => 'M', 1_000 => 'K', 1 => '');
  return $convert{$order}  
}
