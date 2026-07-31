## Study 1 (CNF-01): figures.
##
##   Rscript R/06-figures.R
##
## Two figures, one per aim. The second is the one the study exists to produce.

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

att <- utils::read.csv(file.path(OUT, "attenuation.csv"))
pairs <- utils::read.csv(file.path(OUT, "matched-pairs.csv"))

lab_persist <- c(transient = "effect only while treated",
                 legacy = "effect ramps in and persists")
lab_prog <- c(neutral = "initiation independent of risk",
              prognostic = "high-risk patients initiate first")

## ---- Figure 1. Attenuation against horizon -------------------------------
## Aim A1. What the entry already says, drawn: the ITT-analogue loses a growing
## share of the sustained-strategy effect as the horizon lengthens.
att$facet <- lab_persist[att$persistence]
p1 <- ggplot(att, aes(x = horizon, y = attenuation,
                      colour = factor(target_c120), linetype = shape,
                      group = interaction(target_c120, shape, alpha_l_key))) +
  geom_line(linewidth = 0.6) +
  facet_grid(lab_prog[alpha_l_key] ~ facet) +
  scale_x_continuous(breaks = HORIZONS) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Follow-up horizon (months)",
       y = "Share of the sustained-strategy effect removed by convergence",
       colour = "Cumulative initiation\nin the comparator arm\nby month 120",
       linetype = "Timing of initiation",
       title = "Attenuation of the intention-to-treat analogue",
       subtitle = "Each line is one scenario. Attenuation is enumerated from the mechanism, not estimated.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right", panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig1-attenuation.png"), p1, width = 10, height = 6, dpi = 200)

## ---- Figure 2. The decisive comparison -----------------------------------
## Aim A2. Each pair of points shares a cumulative initiation at month 120 and
## differs only in when the initiation happened. If the diagnostic were
## sufficient, the pairs would coincide.
pairs$facet <- lab_persist[pairs$persistence]
long <- rbind(
  data.frame(pairs[, c("target_c120", "alpha_l_key", "persistence", "horizon", "facet")],
             shape = "early", attenuation = pairs$attenuation_early,
             c_obs = pairs$c_obs_early),
  data.frame(pairs[, c("target_c120", "alpha_l_key", "persistence", "horizon", "facet")],
             shape = "late", attenuation = pairs$attenuation_late,
             c_obs = pairs$c_obs_late))

p2 <- ggplot(long, aes(x = c_obs, y = attenuation, colour = shape)) +
  geom_line(aes(group = interaction(target_c120, alpha_l_key, shape)),
            linewidth = 0.5, alpha = 0.8) +
  geom_point(size = 1.4) +
  facet_grid(lab_prog[alpha_l_key] ~ facet) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x = "Cumulative initiation in the comparator arm, as an author would report it",
       y = "Attenuation",
       colour = "Timing of initiation",
       title = "Does the reported diagnostic determine the attenuation?",
       subtitle = "If it did, the two timing curves would lie on top of each other.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right", panel.grid.minor = element_blank())
ggsave(file.path(FIG, "fig2-diagnostic.png"), p2, width = 10, height = 6, dpi = 200)

message("figures written to ", FIG)
