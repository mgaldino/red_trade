# Verification of an algebraic claim against stored inputs; no model fitting.
.libPaths(c("renv/library/macos/R-4.4/aarch64-apple-darwin20", .libPaths()))
gpi <- targets::tar_read(gpi_data)
panel <- targets::tar_read(synth_data)
raw <- dplyr::inner_join(
  dplyr::select(panel, iso3c, year),
  dplyr::select(gpi, iso3c, year, gpi, us_power, us_power_gap),
  by = c("iso3c", "year")
)
cat("Stored comparison panel rows:", nrow(raw), "\n")
cat("Country power above US:", sum(raw$gpi > raw$us_power, na.rm = TRUE), "\n")
cat("Maximum absolute residual of signed identity:",
    max(abs(raw$us_power_gap - (raw$us_power - raw$gpi)), na.rm = TRUE), "\n")
cat("Country-years violating signed identity:\n")
print(dplyr::filter(raw, abs(us_power_gap - (us_power - gpi)) > 1e-10))
cat("This check does not estimate the separate partial effect of any covariate.\n")
