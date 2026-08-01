## Study LRN-05: figures for paired distortion, calibration, and diagnostics.

.f <- grep('^--file=', commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub('^--file=', '', .f[1L]))))
} else normalizePath('.')
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here('R', '00-config.R'))

OUT <- here('results')
FIG <- here('out')
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

effects <- utils::read.csv(file.path(OUT, 'omission-effects.csv'))
decisions <- utils::read.csv(file.path(OUT, 'decisions.csv'))
curves <- utils::read.csv(file.path(OUT, 'calibration-curves.csv'))
diagnostics <- utils::read.csv(file.path(OUT, 'diagnostics.csv'))
scenarios <- build_scenarios()

effects <- merge(effects, scenarios, by = 'scenario', all.x = TRUE)
intercept <- effects[effects$metric == 'cal_intercept' &
                       effects$score == 'oracle' &
                       effects$strategy %in% STRATEGIES, ]
intercept$profile <- factor(intercept$profile, levels = PROFILE$profile)

p1 <- ggplot(intercept,
             aes(x = profile, y = effect, colour = strategy,
                 ymin = effect_lo, ymax = effect_hi)) +
  geom_hline(yintercept = c(-0.10, 0.10), colour = '#b2182b',
             linetype = 'dashed', linewidth = 0.45) +
  geom_hline(yintercept = c(-0.05, 0.05), colour = '#2166ac',
             linetype = 'dotted', linewidth = 0.45) +
  geom_errorbar(position = position_dodge(width = 0.45), width = 0.18) +
  geom_point(position = position_dodge(width = 0.45), size = 1.7) +
  facet_wrap(~ support, ncol = 1) +
  labs(x = 'Latent association profile',
       y = 'Exact complete-history minus full-history intercept',
       colour = 'Strategy',
       title = 'Paired omission effect on oracle-score calibration intercept',
       subtitle = 'Intervals are Monte Carlo intervals; horizontal lines mark the prespecified regions.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'top')
ggsave(file.path(FIG, 'fig1-intercept-omission.png'), p1,
       width = 10, height = 7, dpi = 200)

## Critique implementation: calibration curves remain strategy-specific. No
## visual subtraction pairs bins formed from different strategy-specific scores.
show_profiles <- c('P0', 'P7', 'P9', 'P10')
curve_plot <- merge(curves, scenarios[, c('scenario', 'profile', 'support')],
                    by = c('scenario', 'profile', 'support'), all.x = TRUE)
curve_plot <- curve_plot[curve_plot$profile %in% show_profiles &
                           curve_plot$method %in% c('full_history', 'exact_complete') &
                           curve_plot$score == 'oracle', ]
curve_plot$panel <- paste(curve_plot$profile, curve_plot$support, sep = ', ')

p2 <- ggplot(curve_plot,
             aes(x = score_mean, y = estimated_risk, colour = method,
                 group = method)) +
  geom_abline(intercept = 0, slope = 1, colour = 'grey55', linewidth = 0.45) +
  geom_line(linewidth = 0.65) +
  geom_point(size = 1.2) +
  facet_grid(strategy ~ panel, scales = 'free') +
  labs(x = 'Population mean predicted risk within strategy-specific decile',
       y = 'Estimated counterfactual event risk',
       colour = 'Weight method',
       title = 'Strategy-specific counterfactual calibration curves') +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'top',
        axis.text.x = element_text(angle = 35, hjust = 1))
ggsave(file.path(FIG, 'fig2-calibration-curves.png'), p2,
       width = 14, height = 7, dpi = 200)

oracle_decision <- decisions[decisions$score == 'oracle', ]
scenario_distortion <- aggregate(maximum_absolute_effect ~ scenario + strategy,
                                 oracle_decision, max, na.rm = TRUE)
diag_plot <- merge(diagnostics, scenario_distortion,
                   by = c('scenario', 'strategy'), all.x = TRUE)
diag_plot <- diag_plot[diag_plot$method %in%
                         c('full_history', 'exact_complete', 'exact_reduced',
                           'fitted_reduced'), ]

p3 <- ggplot(diag_plot,
             aes(x = maximum_absolute_effect, y = flag_probability,
                 colour = method, shape = strategy)) +
  geom_errorbar(aes(ymin = flag_lo, ymax = flag_hi), width = 0,
                alpha = 0.55) +
  geom_point(size = 2) +
  facet_wrap(~ method) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = 'Largest absolute oracle-score omission effect in the scenario',
       y = 'Probability that the weight diagnostic flags',
       colour = 'Method', shape = 'Strategy',
       title = 'Do conventional weight diagnostics flag consequential distortion?') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = 'top')
ggsave(file.path(FIG, 'fig3-diagnostic-operating-characteristics.png'), p3,
       width = 11, height = 7, dpi = 200)

message('figures written to ', FIG)
