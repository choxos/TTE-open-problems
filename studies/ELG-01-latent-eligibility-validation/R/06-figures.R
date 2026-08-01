## ELG-01: figures.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
OUT <- here('results')
FIG <- here('out')
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

truth <- utils::read.csv(file.path(OUT, 'truth.csv'), stringsAsFactors = FALSE)
perf <- utils::read.csv(file.path(OUT, 'performance.csv'), stringsAsFactors = FALSE)
bounds <- utils::read.csv(file.path(OUT, 'bounds-performance.csv'),
                          stringsAsFactors = FALSE)
decision <- utils::read.csv(file.path(OUT, 'decision.csv'), stringsAsFactors = FALSE)

truth_plot <- truth[truth$validation_n == 100L, ]
truth_plot$effect_label <- ifelse(
  truth_plot$effect == 'homogeneous', 'Homogeneous treatment effect',
  'Comorbidity effect modification'
)
truth_plot$kappa_label <- paste0('kappa = ', format(truth_plot$kappa))
truth_plot$m_label <- paste0('Unrecorded eligibility = ',
                             scales::percent(truth_plot$m, accuracy = 1))

p1 <- ggplot(truth_plot,
             aes(x = lambda, y = rd_e, color = kappa_label,
                 group = kappa_label)) +
  geom_hline(yintercept = -0.06, color = 'grey75', linewidth = 0.4) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.8) +
  facet_grid(effect_label ~ m_label) +
  scale_x_continuous(breaks = c(0, log(2), log(4)),
                     labels = c('0', 'log(2)', 'log(4)')) +
  labs(
    x = 'Latent eligibility shift among unrecorded records',
    y = 'True 60-month risk difference among all eligible people',
    color = 'Eligibility association',
    title = 'Observationally equivalent laws can define different target effects',
    subtitle = paste0('Decisive paired contrast: ',
                      scales::number(decision$delta_id, accuracy = 0.0001))
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig1-identification.png'), p1,
       width = 10, height = 6.5, dpi = 200)

plot_perf <- perf[
  perf$variant == 'primary' &
    !(perf$method %in% c('oracle_recording_ipaw')),
]
plot_perf$method_label <- c(
  oracle = 'Oracle eligibility',
  complete_case = 'Complete case',
  mar_ipaw = 'Eligibility-MAR weighting',
  fractional = 'Validation fractional',
  two_phase_ipw = 'Known-design two-phase weighting',
  augmented = 'Augmented two-phase correction'
)[plot_perf$method]
plot_perf <- plot_perf[!is.na(plot_perf$method_label), ]
plot_perf$validation_label <- paste0('Expected validation n = ',
                                     plot_perf$validation_n)

p2 <- ggplot(plot_perf,
             aes(x = bias, y = method_label, color = information_set)) +
  geom_vline(xintercept = c(-0.01, 0.01), linetype = 'dotted',
             color = 'grey55') +
  geom_errorbarh(aes(xmin = bias_ci95_lo, xmax = bias_ci95_hi),
                 height = 0, linewidth = 0.45) +
  geom_point(size = 1.4) +
  facet_grid(effect ~ validation_label) +
  labs(
    x = 'Signed bias with 95% Monte Carlo interval', y = NULL,
    color = 'Information set',
    title = 'Operating characteristics are separated by information set'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-method-bias.png'), p2,
       width = 12, height = 8, dpi = 200)

bounds$m_label <- paste0('Unrecorded = ', scales::percent(bounds$m, accuracy = 1))
p3 <- ggplot(bounds, aes(x = lambda, y = mean_width, color = factor(kappa))) +
  geom_hline(yintercept = 0.20, linetype = 'dotted', color = 'grey45') +
  geom_line(aes(group = interaction(kappa, effect)), linewidth = 0.7) +
  geom_point(size = 1.7) +
  facet_grid(effect ~ m_label) +
  scale_x_continuous(breaks = c(0, log(2), log(4)),
                     labels = c('0', 'log(2)', 'log(4)')) +
  labs(
    x = 'Generating latent shift', y = 'Mean risk-difference bound width',
    color = 'kappa',
    title = 'No-validation outer bounds retain truth at the cost of width'
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig3-partial-identification.png'), p3,
       width = 10, height = 6.5, dpi = 200)

message('figures written to ', FIG)
