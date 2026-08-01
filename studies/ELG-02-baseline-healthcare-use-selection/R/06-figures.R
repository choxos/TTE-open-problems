## Study ELG-02: figures for mechanism, policy, screen, and target shift.
##
##   Rscript R/06-figures.R

.file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
STUDY <- if (length(.file_arg)) {
  dirname(dirname(normalizePath(sub("^--file=", "", .file_arg[1]))))
} else normalizePath(".")
here <- function(...) file.path(STUDY, ...)

suppressPackageStartupMessages(library(ggplot2))
source(here("R", "00-config.R"))

OUT <- here("results")
FIG <- here("out")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

bias <- utils::read.csv(file.path(OUT, "bias-bounds.csv"))
primary <- utils::read.csv(file.path(OUT, "primary-policy.csv"))
screen <- utils::read.csv(file.path(OUT, "screen-performance.csv"))
shift <- utils::read.csv(file.path(OUT, "target-shift.csv"))

bias$retention_label <- paste0("Pr(H = 1) = ", bias$retention)
p1 <- ggplot(
  bias[bias$topology != "noncollider", ],
  aes(x = factor(strength), y = abs_bias, color = topology, group = topology)
) +
  geom_hline(yintercept = c(NEGLIGIBLE_BIAS, MATERIAL_BIAS),
             linetype = c("dotted", "dashed"), color = "grey45") +
  geom_errorbar(aes(ymin = abs_bias_lo, ymax = abs_bias_hi),
                width = 0.08, position = position_dodge(width = 0.25)) +
  geom_point(position = position_dodge(width = 0.25), size = 2) +
  facet_wrap(~ retention_label) +
  labs(
    x = "Eligibility-edge strength", y = "Absolute Monte Carlo bias",
    color = "Collider orientation",
    title = "Bias from minimal adjustment after collider selection",
    subtitle = "Intervals are replicate bootstrap intervals; horizontal lines are decision thresholds."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig1-minimal-bias.png"), p1, width = 9, height = 5.5, dpi = 200)

primary$retention_label <- paste0("Pr(H = 1) = ", primary$retention)
p2 <- ggplot(
  primary[primary$topology != "noncollider", ],
  aes(x = factor(strength), y = benefit, color = topology, group = topology)
) +
  geom_hline(yintercept = 0, color = "grey35") +
  geom_hline(yintercept = POLICY_BENEFIT, linetype = "dashed", color = "grey45") +
  geom_errorbar(aes(ymin = benefit_lo, ymax = benefit_hi),
                width = 0.08, position = position_dodge(width = 0.25)) +
  geom_point(position = position_dodge(width = 0.25), size = 1.8) +
  facet_grid(view ~ retention_label) +
  labs(
    x = "Eligibility-edge strength",
    y = "Absolute-bias reduction: minimal minus policy",
    color = "Collider orientation",
    title = "Unconditional performance of the complete advisory policy",
    subtitle = "Positive values favor the policy. The dashed line is the 0.005 benefit threshold."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig2-policy-benefit.png"), p2, width = 10, height = 7, dpi = 200)

screen$retention_label <- paste0("Pr(H = 1) = ", screen$retention)
p3 <- ggplot(
  screen,
  aes(x = factor(strength), y = warning, color = topology, group = topology)
) +
  geom_errorbar(aes(ymin = warning_lo, ymax = warning_hi),
                width = 0.08, position = position_dodge(width = 0.25)) +
  geom_point(position = position_dodge(width = 0.25), size = 1.8) +
  facet_grid(view ~ retention_label) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent_format()) +
  labs(
    x = "Eligibility-edge strength", y = "Collider-candidate probability",
    color = "Eligibility topology",
    title = "Operating characteristics of the measured-variable screen",
    subtitle = "Intervals are Wilson 95 percent intervals. Reduced-view misses are silent errors."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig3-screen.png"), p3, width = 10, height = 7, dpi = 200)

shift_long <- rbind(
  data.frame(shift[, c("scenario", "topology", "strength", "retention")],
             variable = "B", contribution = shift$contribution_b),
  data.frame(shift[, c("scenario", "topology", "strength", "retention")],
             variable = "X", contribution = shift$contribution_x),
  data.frame(shift[, c("scenario", "topology", "strength", "retention")],
             variable = "D", contribution = shift$contribution_d)
)
shift_long$retention_label <- paste0("Pr(H = 1) = ", shift_long$retention)
p4 <- ggplot(
  shift_long,
  aes(x = factor(strength), y = contribution, fill = variable)
) +
  geom_hline(yintercept = 0, color = "grey35") +
  geom_col(position = "stack") +
  facet_grid(topology ~ retention_label) +
  labs(
    x = "Eligibility-edge strength",
    y = "Order-averaged contribution to RD_H minus RD_all",
    fill = "Variable",
    title = "Target-population shift on the risk-difference scale",
    subtitle = "The D contribution is an oracle diagnostic in the reduced information view."
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig4-target-shift.png"), p4, width = 10, height = 8, dpi = 200)

message("figures written to ", FIG)
