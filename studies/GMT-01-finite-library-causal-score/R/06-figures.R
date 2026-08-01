## GMT-01: figures for performance, paired gains, and selections.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
perf <- utils::read.csv(file.path(OUT, "performance.csv"))
paired <- utils::read.csv(file.path(OUT, "paired-comparisons.csv"))
selection <- utils::read.csv(file.path(OUT, "selection-frequencies.csv"))
scenarios <- build_scenarios()

ostep <- perf[perf$method %in% c("predictive-ostep", "balance-ostep",
                                 "combined-ostep", "oracle-ostep"), ]
ostep$method <- factor(ostep$method,
  levels = c("predictive-ostep", "balance-ostep", "combined-ostep", "oracle-ostep"),
  labels = c("Predictive CV", "Bespoke balance", "Combined score", "Library oracle"))
ostep$stratum <- ifelse(ostep$gamma_z_key == "absent",
                        "Primary: treatment-only predictor absent",
                        "Positive control: treatment-only predictor present")

p1 <- ggplot(ostep, aes(x = factor(scenario), y = coverage, color = method)) +
  geom_hline(yintercept = 0.95, color = "grey55", linewidth = 0.4) +
  geom_point(position = position_dodge(width = 0.55), size = 1.6) +
  facet_wrap(~stratum, scales = "free_x") +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Scenario", y = "Empirical 95% coverage", color = "Selector",
       title = "One-step interval coverage by scenario",
       subtitle = "IPW sensitivity bands are excluded because they are not nominal intervals") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), axis.text.x = element_text(angle = 90, vjust = 0.5))
ggsave(file.path(FIG, "fig1-coverage.png"), p1, width = 11, height = 6, dpi = 200)

pred <- paired[paired$comparator == "predictive", ]
pred$stratum <- ifelse(pred$gamma_z_key == "absent", "gamma_Z = 0 primary stratum",
                       "nonzero gamma_Z positive controls")
p2 <- ggplot(pred, aes(x = factor(scenario), y = absolute_bias_gain,
                       ymin = absolute_bias_lower, ymax = absolute_bias_upper,
                       color = separation_key)) +
  geom_hline(yintercept = DECISION$favorable_abs_bias, linetype = 2, color = "grey45") +
  geom_hline(yintercept = 0, linewidth = 0.4) +
  geom_pointrange(position = position_dodge(width = 0.4)) +
  facet_wrap(~stratum, scales = "free_x") +
  labs(x = "Scenario", y = "Absolute-bias reduction versus predictive CV",
       color = "Propensity separation", title = "Paired selector improvement",
       subtitle = "Vertical intervals are paired Monte Carlo bootstrap intervals") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), axis.text.x = element_text(angle = 90, vjust = 0.5))
ggsave(file.path(FIG, "fig2-paired-bias-gain.png"), p2, width = 11, height = 6, dpi = 200)

p3 <- ggplot(selection, aes(x = candidate, y = proportion, fill = field)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~field, scales = "free_x") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Selected candidate in an outer fold", y = "Selection frequency",
       title = "Equal-weight combined-score selections") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig3-selection-frequencies.png"), p3,
       width = 9, height = 4.5, dpi = 200)
message("figures written to ", FIG)
