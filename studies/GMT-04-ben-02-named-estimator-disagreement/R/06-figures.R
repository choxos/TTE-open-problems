## GMT-04 benchmark: figures for named implementations and decision endpoints.

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
performance <- utils::read.csv(file.path(OUT, 'performance.csv'))
disagreement <- utils::read.csv(file.path(OUT, 'disagreement.csv'))
hidden <- utils::read.csv(file.path(OUT, 'hidden-agreement.csv'))
diagnostics <- utils::read.csv(file.path(OUT, 'diagnostic-performance.csv'))

method_labels <- c(
  iptw_nuisance = 'IPTW, nuisance-adjusted interval',
  iptw_fixed = 'IPTW, fixed-weight interval',
  gformula_pooled = 'Pooled parametric g-formula',
  ltmle_formula = 'Formula-based longitudinal TMLE'
)

factorial <- performance[performance$type == 'factorial' &
                           performance$method != 'iptw_fixed', ]
factorial$method_label <- method_labels[factorial$method]
factorial$u_label <- ifelse(factorial$observed_u, 'U observed', 'U hidden')

p1 <- ggplot(factorial,
             aes(x = factor(s), y = bias, colour = method_label,
                 group = method_label)) +
  geom_hline(yintercept = 0, colour = 'grey55', linewidth = 0.4) +
  geom_line(linewidth = 0.6) +
  geom_point(size = 1.5) +
  facet_grid(u_label ~ role, scales = 'free_y') +
  labs(
    x = 'Practical overlap scale', y = 'Bias in the 36-month risk difference',
    colour = 'Named implementation',
    title = 'Bias of the three prespecified point implementations',
    subtitle = 'Selective nuisance quadrants and hidden U are controls, not declaration scenarios.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig1-implementation-bias.png'), p1,
       width = 12, height = 7, dpi = 200)

primary <- disagreement[disagreement$primary, ]
controls <- disagreement[!is.na(disagreement$control), ]
plot_disagreement <- rbind(
  data.frame(label = primary$scenario_label,
             probability = primary$disagreement_probability,
             lower = primary$disagreement_lower, upper = primary$disagreement_upper,
             group = 'Primary benchmark'),
  data.frame(label = controls$scenario_label,
             probability = controls$disagreement_probability,
             lower = controls$disagreement_lower, upper = controls$disagreement_upper,
             group = 'Calibration control')
)
plot_disagreement$label <- factor(plot_disagreement$label,
                                  levels = rev(plot_disagreement$label))
p2 <- ggplot(plot_disagreement,
             aes(x = probability, y = label, colour = group)) +
  geom_vline(xintercept = PRIMARY_PROBABILITY_THRESHOLD,
             linetype = 2, colour = 'grey45') +
  geom_errorbarh(aes(xmin = lower, xmax = upper), height = 0.18) +
  geom_point(size = 2) +
  scale_x_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    x = 'Probability that the within-replicate estimate range exceeds 0.03',
    y = NULL, colour = NULL,
    title = 'Primary disagreement and calibration controls',
    subtitle = 'The vertical line is the symmetric decision threshold of 0.20.'
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-primary-disagreement.png'), p2,
       width = 10, height = 6, dpi = 200)

p3 <- ggplot(hidden,
             aes(x = h_probability, y = reorder(scenario_label, h_probability))) +
  geom_errorbarh(aes(xmin = h_lower, xmax = h_upper), height = 0.18,
                 colour = '#355C7D') +
  geom_point(size = 2, colour = '#355C7D') +
  scale_x_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    x = 'Probability of close agreement with shared absolute error above 0.02',
    y = NULL,
    title = 'Within-dataset agreement under the composite hidden-U failure',
    subtitle = 'Agreement is defined by an estimate range below 0.01.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, 'fig3-hidden-u-agreement.png'), p3,
       width = 10, height = 7, dpi = 200)

primary_diagnostics <- diagnostics[
  diagnostics$coefficient_cutoff == 20 &
    diagnostics$condition_cutoff == 1e12,
]
primary_diagnostics$method_label <- method_labels[primary_diagnostics$method]
p4 <- ggplot(primary_diagnostics,
             aes(x = sensitivity, y = positive_predictive_value,
                 colour = method_label)) +
  geom_point(alpha = 0.75, size = 1.8, na.rm = TRUE) +
  coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
  scale_x_continuous(labels = scales::percent_format()) +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(
    x = 'Diagnostic sensitivity', y = 'Diagnostic positive predictive value',
    colour = 'Named implementation',
    title = 'Diagnostic performance for gross estimation error',
    subtitle = 'Rates are shown only when the applicable denominator is at least 400.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig4-diagnostic-performance.png'), p4,
       width = 9, height = 6, dpi = 200)

message('figures written to ', FIG)
