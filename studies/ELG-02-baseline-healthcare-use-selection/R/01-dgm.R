## Study ELG-02: data-generating mechanism.
##
## All eligibility causes precede time zero. The collider cells instantiate
## A <- P -> H <- D -> Y. No claim is made about post-treatment eligibility.

get_scenario_value <- function(scen, name) {
  unname(scen[[name]][1])
}

gen_sample <- function(scen, n) {
  B <- stats::rbinom(n, 1L, 0.5)
  X <- stats::rnorm(n)
  P <- stats::rnorm(n)
  D <- stats::rnorm(n)
  noise <- matrix(stats::rnorm(n * length(NOISE_VARS)), nrow = n)
  colnames(noise) <- NOISE_VARS

  V_H <- stats::runif(n)
  V_A <- stats::runif(n)
  V_Y <- stats::runif(n)

  lp_h <- get_scenario_value(scen, "alpha_h") + 0.30 * B + 0.20 * X +
    get_scenario_value(scen, "lambda_p") * P +
    get_scenario_value(scen, "lambda_d") * D
  H <- as.integer(V_H < stats::pnorm(lp_h))

  lp_a <- -0.05 + 0.35 * B - 0.25 * X + 0.55 * P
  A <- as.integer(V_A < stats::pnorm(lp_a))

  z <- -1.50 + 0.45 * B + 0.35 * X + 0.65 * D
  delta <- -0.35 + 0.25 * B
  p0 <- stats::pnorm(z)
  p1 <- stats::pnorm(z + delta)
  Y <- as.integer(V_Y < ifelse(A == 1L, p1, p0))

  out <- data.frame(
    B = B, X = X, P = P, D = D, H = H, A = A, Y = Y,
    stringsAsFactors = FALSE
  )
  cbind(out, as.data.frame(noise, check.names = FALSE))
}

gen_replicate_pair <- function(scen) {
  ## The audit decision is based on an independent sample. The analysis sample
  ## is generated separately from the same superpopulation.
  list(
    audit = gen_sample(scen, N_AUDIT),
    analysis = gen_sample(scen, N_ANALYSIS)
  )
}
