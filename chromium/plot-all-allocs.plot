# Print a (not so) nice graph of allocation sizes.
# (see the file all-allocs.dat to see what the data looks like)
# all-allocs.dat should be generate by runinng benchmarks with the js
# flags --trace-mem-allocs or something like that (that is, in each
# call to PagedSpace::AllocateRaw, print the size of the allocation if
# identity() == OLD_SPACE)

set terminal png size 1280,600
set output 'all-allocs.png'
set border 3
set tics nomirror

set grid ytics

set xtics out
set ytics out

set logscale x 10
set logscale y 10

unset key

set yrange [10:]

set ylabel "Count"
set xlabel "Size (bytes)"

set title 'Allocations per size (CNN, Facebook, Gmail, Speedometer2, Twitter)'

plot 'all-allocs.dat' using 1:2 w p pt 1 lc rgb "red"
