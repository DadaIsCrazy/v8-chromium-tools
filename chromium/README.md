
Each scripts start with a small description of what it does, how to use it, and how to configure/customize it. You should ignore `.pm` files, which are modules, and should be hard to understand for non-perl non-V8 developpers.


The most useful scripts in this directory are:

  - `compare.pl`: runs a bunch of stories (in parallel or not) with different flags to compare flags.
  
  - `summarize_results.pl`: nicely format and outputs comparison of flags based on traces produced by `compare.pl`.
  
Note that those two scripts need the following scripts/modules to run:

  - `parse_res.pl`: parses HTML traces of chromium benchmarks
  
  - `Analyze.pm`: compares flags and nicely outputs the said comparison
  
  - `xvfb-wrap-safe`: a wrapper around `xvfb-run` used by `compare.pl`
  

Typically, to compare two flags, say "--gc-trace-freelists=0" and "--gc-trace-freelists=2", you will do:

  1- edit `compare.pl`: set its variable `@opts` to `("--gc-trace-freelists=0", "--gc-trace-freelists=2")`
  
  2- run `compare.pl`:

```
./compare.pl --benchs=facebook,speedometer2,nytimes,reddit --name=my-benchmark
```
    This will put the traces in the folder `tools/perf/results/my-benchmark`.
  
  3- run `summarize_results.pl`:

```
./summarize_results.pl --dir tools/perf/results/my-benchmark
```
    This will parse the results, and nicely print them in your terminal


You probably shouldn't need to configure `compare.pl` to much (the `--nb-run=<number>` flag could be useful though, in order to chose how many times to repeat the benchmark).  
`summarize_results.pl`'s options could be more useful though; see the documentation at its top.


---
  
  
Also, two other scripts, less useful, are included "just in case":

  - `run_lightweight_stories.pl`: runs a bunch of stories in parallel (useful for simple trace generation)
  
  - `plot-all-allocs.plot`: a gnuplot script to generate a plot of all allocations based on `all-allocs.dat`
