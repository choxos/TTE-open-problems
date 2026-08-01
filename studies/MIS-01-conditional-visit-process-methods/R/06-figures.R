## Study MIS-01: figures for confirmatory and descriptive results.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub('^--file=', '', .f[1])))) else normalizePath('.')
here <- function(...) file.path(STUDY, ...)
suppressPackageStartupMessages(library(ggplot2))
source(here('R', '00-config.R'))

OUT <- here('results')
FIG <- here('out')
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
perf <- utils::read.csv(file.path(OUT, 'performance.csv'))
gates <- utils::read.csv(file.path(OUT, 'decision-gates.csv'))
pairs <- utils::read.csv(file.path(OUT, 'matched-pairs.csv'))
diag <- utils::read.csv(file.path(OUT, 'diagnostics.csv'))

core <- perf[perf$panel == 'confirmatory' & perf$estimand == 'rd24' &
             perf$variant == 'compatible', ]
core$frequency <- factor(core$obs_target, levels = c(0.30, 0.08),
                         labels = c('30% observed', '8% observed'))
core$informativeness <- factor(core$gamma_L, levels = c(0, 1.386294),
                               labels = c('gamma L = 0', 'gamma L = log(4)'))

p1 <- ggplot(core, aes(x = method, y = bias, color = informativeness)) +
  geom_hline(yintercept = c(-0.02, 0, 0.02),
             linetype = c('dotted', 'solid', 'dotted'), color = 'grey55') +
  geom_boxplot(outlier.size = 0.7, position = position_dodge(width = 0.75)) +
  facet_wrap(~ frequency) +
  coord_flip() +
  labs(x = NULL, y = 'Bias in the 24-month risk difference',
       color = 'Observation dependence',
       title = 'Bias across the confirmatory factorial',
       subtitle = 'Panels hold marginal observation frequency fixed by mechanism calibration.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig1-confirmatory-bias.png'), p1,
       width = 10, height = 7, dpi = 200)

p2 <- ggplot(core, aes(x = convergence, y = coverage, color = method)) +
  geom_vline(xintercept = c(0.95, 0.99), linetype = 'dotted') +
  geom_hline(yintercept = c(0.90, 0.925, 0.975), linetype = 'dotted') +
  geom_point(alpha = 0.65, size = 1.5) +
  facet_grid(frequency ~ informativeness) +
  coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
  labs(x = 'Convergence probability',
       y = 'Conditional 95% interval coverage',
       color = 'Method', title = 'The two co-primary performance measures') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-coverage-convergence.png'), p2,
       width = 11, height = 8, dpi = 200)

locf_pairs <- pairs[pairs$method == 'locf', ]
p3 <- ggplot(locf_pairs, aes(x = change_abs_bias, y = reorder(profile_id, change_abs_bias))) +
  geom_vline(xintercept = c(0, 0.01), linetype = c('solid', 'dotted'), color = 'grey50') +
  geom_errorbarh(aes(xmin = change_low, xmax = change_high), height = 0.15) +
  geom_point(size = 1.4) +
  facet_grid(obs_target ~ gamma_A, labeller = label_both) +
  labs(x = 'Informative minus noninformative absolute bias', y = 'Latent-role profile',
       title = 'Matched LOCF deterioration under common random numbers',
       subtitle = 'Intervals use the sign-aware delta method or conservative projection near zero.') +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, 'fig3-locf-matched-change.png'), p3,
       width = 11, height = 9, dpi = 200)

wd <- diag[diag$method %in% c('iiw_raw', 'iiw_capped', 'iiw_calibrated'), ]
p4 <- ggplot(wd, aes(x = weight_ess_fraction, y = weight_cv, color = method)) +
  geom_point(alpha = 0.65) +
  scale_y_continuous(trans = 'log1p') +
  labs(x = 'Effective sample-size fraction', y = 'Visit-weight coefficient of variation',
       color = 'Method', title = 'Visit-weight dispersion') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig4-weight-dispersion.png'), p4,
       width = 8, height = 6, dpi = 200)

message('figures written to ', FIG)
