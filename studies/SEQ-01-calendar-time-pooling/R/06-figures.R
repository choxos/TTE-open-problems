## Study SEQ-01: trial-specific, operating-characteristic, and efficiency figures.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)
source(here("R", "00-config.R"))
suppressPackageStartupMessages(library(ggplot2))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
truth <- utils::read.csv(file.path(OUT, "truth.csv"))
trial <- utils::read.csv(file.path(OUT, "trial-specific.csv"))
diag <- utils::read.csv(file.path(OUT, "diagnostics.csv"))
eff <- utils::read.csv(file.path(OUT, "efficiency.csv"))
scenarios <- build_scenarios()

show_methods <- c("equal_common", "equal_flexible", "start_saturated")
d <- trial[trial$method %in% show_methods, ]
d$method <- factor(d$method, levels = show_methods,
                   labels = c("Equal-start common effect",
                              "Equal-start flexible effect",
                              "Start-saturated benchmark"))
d$facet <- paste0(d$h_key, "; adoption ", d$adoption,
                  "; background risk ", d$background)

p1 <- ggplot(d, aes(x = start, y = truth, group = scenario)) +
  geom_ribbon(aes(ymin = truth - 0, ymax = truth + 0), alpha = 0) +
  geom_line(aes(color = "Truth"), linewidth = 0.8) +
  geom_point(aes(y = truth + bias, color = method), size = 1.3) +
  geom_errorbar(aes(ymin = truth + bias - 1.96 * bias_mcse,
                    ymax = truth + bias + 1.96 * bias_mcse,
                    color = method), width = 0.35, linewidth = 0.35) +
  facet_wrap(~ facet, scales = "free_y") +
  scale_x_continuous(breaks = STARTS) +
  labs(x = "Trial start month", y = "12-month risk difference",
       color = NULL,
       title = "Every trial-specific effect remains visible",
       subtitle = "Points are Monte Carlo mean estimates; lines are mechanism-based truth.") +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig1-trial-specific-curves.png"), p1,
       width = 13, height = 9, dpi = 200)

plot_diag <- merge(diag, scenarios, by = "scenario")
plot_diag$truth_class <- factor(plot_diag$truth_class,
                                levels = c("near", "indifference", "material"))
p2 <- ggplot(plot_diag, aes(x = factor(scenario), y = positive_rate,
                            fill = truth_class)) +
  geom_col(width = 0.75) +
  geom_hline(yintercept = c(DIAG_SENS_INADEQUATE, DIAG_SENS_ADEQUATE),
             linetype = c("dotted", "dashed"), color = "grey35") +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = "Scenario", y = "Positive material-heterogeneity diagnostic",
       fill = "Truth set",
       title = "RD-scale material-heterogeneity diagnostic",
       subtitle = "Exact-homogeneity rejection is reported separately in diagnostics.csv.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig2-material-diagnostic.png"), p2,
       width = 9, height = 5.5, dpi = 200)

plot_eff <- merge(eff, scenarios, by = "scenario")
p3 <- ggplot(plot_eff, aes(x = factor(scenario), y = variance_ratio,
                           color = truth_class)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey35") +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.25) +
  geom_point(size = 2) +
  labs(x = "Scenario",
       y = "Variance: flexible pooled RD12 / standalone RD12",
       color = "Truth set",
       title = "Does pooling retain precision after person-level inference?",
       subtitle = "Values below one favor the flexible sequential emulation.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig3-pooling-efficiency.png"), p3,
       width = 9, height = 5.5, dpi = 200)

message("figures written to ", FIG)
