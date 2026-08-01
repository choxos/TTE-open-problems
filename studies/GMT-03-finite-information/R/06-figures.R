## Study GMT-03: figures for coverage and time-varying information.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1L])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))
OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

perf <- utils::read.csv(file.path(OUT, "cell-decisions.csv"),
                        stringsAsFactors = FALSE)
monthly <- utils::read.csv(file.path(OUT, "monthly-diagnostics.csv"),
                           stringsAsFactors = FALSE)
validation <- utils::read.csv(file.path(OUT, "validation-index-studies.csv"),
                              stringsAsFactors = FALSE)

primary <- perf[perf$horizon == 60L & perf$method %in% c("exact_fixed", "msm"), ]
primary$family <- paste(primary$endpoint, primary$subgroup, sep = ", ")

p1 <- ggplot(primary, aes(x = median_min_riskset_ess, y = coverage,
                          colour = decision, shape = method)) +
  geom_hline(yintercept = c(0.90, 0.925), colour = "grey55",
             linetype = c("dashed", "dotted")) +
  geom_vline(xintercept = RISKSET_ESS_FLAG, colour = "grey55", linetype = "dashed") +
  geom_point(alpha = 0.75, size = 1.7) +
  facet_wrap(~ family, scales = "free_x") +
  scale_x_log10() +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Median minimum arm-specific risk-set Kish effective sample size",
       y = "Conditional interval coverage", colour = "Decision branch",
       shape = "Estimator",
       title = "Coverage against the minimum longitudinal risk-set ESS",
       subtitle = "Horizontal lines are the 0.90 failure and 0.925 adequacy boundaries.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig1-coverage-riskset-ess.png"), p1,
       width = 11, height = 7, dpi = 200)

p2 <- ggplot(primary, aes(x = median_event_ess, y = coverage,
                          colour = decision, shape = method)) +
  geom_hline(yintercept = c(0.90, 0.925), colour = "grey55",
             linetype = c("dashed", "dotted")) +
  geom_vline(xintercept = EVENT_ESS_FLAG, colour = "grey55", linetype = "dashed") +
  geom_point(alpha = 0.75, size = 1.7) +
  facet_wrap(~ family, scales = "free_x") +
  scale_x_log10() +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Median minimum arm-specific effective event count",
       y = "Conditional interval coverage", colour = "Decision branch",
       shape = "Estimator",
       title = "Endpoint-specific coverage against effective event information",
       subtitle = "Primary and competing endpoints remain in separate panels.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig2-coverage-event-ess.png"), p2,
       width = 11, height = 7, dpi = 200)

m <- monthly[monthly$subgroup == "all" & monthly$phase == "core", ]
m$scenario_label <- paste0("n=", m$n, ", ", m$k_level)
p3 <- ggplot(m, aes(x = month, y = kish_ess_median, colour = factor(strategy),
                    group = interaction(scenario, strategy))) +
  geom_hline(yintercept = RISKSET_ESS_FLAG, colour = "grey55", linetype = "dashed") +
  geom_line(alpha = 0.22, linewidth = 0.35) +
  facet_grid(method ~ n, scales = "free_y") +
  scale_y_log10() +
  labs(x = "Month", y = "Median arm-specific risk-set Kish ESS",
       colour = "Strategy",
       title = "Effective information changes over follow-up",
       subtitle = "Each line is one core scenario. Nominal n is shown by column.") +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig3-time-varying-ess.png"), p3,
       width = 11, height = 7, dpi = 200)

if (nrow(validation)) {
  validation$family <- factor(validation$family)
  p4 <- ggplot(validation, aes(x = min_riskset_ess, y = coverage,
                              colour = factor(warning), shape = method)) +
    geom_hline(yintercept = c(0.90, 0.925), colour = "grey55",
               linetype = c("dashed", "dotted")) +
    geom_vline(xintercept = RISKSET_ESS_FLAG, colour = "grey55", linetype = "dashed") +
    geom_point(alpha = 0.8) +
    facet_wrap(~ family) +
    scale_x_log10() +
    scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
    labs(x = "Index-study minimum risk-set ESS", y = "Independent scenario coverage",
         colour = "Index warning", shape = "Estimator",
         title = "Held-out index warnings and independently estimated coverage") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(), legend.position = "bottom")
  ggsave(file.path(FIG, "fig4-heldout-validation.png"), p4,
         width = 11, height = 7, dpi = 200)
}
message("figures written to ", FIG)
