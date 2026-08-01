## Study PRO-04: figures.
##
##   Rscript R/06-figures.R

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

surface <- utils::read.csv(file.path(OUT, 'response-surface.csv'))
probabilities <- utils::read.csv(file.path(OUT, 'mechanism-probabilities.csv'))
standardized <- utils::read.csv(file.path(OUT, 'standardized-probabilities.csv'))
diagnostics <- utils::read.csv(file.path(OUT, 'diagnostic-performance.csv'))

component_labels <- c(
  eligibility = 'Eligibility substituted',
  strategy = 'Treatment strategy substituted',
  outcome = 'Outcome substituted'
)
dependence_labels <- c(
  nondifferential = 'Nondifferential',
  differential = 'Differential with matched mean fidelity'
)

surface$component_label <- component_labels[surface$component]
surface$dependence_label <- dependence_labels[surface$dependence]
p1 <- ggplot(surface, aes(x = lambda, y = mean_delta, colour = fidelity,
                          fill = fidelity)) +
  geom_hline(yintercept = c(-MATERIAL_MARGIN, -PRESERVATION_MARGIN,
                            PRESERVATION_MARGIN, MATERIAL_MARGIN),
             colour = 'grey65', linewidth = 0.35) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.14, colour = NA) +
  geom_line(linewidth = 0.75) +
  facet_grid(component_label ~ dependence_label, scales = 'free_y') +
  scale_colour_manual(values = c(mild = '#2C7FB8', severe = '#D95F0E')) +
  scale_fill_manual(values = c(mild = '#2C7FB8', severe = '#D95F0E')) +
  labs(
    x = 'Effect-modification parameter lambda',
    y = 'Mean operational minus intended risk difference',
    colour = 'Fidelity', fill = 'Fidelity',
    title = 'Continuous response surface for the protocol substitution gap',
    subtitle = 'Bands are regression confidence intervals under the declared synthetic mechanism distribution.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'top')
ggsave(file.path(FIG, 'fig1-delta-response-surface.png'), p1,
       width = 11, height = 8, dpi = 200)

probabilities$component_label <- component_labels[probabilities$component]
prob_long <- rbind(
  data.frame(probabilities[, c('scenario', 'component_label', 'fidelity',
                                'effect_modification', 'dependence')],
             classification = 'Material change', probability = probabilities$p_material),
  data.frame(probabilities[, c('scenario', 'component_label', 'fidelity',
                                'effect_modification', 'dependence')],
             classification = 'Numerical preservation', probability = probabilities$p_preserving)
)
prob_long$dependence_label <- dependence_labels[prob_long$dependence]
p2 <- ggplot(prob_long, aes(x = fidelity, y = probability,
                            fill = classification)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  facet_grid(component_label + effect_modification ~ dependence_label) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_fill_manual(values = c('Material change' = '#B2182B',
                               'Numerical preservation' = '#2166AC')) +
  labs(x = 'Mean operational fidelity', y = 'Mechanism-distribution probability',
       fill = NULL,
       title = 'Stratum-specific probabilities of numerical preservation and material change',
       subtitle = 'Probabilities describe the synthetic distributions and not applied prevalence.') +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(), legend.position = 'top')
ggsave(file.path(FIG, 'fig2-mechanism-probabilities.png'), p2,
       width = 11, height = 9, dpi = 200)

scored <- diagnostics[diagnostics$method == 'gap_aug' &
                        diagnostics$metric %in% c('preserving_sensitivity',
                                                  'changed_sensitivity'), ]
scored$label <- ifelse(scored$metric == 'preserving_sensitivity',
                       'Preserving-class sensitivity', 'Changed-class sensitivity')
p3 <- ggplot(scored, aes(x = label, y = estimate)) +
  geom_hline(yintercept = 0.80, linetype = 'dotted', colour = '#B2182B') +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.12) +
  geom_point(size = 2.5, colour = '#2166AC') +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = NULL, y = 'Classification probability',
       title = 'Primary augmented two-phase diagnostic accuracy',
       subtitle = 'Wilson intervals are scored only at absolute Delta no greater than 0.005 or at least 0.03.') +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, 'fig3-augmented-diagnostic.png'), p3,
       width = 8, height = 5, dpi = 200)

message('figures written to ', FIG)
