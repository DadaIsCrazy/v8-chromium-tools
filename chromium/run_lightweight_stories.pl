#!/usr/bin/perl

=head1

  This file runs all the stories in @stories in parallel. It is very
  simple and just meant to accelerate a bit collection of
  data. Typically, right now it's configured to run all those stories
  with --gc-freelist-strategy=2 --trace-mem-alloc-large and store the
  traces, which will contain some interesting stuffs.

=cut

$SIG{INT} = sub { };

@stories = qw(facebook nytimes cnn twitter youtube maps earth google_india reddit discourse);

for $story (@stories) {
    next unless fork();
    $cmd =  "./xvfb-wrap-safe ./tools/perf/run_benchmark run v8.browsing_desktop --also-run-disabled-tests --browser-executable=./out/Default/chrome --browser=exact --output-format=html --story-filter=$story --show-stdout --pageset-repeat=1 --extra-browser-args='--js-flags=\"--gc-freelist-strategy=2 --trace-mem-alloc-large\"' > traces-large-allocs/$story.txt";
    system $cmd;
    last;
}
