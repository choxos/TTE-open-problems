## LRN-01 support stress study: decision-facing figures.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else normalizePath(".")
here <- function(...) file.path(STUDY, ...)
suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
compatible <- utils::read.csv(file.path(OUT, "compatible-performance.csv"))
paired <- utils::read.csv(file.path(OUT, "paired-excess.csv"))
warning <- utils::read.csv(file.path(OUT, "support-warning-performance.csv"))
reduction <- utils::read.csv(file.path(OUT, "map-reduction.csv"))

primary <- compatible[abs(compatible$magnitude - PRIMARY_MAGNITUDE) < 1e-10, ]
primary$complexity_label <- ifelse(primary$complexity == 0, "Main-effects law", "Nonlinear law")
primary$method <- factor(primary$method, levels = METHODS,
                         labels = c("Fixed-cap IPW", "Main-effects AIPW",
                                    "Flexible series AIPW", "Flexible AIPW plus map"))
p1 <- ggplot(primary, aes(x = support_key, y = false_certainty,
                          color = method, group = method)) +
  geom_point(position = position_dodge(width = 0.55), size = 1.5) +
  facet_grid(complexity_label ~ n, labeller = label_both) +
  coord_flip() +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = NULL, y = "Conventionally green intervals missing the compatible-truth set",
       color = "Workflow", title = "False certainty under exact support holes",
       subtitle = "Compatible sets use the prespecified log(2) completion magnitude") +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig1-false-certainty.png"), p1,
       width = 11, height = 8, dpi = 200)

paired$comparison <- factor(paired$comparison,
  levels = c("flex-minus-ipw", "flex-minus-main_aipw"),
  labels = c("Flexible minus fixed-cap IPW", "Flexible minus main-effects AIPW"))
paired$complexity_label <- ifelse(paired$complexity == 0, "Main-effects law", "Nonlinear law")
p2 <- ggplot(paired, aes(x = support_key, y = estimate, ymin = lower, ymax = upper,
                         color = comparison)) +
  geom_hline(yintercept = c(DECISION$excess_not_supported_upper,
                            DECISION$excess_support_lower),
             linetype = c("dotted", "dashed"), color = "grey45") +
  geom_pointrange(position = position_dodge(width = 0.55), linewidth = 0.35) +
  facet_grid(complexity_label ~ n, labeller = label_both) +
  coord_flip() +
  labs(x = NULL, y = "Paired false-certainty excess",
       color = "Comparison", title = "Simultaneous Monte Carlo bounds for the primary contrasts",
       subtitle = "Reference lines are the 0.05 not-supported and 0.10 supported margins") +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig2-paired-excess.png"), p2,
       width = 11, height = 8, dpi = 200)

warning$metric <- ifelse(warning$target == "specificity", "Specificity", "Sensitivity")
warning$complexity_label <- ifelse(warning$complexity == 0, "Main-effects law", "Nonlinear law")
p3 <- ggplot(warning, aes(x = support_key, y = estimate, ymin = lower, ymax = upper,
                          color = metric)) +
  geom_hline(yintercept = 0.90, linetype = "dashed", color = "grey45") +
  geom_pointrange(position = position_dodge(width = 0.5), linewidth = 0.35) +
  facet_grid(complexity_label ~ n, labeller = label_both) +
  coord_flip() +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(x = NULL, y = "Warning operating characteristic",
       color = NULL, title = "Prediction-level support-map performance",
       subtitle = "Intervals are one-sided Bonferroni-adjusted Wilson bounds") +
  theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom")
ggsave(file.path(FIG, "fig3-support-map.png"), p3,
       width = 11, height = 8, dpi = 200)
message("figures written to ", FIG)
