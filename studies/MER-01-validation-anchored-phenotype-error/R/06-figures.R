## Study 2 (MER-01): figures.

.f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.f)) dirname(dirname(normalizePath(sub("^--file=", "", .f[1])))) else
  normalizePath(".")
here <- function(...) file.path(STUDY, ...)
suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
perf <- utils::read.csv(file.path(OUT, "performance.csv"), stringsAsFactors = FALSE)
interactions <- utils::read.csv(file.path(OUT, "interactions.csv"), stringsAsFactors = FALSE)
qualification <- utils::read.csv(file.path(OUT, "correction-qualification.csv"), stringsAsFactors = FALSE)

## Figure 1 shows the eight decisive nonaligned joint-error cells. Vertical
## intervals are simultaneous Monte Carlo intervals for signed bias.
d <- perf[perf$decision_cell & perf$estimand == "dynamic" &
            perf$analysis_pattern == "AL" &
            perf$method %in% c("first_order", "rich", "exact_filter", "corrected", "oracle"), ]
d$cell <- paste(d$profile, sprintf("accuracy %.2f", d$accuracy), sep = "\n")
p1 <- ggplot(d, aes(x = method, y = bias, ymin = bias_lo, ymax = bias_hi,
                    colour = method)) +
  geom_hline(yintercept = c(-DECISION$negligible_bias, DECISION$negligible_bias),
             linetype = 2, colour = "grey45") +
  geom_pointrange(position = position_dodge(width = 0.4)) +
  facet_wrap(~ cell, ncol = 4L) +
  coord_flip() +
  labs(x = NULL, y = "Bias in the dynamic-strategy risk difference",
       title = "Longitudinal phenotype error in the decisive cells",
       subtitle = "Intervals use the prespecified simultaneous Monte Carlo procedure") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none", panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig1-decisive-bias.png"), p1, width = 12, height = 7, dpi = 200)

## Figure 2 separates the paired A-L interaction from total joint-error bias.
i <- interactions[interactions$method %in% c("exact_filter", "rich"), ]
i$cell <- paste(i$profile, sprintf("accuracy %.2f", i$accuracy), sep = "\n")
p2 <- ggplot(i, aes(x = method, y = interaction,
                    ymin = interaction_lo, ymax = interaction_hi,
                    colour = method)) +
  geom_hline(yintercept = c(-DECISION$interaction_equivalence,
                            DECISION$interaction_equivalence),
             linetype = 2, colour = "grey45") +
  geom_pointrange() +
  facet_wrap(~ cell, ncol = 4L) +
  coord_flip() +
  labs(x = NULL, y = expression(B[AL] - B[A] - B[L] + B[0]),
       title = "Paired nonadditivity of treatment and confounder error") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none", panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig2-error-interaction.png"), p2, width = 12, height = 6, dpi = 200)

## Figure 3 reports correction performance across both benchmark mechanisms and
## every one-at-a-time misspecification regime.
if (nrow(qualification)) {
  qualification$mechanism <- ifelse(
    qualification$benchmark == "nondifferential_070",
    "Nondifferential, accuracy 0.70", "Unrelated X3, accuracy 0.85")
  p3 <- ggplot(qualification,
               aes(x = factor(validation_n), y = bias_gain,
                   ymin = bias_gain_lo, ymax = bias_gain_hi,
                   colour = specification, group = specification)) +
    geom_hline(yintercept = 0, linetype = 2, colour = "grey45") +
    geom_pointrange(position = position_dodge(width = 0.45)) +
    facet_wrap(~ mechanism) +
    labs(x = "Internal validation sample size",
         y = expression(abs(B[corrected]) - 0.5 * abs(B[rich])),
         colour = "Correction model",
         title = "When is latent-state correction worth its variance cost?") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank())
  ggsave(file.path(FIG, "fig3-validation-size.png"), p3,
         width = 11, height = 6, dpi = 200)
}
message("figures written to ", FIG)
