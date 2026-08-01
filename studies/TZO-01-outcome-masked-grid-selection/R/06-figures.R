## Study TZO-01: figures for movement, selection, and resource comparisons.

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

movement <- utils::read.csv(file.path(OUT, 'movement.csv'))
pairs <- utils::read.csv(file.path(OUT, 'movement-pairs.csv'))
selection <- utils::read.csv(file.path(OUT, 'selection-frequency.csv'))
selector <- utils::read.csv(file.path(OUT, 'selector-comparison.csv'))
resources <- utils::read.csv(file.path(OUT, 'resource-summary.csv'))
cells <- build_cells()

pairs <- merge(pairs, cells[, c('cell', 'profile', 'G', 'visit_key', 'pressure_key')],
               by = 'cell', all.x = TRUE)
pairs$label <- factor(pairs$label,
                      levels = c('1-vs-2', '1-vs-4', '1-vs-8',
                                 '2-vs-4', '2-vs-8', '4-vs-8'))

p1 <- ggplot(pairs, aes(x = mean, y = label, xmin = lower, xmax = upper,
                        color = profile)) +
  geom_vline(xintercept = c(-GRID_MARGIN, GRID_MARGIN),
             linetype = 'dotted', color = 'grey40') +
  geom_errorbarh(height = 0.15) +
  geom_point(size = 1.2) +
  facet_grid(visit_key + pressure_key ~ G, scales = 'free_y') +
  labs(
    x = 'Paired difference between expected risk-difference estimates',
    y = 'Grid comparison',
    color = 'Outcome profile',
    title = 'Simultaneous Monte Carlo intervals for expected grid movement',
    subtitle = 'Dotted lines mark the prespecified equivalence margin.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig1-grid-movement.png'), p1,
       width = 12, height = 10, dpi = 200)

selection <- merge(selection, cells[, c('cell', 'profile', 'G', 'visit_key', 'pressure_key')],
                   by = 'cell', all.x = TRUE)
p2 <- ggplot(selection, aes(x = factor(selected_grid), y = frequency,
                            fill = profile)) +
  geom_col(position = 'dodge') +
  facet_grid(visit_key + pressure_key ~ G) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(
    x = 'Selected grid in weeks', y = 'Selection frequency',
    fill = 'Outcome profile',
    title = 'Outcome-masked process selector',
    subtitle = 'Outcome-law twins must have the same selection distribution.'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig2-selection-frequency.png'), p2,
       width = 11, height = 7, dpi = 200)

selector <- merge(selector, cells[, c('cell', 'profile', 'G', 'visit_key', 'pressure_key')],
                  by = 'cell', all.x = TRUE)
p3 <- ggplot(selector, aes(x = time_reduction, y = mse_ratio, color = selector_verdict)) +
  geom_vline(xintercept = MIN_TIME_REDUCTION, linetype = 'dotted') +
  geom_hline(yintercept = 1, linetype = 'dotted') +
  geom_errorbar(aes(ymin = mse_ratio_lower, ymax = mse_ratio_upper), width = 0) +
  geom_errorbarh(aes(xmin = time_reduction_lower, xmax = time_reduction_upper), height = 0) +
  geom_point(size = 2) +
  facet_grid(visit_key + pressure_key ~ G) +
  labs(
    x = 'Reduction in total worker time',
    y = 'Mean squared error ratio versus one week on 5000 people',
    color = 'Selector verdict',
    title = 'Resource and accuracy requirements for selector success'
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = 'bottom')
ggsave(file.path(FIG, 'fig3-selector-comparison.png'), p3,
       width = 11, height = 8, dpi = 200)

message('figures written to ', FIG)
