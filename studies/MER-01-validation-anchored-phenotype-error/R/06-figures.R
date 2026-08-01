## MER-01: figures for the decisive cells and validation-size result.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
         else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
source(here('R', '00-config.R'))
suppressPackageStartupMessages(library(ggplot2))

OUT <- here('results')
FIG <- here('out')
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
perf <- utils::read.csv(file.path(OUT, 'performance.csv'))
scenarios <- build_scenarios()

pdat <- perf[perf$contrast == 'dynamic' & perf$decisive &
               perf$method %in% c('rich_history', 'exact_filtered',
                                   'oracle_complete'), ]
pdat$method <- factor(pdat$method,
                      levels = c('oracle_complete', 'exact_filtered',
                                 'rich_history'),
                      labels = c('Oracle complete data',
                                 'Exact filtered threshold',
                                 'Rich-history threshold'))
pdat$cell <- paste(pdat$profile, sprintf('accuracy %.2f', pdat$accuracy), sep = ', ')

p1 <- ggplot(pdat, aes(x = bias, y = cell, colour = method)) +
  geom_vline(xintercept = c(-0.01, 0.01), colour = 'grey70', linetype = 2) +
  geom_errorbarh(aes(xmin = bias_lo, xmax = bias_hi),
                 height = 0.18, position = position_dodge(width = 0.55)) +
  geom_point(position = position_dodge(width = 0.55), size = 1.8) +
  labs(x = 'Bias in the dynamic-strategy risk difference', y = NULL,
       colour = NULL,
       title = 'Longitudinal phenotype error after propensity approximation is removed',
       subtitle = 'Intervals use the prespecified simultaneous Monte Carlo procedure.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig1-decisive-bias.png'), p1,
       width = 10, height = 6.5, dpi = 200)

p2 <- ggplot(pdat, aes(x = coverage, y = cell, colour = method)) +
  geom_rect(aes(xmin = 0.925, xmax = 0.975, ymin = -Inf, ymax = Inf),
            inherit.aes = FALSE, fill = 'grey90') +
  geom_errorbarh(aes(xmin = coverage_lo, xmax = coverage_hi),
                 height = 0.18, position = position_dodge(width = 0.55)) +
  geom_point(position = position_dodge(width = 0.55), size = 1.8) +
  geom_vline(xintercept = 0.90, linetype = 2) +
  scale_x_continuous(limits = c(0, 1)) +
  labs(x = 'Nominal 95% interval coverage', y = NULL, colour = NULL,
       title = 'Coverage in the eight decisive nonaligned cells',
       subtitle = 'The grey region is the prespecified 0.925 to 0.975 validity band.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-decisive-coverage.png'), p2,
       width = 10, height = 6.5, dpi = 200)

vfile <- file.path(OUT, 'validation-size.csv')
if (file.exists(vfile)) {
  val <- utils::read.csv(vfile)
  val <- val[!is.na(val$benchmark), ]
  val$benchmark <- factor(val$benchmark, levels = c('nd70', 'un85'),
                          labels = c('Nondifferential, accuracy 0.70',
                                     'Unrelated differential, accuracy 0.85'))
  p3 <- ggplot(val, aes(x = validation_n, y = bias_gain,
                        colour = specification, group = specification)) +
    geom_hline(yintercept = 0, colour = 'grey60') +
    geom_errorbar(aes(ymin = bias_gain_lo, ymax = bias_gain_hi), width = 25) +
    geom_line(linewidth = 0.55) + geom_point(size = 1.6) +
    facet_wrap(~ benchmark) +
    scale_x_continuous(breaks = c(100, 250, 500, 1000)) +
    labs(x = 'Internal validation sample size',
         y = '|corrected bias| minus 0.5 |rich-history bias|',
         colour = 'Correction model',
         title = 'When is validation-anchored correction worth its variance cost?',
         subtitle = 'Qualification requires the entire interval below zero plus all other gates.') +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
  ggsave(file.path(FIG, 'fig3-validation-size.png'), p3,
         width = 10, height = 6, dpi = 200)
}
message('figures written to ', FIG)
