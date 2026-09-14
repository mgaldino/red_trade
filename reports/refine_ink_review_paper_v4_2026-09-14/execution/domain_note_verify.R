# Item 25: arithmetic verification of archived evidence only; no model fitting.
# Run from repository root with Rscript --vanilla. Output goes to stdout only.
options(encoding = "UTF-8")
rev_dir <- "quality_reports/revisions/paper_v4/20260905_RIO_selected_fixes/independent_ddd_checks"
src_dir <- "data/processed/diagnostics/RIO_20260905_ddd"
s <- read.csv(file.path(rev_dir, "sensitivity.csv"))
f <- read.csv(file.path(rev_dir, "fwl.csv"))
w <- read.csv(file.path(rev_dir, "country_domain_weights.csv"))
t <- read.csv(file.path(rev_dir, "donor_domain_restriction.csv"))
b <- readRDS(file.path(src_dir, "corrected_ddd_bundle.rds"))
d <- readRDS(file.path(src_dir, "estimation_sample.rds"))
stopifnot(nrow(d) == 55190L, length(unique(d$iso3c)) == 95L,
          length(unique(d$rcid)) == 612L,
          !anyDuplicated(d[c("iso3c", "rcid")]),
          !anyNA(d[c("iso3c", "rcid", "human_rights_binary", "distance_china_minus_usa")]))
cat("Archived sample: 55190 rows, 95 countries, 612 resolutions; keys unique; required fields complete.\n")
for (y in unique(s$outcome)) {
  a <- s[s$outcome == y & s$specification == "corrected", ]
  c <- s[s$outcome == y & s$specification == "country_domain", ]
  v <- b$ddd_models[b$ddd_models$outcome == y & b$ddd_models$term == "brazil_post_hr" &
      grepl("country-clustered", b$ddd_models$model), ]
  stopifnot(nrow(a) == 1L, nrow(c) == 1L, nrow(v) == 1L,
            abs(a$estimate - v$estimate) < 1e-10, a$nobs == c$nobs)
  cat(sprintf("%s: archived current %.12f; country-domain %.12f; difference %.12f; relative absolute change %.6f%%; matches consumed RDS.\n",
              y, a$estimate, c$estimate, c$estimate - a$estimate,
              100 * abs((c$estimate - a$estimate) / a$estimate)))
}
stopifnot(max(abs(f$estimate - f$independent_fwl)) < 1e-9)
sum_abs <- sum(abs(w$sum_w[w$human_rights_binary == 1L]))
stopifnot(abs(sum_abs - t$sum_abs_country_hr_weights) < 1e-12,
          abs(sum_abs - t$corrected_coefficient) < 1e-9,
          abs(t$country_domain_coefficient) < 1e-9)
cat(sprintf("Archived FWL identity max discrepancy %.12g; archived absolute HR country-weight sum %.12f; synthetic counterexample %.12f.\n",
            max(abs(f$estimate - f$independent_fwl)), sum_abs, t$corrected_coefficient))
cat("PASS: read-only arithmetic and integrity checks; no regression, new FE, placebo, targets execution, or data writes.\n")
