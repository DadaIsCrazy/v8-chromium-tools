
Each scripts start with a small description of what it does, how to use it, and how to configure/customize it. You should ignore `.pm` files, which are modules, and should be hard to understand for non-perl non-V8 developpers.


Bried overview of the scripts in this folder:

  - `compare_octane.pl`: compare various flags on Octane, and prints performances/memory consumption.
  
  - `compare_freelists_usage.pl`: takes traces produce by `d8 --trace-gc-freelists` and nicely formats them for an easy visual inspection/comparison.
  
  - `run-prof.pl`: runs d8's profiler on various flags on a benchmark (Octane for instance), and compares the traces obtained.
  
  - `analyze_freelists.pl`: takes a trace produce by `d8 --trace-gc-freelists` and formats it for a easier visual inspection. (more detailed than `compare_freelists_usage.pl`, but only takes a single trace and doesn't do comparison)
