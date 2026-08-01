## Study 2 (BEN-02): figures.
##
##   Rscript R/06-figures.R

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .f[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

agreement <- utils::read.csv(
  file.path(OUT, "paired-agreement-probabilities.csv"),
  stringsAsFactors = FALSE
)
ranges <- utils::read.csv(
  file.path(OUT, "precision-ranges.csv"),
  stringsAsFactors = FALSE
)
curves <- utils::read.csv(
  file.path(OUT, "compatibility-curves.csv"),
  stringsAsFactors = FALSE
)

agreement$precision <- factor(
  agreement$precision, levels = PRECISION$precision, ordered = TRUE
)
agreement$n_trial <- PRECISION$n_trial[match(
  as.character(agreement$precision), PRECISION$precision
)]
agreement$operator <- factor(
  agreement$operator,
  levels = c("direction", "overlap"),
  labels = c("Direction match", "Interval overlap")
)

p1 <- ggplot(
  agreement,
  aes(x = n_trial, y = agreement_probability,
      color = mismatch, group = interaction(scenario, mismatch))
) +
  geom_line(linewidth = 0.55, alpha = 0.75) +
  geom_point(size = 1.3) +
  facet_grid(operator ~ family + baseline_risk) +
  scale_x_log10(breaks = PRECISION$n_trial, labels = scales::comma) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    x = "Trial sample size",
    y = "Agreement probability",
    color = "Mismatch mechanism",
    title = "Agreement labels change while pair-level truths stay fixed",
    subtitle = "Each line is one structural scenario with nested precision levels."
  ) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(
  file.path(FIG, "fig1-agreement-by-precision.png"),
  p1, width = 12, height = 7, dpi = 200
)

ranges$operator <- factor(
  ranges$operator,
  levels = c("direction", "overlap"),
  labels = c("Direction match", "Interval overlap")
)
ranges$scenario_label <- sprintf("%02d", ranges$scenario)
p2 <- ggplot(
  ranges,
  aes(x = scenario_label, y = probability_range, fill = operator)
) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = PRIMARY_S_THRESHOLD, linetype = 2, color = "firebrick") +
  facet_wrap(~ mismatch, scales = "free_x") +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(
    x = "Structural scenario",
    y = "Range across three precision levels",
    fill = "Illustrative operator",
    title = "Scenario-level precision sensitivity",
    subtitle = "The horizontal line is the prespecified materiality threshold for aggregate S."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(
  file.path(FIG, "fig2-precision-ranges.png"),
  p2, width = 11, height = 6, dpi = 200
)

curves <- curves[abs(curves$delta - DELTA_PRIMARY) < 1e-12, ]
curves$precision <- factor(
  curves$precision, levels = PRECISION$precision, ordered = TRUE
)
p3 <- ggplot(
  curves,
  aes(x = decision_rate, y = wrong_definitive,
      color = precision, group = precision)
) +
  geom_path(linewidth = 0.8) +
  geom_point(aes(size = cutoff), alpha = 0.7) +
  scale_x_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  scale_size_continuous(range = c(0.8, 2.5)) +
  labs(
    x = "Definitive decision rate",
    y = "Wrong definitive decision probability",
    color = "Precision",
    size = "Compatibility cutoff",
    title = "Compatibility score error and decision rate",
    subtitle = "Delta equals 0.02. Points average the fixed structural scenarios equally."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "right")
ggsave(
  file.path(FIG, "fig3-error-decision-curves.png"),
  p3, width = 9, height = 6, dpi = 200
)

message("figures written to ", FIG)
