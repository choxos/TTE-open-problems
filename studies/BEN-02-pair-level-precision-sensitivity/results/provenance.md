# Provenance

R: R version 4.6.0 (2026-04-24)
Platform: aarch64-apple-darwin23
Running under: macOS Tahoe 26.5

## Packages

| package | version |
| --- | --- |
| base | 4.6.0 |
| stats | 4.6.0 |
| future | 1.70.0 |
| furrr | 0.4.0 |

## Run

- **study**: BEN-02 pair-level precision sensitivity
- **structural_scenarios**: 16
- **replicates_per_scenario**: 10000
- **precision_levels**: small, medium, large
- **trial_sizes**: 500, 2500, 25000
- **emulation_sizes**: 5000, 25000, 250000
- **master_seed**: 20260801
- **primary_delta**: 0.02
- **bootstrap_resamples**: 20000
- **sceptical_source**: Köppe et al. 2025, BMC Medical Research Methodology, DOI 10.1186/s12874-025-02589-z
- **sceptical_locator**: Methods section, equation defining the sceptical z-value and two-sided sceptical p-value
- **sceptical_equation**: zS^2=(zo^2+zr^2)/2-sqrt(((zo^2-zr^2)/2)^2+c); c=se_o^2/se_r^2; pS=2*Phi(-zS)

