# Read-only verification of existing evidence; no estimation or targets calls.
d <- readRDS('_targets/objects/synth_data')
timing <- read.csv('data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/timing_placebos.csv')
for (i in seq_len(nrow(timing))) {
  y <- timing$nominal_treatment_year[i]; end <- timing$year_end[i]
  x <- d[d$year >= 1997 & d$year <= end, ]
  stopifnot(!anyDuplicated(x[c('iso3c','year')]), !anyNA(x[c('iso3c','year','abs_distance_china')]), length(unique(table(x$iso3c))) == 1)
  cat(sprintf('onset=%d window=1997-%d pre=1997-%d post=%d-%d horizon=%d units=%d donors=%d rows=%d\n', y,end,y-1,y,end,end-y+1,length(unique(x$iso3c)),length(unique(x$iso3c))-1,nrow(x)))
}
p <- 'data/processed/diagnostics/ungadm_outcome_robustness/postreview/'
g <- read.csv(paste0(p,'ife_2x2_fixed_r.csv'))
b <- read.csv(paste0(p,'ife_paired_bootstrap_draws.csv'))
s <- read.csv(paste0(p,'ife_paired_bootstrap_summary.csv'))
stopifnot(nrow(g)==4, all(g$n_obs==4727), all(g$nboots==10000), !any(g$smoke_test), nrow(b)==1000, !anyDuplicated(b$b), all(b$status=='ok'))
stopifnot(max(abs(b$diff_procedure-(b$att_dm_r1-b$att_bsv_r2)))<1e-12, max(abs(b$diff_common_r2-(b$att_dm_r2-b$att_bsv_r2)))<1e-12)
att <- function(o,r) g$att[g$outcome==o & g$r_fixed==r]
cat(sprintf('Existing 2x2 arithmetic: BSV r2-r1=%.12f; DM r2-r1=%.12f; difference of these contrasts=%.12f (descriptive, no interaction test)\n',att('BSV',2)-att('BSV',1),att('UNGA-DM',2)-att('UNGA-DM',1),(att('UNGA-DM',2)-att('UNGA-DM',1))-(att('BSV',2)-att('BSV',1))))
for(i in 1:2) {
  v <- b[[c('diff_procedure','diff_common_r2')[i]]]
  obs <- att('UNGA-DM',c(1,2)[i])-att('BSV',2)
  vals <- c(obs, mean(v), sd(v), unname(quantile(v,c(.025,.975))), 2*min(mean(v<=0),mean(v>=0)), 2*pnorm(-abs(obs/sd(v))))
  stored <- unlist(s[i,c('observed_diff','boot_mean','boot_sd','ci_2_5','ci_97_5','p_two_sided_percentile','p_two_sided_normal')],use.names=FALSE)
  stopifnot(max(abs(vals-stored))<1e-12, s$n_valid[i]==1000, s$n_failed[i]==0)
  cat(sprintf('paired row %d PASS max discrepancy %.3g; diff %.12f; percentile p %.3f\n',i,max(abs(vals-stored)),obs,vals[6]))
}
cat('PASS: verification only; no model fits, resampling, standardization, data writes, or targets operations.\n')
