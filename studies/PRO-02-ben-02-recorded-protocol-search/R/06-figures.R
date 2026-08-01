## Study 2 (PRO-02): figures for calibration, global deficits, and selection.
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

calibration <- utils::read.csv(file.path(OUT, "calibration.csv"))
global <- utils::read.csv(file.path(OUT, "global-deficits.csv"))
selection <- utils::read.csv(file.path(OUT, "selection-frequency.csv"))
risk <- utils::read.csv(file.path(OUT, "multiverse-risk.csv"))

p1 <- ggplot(calibration,
             aes(x = candidate, y = coverage, colour = factor(event_target))) +
  geom_hline(yintercept = CALIBRATION_RANGE, colour = "grey55",
             linewidth = 0.4, linetype = "dotted") +
  geom_point(size = 1.2, alpha = 0.8) +
  facet_grid(effect ~ K, scales = "free_x", space = "free_x") +
  coord_cartesian(ylim = c(0.88, 1.00)) +
  labs(x = "Prespecified protocol", y = "Unconditional 95% coverage",
       colour = "Expected events\nat anchor",
       title = "Fixed-candidate calibration gate",
       subtitle = "Failures count as noncoverage; every declared candidate is shown.") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 60, hjust = 1),
        panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig1-fixed-calibration.png"), p1,
       width = 12, height = 7, dpi = 200)

global$estimand <- factor(global$estimand,
                          levels = c("D_all", "D_nonboundary", "D_boundary"))
p2 <- ggplot(global, aes(x = estimand, y = deficit)) +
  geom_hline(yintercept = MATERIAL_DEFICIT, colour = "firebrick",
             linewidth = 0.6, linetype = "dashed") +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.12) +
  geom_point(size = 2.4) +
  scale_x_discrete(labels = c(
    D_all = "All regimes",
    D_nonboundary = "Nonboundary regimes",
    D_boundary = "Boundary regime")) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
  labs(x = NULL, y = "Deficit from 95% coverage",
       title = "Global coverage deficits after recorded effect-blind search",
       subtitle = "Intervals form the registered simultaneous Monte Carlo rectangle.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig2-global-deficits.png"), p2,
       width = 8, height = 5, dpi = 200)

show_selection <- selection[
  selection$method == "naive" &
    selection$selector %in% c("workability", "prognostic_high", "prognostic_low"), ]
p3 <- ggplot(show_selection,
             aes(x = candidate, y = frequency, fill = selector)) +
  geom_col(position = "dodge") +
  facet_grid(effect + event_target ~ K, scales = "free_x", space = "free_x") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Selected protocol", y = "Selection frequency",
       fill = "Selector",
       title = "Which recorded protocol was selected?",
       subtitle = "The same generated dataset supplies both prognostic-score analyses.") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 60, hjust = 1),
        panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig3-selection-frequency.png"), p3,
       width = 13, height = 9, dpi = 200)

risk$category <- factor(risk$category,
                        levels = c("below_1", "1_through_2", "above_2"),
                        labels = c("Below 1", "1 through 2", "Above 2"))
p4 <- ggplot(risk, aes(x = category, y = noncoverage_risk,
                       colour = selector, group = selector)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Multiverse range divided by median candidate SE",
       y = "Risk of naive interval noncoverage",
       colour = "Selector",
       title = "Does multiverse spread predict noncoverage?") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig4-multiverse-prediction.png"), p4,
       width = 8, height = 5, dpi = 200)

message("figures written to ", FIG)
