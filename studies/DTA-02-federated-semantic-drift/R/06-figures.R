## DTA-02: figures for estimand changes, gate safety, and interval behavior.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here('R', '00-config.R'))

OUT <- here('results')
FIG <- here('out')
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

paired <- utils::read.csv(file.path(OUT, 'paired-changes.csv'))
gates <- utils::read.csv(file.path(OUT, 'gate-performance.csv'))
perf <- utils::read.csv(file.path(OUT, 'performance.csv'))

mapping_labels <- c(
  'eligibility-visible' = 'Visible eligibility drift',
  'eligibility-stealth' = 'Aggregate-stealth eligibility drift',
  'exposure-broad' = 'Broad exposure',
  'outcome-broad' = 'Broad outcome',
  'label-permutation' = 'Label permutation control'
)
paired$mapping_label <- mapping_labels[paired$mapping]
paired$gamma_label <- sprintf('gamma = %.2f', paired$gamma)

p1 <- ggplot(paired, aes(x = factor(kappa), y = paired_mean_change,
                         ymin = familywise_lower, ymax = familywise_upper,
                         colour = mapping_label)) +
  geom_hline(yintercept = 0, colour = 'grey45', linewidth = 0.4) +
  geom_hline(yintercept = c(-EQUIVALENCE_MARGIN, EQUIVALENCE_MARGIN),
             linetype = 3, colour = 'grey60', linewidth = 0.35) +
  geom_pointrange(position = position_dodge(width = 0.55), linewidth = 0.45) +
  facet_wrap(~ gamma_label) +
  labs(x = 'Mapping-consequence coupling kappa',
       y = 'Paired change in equal-site common-q estimate',
       colour = 'Production mapping',
       title = 'Semantic mapping changes are scenario-specific',
       subtitle = 'Intervals are familywise 95 percent Monte Carlo intervals; dotted lines mark the equivalence margin.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'right')
ggsave(file.path(FIG, 'fig1-paired-target-change.png'), p1,
       width = 10.5, height = 6.2, dpi = 200)

plot_gates <- gates[gates$method %in% c('aggregate-gate', 'validation-50',
                                        'validation-100', 'validation-200') &
                      gates$tolerance == 0.01, ]
plot_gates$mapping_label <- ifelse(
  plot_gates$mapping == 'compatible', 'Compatible', mapping_labels[plot_gates$mapping])
plot_gates$method <- factor(plot_gates$method,
                            levels = c('aggregate-gate', 'validation-50',
                                       'validation-100', 'validation-200'))

p2 <- ggplot(plot_gates,
             aes(x = release_probability, y = unsafe_release, colour = method)) +
  geom_vline(xintercept = DIAGNOSTIC_ADEQUATE_LOWER,
             linetype = 3, colour = 'grey55') +
  geom_hline(yintercept = SAFETY_ADEQUATE_UPPER,
             linetype = 3, colour = 'grey55') +
  geom_point(alpha = 0.75, size = 1.7) +
  facet_grid(reference ~ mapping_label) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = 'Network release probability',
       y = 'Unsafe-release probability at tolerance 0.01',
       colour = 'Gate',
       title = 'Safety cannot be separated from abstention',
       subtitle = 'Each point is one kappa by gamma cell.') +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(),
        axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-release-and-safety.png'), p2,
       width = 14, height = 7.5, dpi = 200)

interval_methods <- c('historical-fixed', 'historical-dl', 'commonq-fixed',
                      'pm-hk', 'equalq')
p3dat <- perf[perf$method %in% interval_methods, ]
p3dat$method <- factor(p3dat$method, levels = interval_methods)
p3 <- ggplot(p3dat, aes(x = method, y = coverage, colour = mapping)) +
  geom_hline(yintercept = 0.95, linetype = 3, colour = 'grey55') +
  geom_point(position = position_jitter(width = 0.15, height = 0), alpha = 0.55) +
  facet_grid(gamma ~ kappa, labeller = label_both) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = NULL, y = 'Coverage against the method-specific functional',
       colour = 'Mapping',
       title = 'Interval performance is evaluated against the quantity each method targets') +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(),
        axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = 'bottom')
ggsave(file.path(FIG, 'fig3-method-specific-coverage.png'), p3,
       width = 12, height = 7, dpi = 200)

message('figures written to ', FIG)
