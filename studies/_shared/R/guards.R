## Runtime guards for defects that fail silently.
##
## `ifelse(test, yes, no)` returns a value shaped like `test`. With a scalar test
## and vector branches it returns `yes[1]` or `no[1]` alone, which then recycles.
## PRO-04 wrote `ifelse(y == 1L, p_y, 1 - p_y)` inside `for (y in 0:1)`, so every
## state carried the outcome probability of the first quadrature node and its
## power calculation ran on the wrong population without raising anything.
## A scalar test with vector branches is never what was meant, so it is an error.
ifelse <- function(test, yes, no) {
  if (length(test) == 1L && (length(yes) > 1L || length(no) > 1L)) {
    stop("ifelse() with a scalar test and vector branches returns one element; ",
         "use if (test) yes else no", call. = FALSE)
  }
  base::ifelse(test, yes, no)
}
