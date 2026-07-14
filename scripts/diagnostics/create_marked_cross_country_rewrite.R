source_file <- "paper_v4.Rmd"
out_file <- "paper_v4_cross_country_rewrite_marked.Rmd"
map_file <- file.path("quality_reports", "2026-05-17_cross_country_rewrite_line_map.md")

original <- readLines(source_file, warn = FALSE, encoding = "UTF-8")
edited <- original
changes <- data.frame(
  label = character(),
  old_start = integer(),
  old_end = integer(),
  action = character(),
  stringsAsFactors = FALSE
)

as_lines <- function(txt) {
  strsplit(txt, "\n", fixed = TRUE)[[1]]
}

find_one <- function(x, pattern, label, start_after = 0L) {
  idx <- grep(pattern, x, perl = TRUE)
  idx <- idx[idx > start_after]
  if (length(idx) != 1L) {
    stop(sprintf("Expected one match for '%s', found %d", label, length(idx)))
  }
  idx
}

find_next <- function(x, pattern, label, start_after) {
  idx <- grep(pattern, x, perl = TRUE)
  idx <- idx[idx > start_after]
  if (length(idx) < 1L) {
    stop(sprintf("Expected at least one later match for '%s', found 0", label))
  }
  idx[[1]]
}

record_change <- function(label, old_start, old_end, action) {
  changes <<- rbind(
    changes,
    data.frame(
      label = label,
      old_start = old_start,
      old_end = old_end,
      action = action,
      stringsAsFactors = FALSE
    )
  )
}

md_begin_marker <- function(label, old_start, old_end) {
  c(
    sprintf(
      "> **[inicio da proposta - substitui paper_v4.Rmd linhas %d-%d: %s]**",
      old_start, old_end, label
    ),
    ""
  )
}

md_end_marker <- function() {
  c("", "> **[fim da proposta]**")
}

comment_begin_marker <- function(label, old_start, old_end, prefix = "#") {
  sprintf(
    "%s [inicio da proposta - substitui paper_v4.Rmd linhas %d-%d: %s]",
    prefix, old_start, old_end, label
  )
}

comment_end_marker <- function(prefix = "#") {
  sprintf("%s [fim da proposta]", prefix)
}

replace_line <- function(pattern, replacement, label, prefix = NULL) {
  old_idx <- find_one(original, pattern, label)
  cur_idx <- find_one(edited, pattern, label)
  repl <- as_lines(replacement)
  if (!is.null(prefix)) {
    repl <- c(
      comment_begin_marker(label, old_idx, old_idx, prefix),
      repl,
      comment_end_marker(prefix)
    )
  } else {
    repl <- c(md_begin_marker(label, old_idx, old_idx), repl, md_end_marker())
  }
  edited <<- c(edited[seq_len(cur_idx - 1L)], repl, edited[seq(cur_idx + 1L, length(edited))])
  record_change(label, old_idx, old_idx, "replace line")
}

replace_block <- function(start_pattern, end_pattern, replacement, label) {
  old_start <- find_one(original, start_pattern, label)
  old_end_next <- find_next(original, end_pattern, paste0(label, " end"), old_start)
  old_end <- old_end_next - 1L

  cur_start <- find_one(edited, start_pattern, label)
  cur_end_next <- find_next(edited, end_pattern, paste0(label, " end"), cur_start)
  cur_end <- cur_end_next - 1L

  repl <- c(md_begin_marker(label, old_start, old_end), as_lines(replacement), md_end_marker(), "")
  before <- if (cur_start > 1L) edited[seq_len(cur_start - 1L)] else character()
  after <- if (cur_end < length(edited)) edited[seq(cur_end + 1L, length(edited))] else character()
  edited <<- c(before, repl, after)
  record_change(label, old_start, old_end, "replace block")
}

replace_chunk <- function(start_pattern, replacement, label) {
  old_start <- find_one(original, start_pattern, label)
  old_end <- find_next(original, "^```$", paste0(label, " end"), old_start)

  cur_start <- find_one(edited, start_pattern, label)
  cur_end <- find_next(edited, "^```$", paste0(label, " end"), cur_start)

  repl <- c(md_begin_marker(label, old_start, old_end), as_lines(replacement), md_end_marker(), "")
  before <- if (cur_start > 1L) edited[seq_len(cur_start - 1L)] else character()
  after <- if (cur_end < length(edited)) edited[seq(cur_end + 1L, length(edited))] else character()
  edited <<- c(before, repl, after)
  record_change(label, old_start, old_end, "replace chunk")
}

abstract_text <- r"(abstract: "\\singlespacing  How do trade-based status gains affect foreign policy alignment? Existing IR research emphasizes status anxiety and status seeking, but pays less attention to the foreign-policy consequences of upward status shifts. We argue that when a rising major power moves to the top of a country's trade hierarchy, becoming its largest export destination, this status upgrade creates a salient cue that can reshape diplomatic alignment beyond what smooth exposure models predict. The effect should be especially strong when the displaced number-one partner is the hegemon and strategic rival of the rising power. Brazil is a high-salience case of this same treatment: in 2009, China overtook the United States as Brazil's top trade partner after roughly eight decades of US primacy. Using Synthetic Difference-in-Differences on UNGA ideal-point distance, we estimate a statistically significant 41% average post-2009 reduction in Brazil's ideological distance to China relative to the synthetic counterfactual (p = 0.032). To probe the mechanism, we analyze Brazilian newspaper coverage and find evidence consistent with a post-2009 increase in China-related and trade-focused salience. We then estimate the same treatment in a cross-country panel: treatment begins when China becomes a country's largest export destination and remains on while China holds that position. Using a counterfactual estimator with interactive fixed effects, with the number of latent factors selected by cross-validation, we read the panel as an external-validity and scope-condition probe of the same top-partner treatment, while Brazil represents the theoretically strongest hegemonic-rival replacement case. The results suggest that ordinal milestones in economic relationships can shape foreign-policy behavior, especially when they signal a rising power's displacement of an incumbent hegemon.")"
replace_line("^abstract:", abstract_text, "abstract revisado", "#")

treat_def_panel_text <- r"(treat_def_panel <- "Treatment indicator equals 1 in country-years in which China, the rising major power studied here, is the country's largest export destination and 0 otherwise; treatment turns off when another partner overtakes China")"
replace_line("^treat_def_panel <-", treat_def_panel_text, "definicao global do tratamento cross-country", "#")

research_question_text <- r"(When a rising major power becomes a country's top trade partner, does that status change induce foreign-policy realignment beyond what continuous trade exposure predicts? And is the effect stronger when the displaced number-one partner is the hegemon and strategic rival of the rising power?)"
replace_line("^When a rising major power becomes a country's top trade partner", research_question_text, "pergunta de pesquisa", NULL)

intro_block <- r"(We argue that foreign-policy realignment can follow from a discrete status change in the trade hierarchy: a rising major power becomes a country's top trade partner. This is not only a change in commercial exposure. It is also a categorical upgrade from important partner to number-one partner, a status cue that can attract attention, legitimize policy adjustment, and make alignment with the rising power more politically usable. The cue can arrive abruptly, but the policy response need not be a one-year jump: diplomatic positions are embedded in prior votes, bureaucratic routines, coalition commitments, and reputational costs, so governments may adjust gradually as the new status category becomes politically usable.

The same treatment organizes both empirical designs in the paper: China becomes the country's top trade partner, operationalized in the cross-country data as China becoming the largest export destination. What varies is the scope condition under which the treatment occurs. The effect should be stronger when the displaced number-one partner is not just any incumbent, but the hegemon and strategic rival of the rising power. In that setting, the rank reversal carries greater symbolic and geopolitical content: it signals not only that China has become commercially central, but also that the United States has lost a privileged position.

Brazil is the most-likely and theoretically strongest case of this treatment. The United States had been Brazil's leading trade partner for roughly eight decades before China displaced it in 2009. Brazil also has an active press, which allows us to observe the salience channel, and is a regional power, making a purely coercive explanation less plausible. The Brazilian design therefore estimates the same top-partner transition as the panel, but under the scope condition where the theory predicts the largest effect.

To credibly show that the overtaking of the US by China as Brazil's top trade partner has a causal effect on Brazil's foreign policy orientation, we use a synthetic difference-in-differences approach. We measure the outcome as the absolute distance in UNGA ideal point estimation [@bailey_etal2017] between Brazil and China over 1997-2015. The SDiD point estimate corresponds to an estimated `r sprintf('%.1f', perc_change)`% average reduction in Brazil's ideological distance from China over the post-2009 period relative to the synthetic counterfactual. It is not an estimate of a visual discontinuity or of the one-year change in 2009.

Second, we estimate the same treatment in a cross-country panel. Treatment begins when China becomes a country's largest export destination and remains on while China holds that position. The pooled panel ATT is therefore an average effect of China entering and holding the top trade position across cases with different levels of geopolitical salience. It should not be expected to equal the Brazilian estimate: Brazil is a high-salience hegemonic-rival replacement case, while the panel also includes lower-salience cases where the displaced incumbent is not the United States or was less entrenched.

To probe mechanism implications, we analyze Brazilian newspaper coverage and show that China and China-Brazil trade became more salient after the 2009 rank reversal. This media evidence speaks directly to the Brazilian case. In the cross-country panel, the mechanism is interpreted more cautiously: the evidence is consistent with a rank/status mechanism, but does not directly measure salience in each country.

We also inspect Brazil-China roll-call votes at the resolution level to make the aggregate UNGA movement less abstract. This diagnostic clarifies where there was room for additional convergence after 2009 and gives concrete content to what changed in Brazilian foreign policy at the UNGA.

This study provides evidence that a rising major power's move to the top of a trade hierarchy can produce foreign-policy realignment under high-salience scope conditions, with the strongest mechanism evidence coming from Brazil and the cross-country panel serving as a broader probe of the same treatment. Residual endogeneity from shared structural features of commodity-exporting economies cannot be entirely ruled out, and the pooled panel estimates should be interpreted cautiously when they are imprecise under cross-validated IFE. The study questions the idea in the literature that status gains are mostly illusory [@mercer_2017]. It also has broad implications for the study of economic ties with an emerging power. Similar status-change effects may also shape how other economic variables, such as foreign direct investment, aid, and loans, affect foreign-policy behavior.)"
replace_block("^We argue that discrete status change", "^# Trade, Status, and Political Alignment", intro_block, "bloco empirico da introducao")

microfoundation_text <- r"(The micro-foundation for why rank matters comes from coarse categorization -- the tendency to rely on broad, easily processed bins rather than fine-grained metrics when confronting complexity [@graeber_etal2025; @enke2024]. Actors -- media editors, policymakers, business leaders -- can track continuous trade shares, but they also attend to categories such as "largest export market" or "top trade partner." The relevant cognitive shift is from an incumbent number-one partner category to a new "China = top trade partner" category. This reclassification does not necessarily provide new information about trade volumes; those data accumulate continuously. What it provides is a categorical cue that can organize attention, public interpretation, and elite coordination. The cue should be most salient when the new top partner is a rising major power and the displaced incumbent is politically prominent, long-entrenched, hegemonic, or strategically opposed to the rising power. The Brazilian case, where China displaced the United States after roughly eight decades, is therefore the strongest scope condition for the same top-partner treatment.)"
replace_line("^The micro-foundation for why rank matters", microfoundation_text, "microfundacao mais geral de rank/status", NULL)

limits_text <- r"(We are explicit about the limits of our design. The Brazilian SDiD and the cross-country panel estimate the same theoretical treatment: China becomes and holds the top trade-partner position. The Brazilian SDiD estimates this treatment under the strongest scope condition, where the displaced incumbent is the United States. The NLP media analysis provides suggestive evidence for the attention claim in Brazil. The cross-country analysis estimates the average effect of the same status transition across broader scope conditions, conditional on the counterfactual model. It does not directly identify media salience or elite response in every country. We therefore treat the panel as evidence on the average top-partner treatment effect, while reserving direct mechanism evidence for the Brazilian case.)"
replace_line("^We are explicit about the limits of our design", limits_text, "limites da identificacao e do mecanismo", NULL)

hypotheses_block <- r"(## Hypotheses

From the theoretical building blocks above, we derive four expectations.

Hypothesis 1 (Top-partner status): When China becomes a country's top trade partner, operationalized as its largest export destination, that country's UNGA ideal-point distance to China decreases relative to its counterfactual path. This is the main treatment in both the Brazilian SDiD and the cross-country panel.

Hypothesis 2 (Hegemonic-rival replacement): The top-partner effect should be stronger when China replaces the United States as the number-one partner. Displacing the hegemon and strategic rival of the rising power makes the status change more visible, more politically meaningful, and more likely to alter the domestic and diplomatic interpretation of the trade relationship.

Hypothesis 3 (Media salience): In cases where the rank reversal becomes publicly visible, media coverage of China and of the bilateral trade relationship should increase around the reversal. We test this implication directly in the Brazilian case.

Hypothesis 4 (Temporal dynamics): The alignment response may build gradually after China enters the top rank and should attenuate when China loses that position. Salience is temporary, while foreign-policy adjustment is constrained by diplomatic inertia and prior commitments.

## Scope Conditions

The treatment is the same across designs: China becomes and holds the top trade-partner position. What changes is the scope condition under which the treatment occurs. The status-salience mechanism should be strongest when the displaced partner is the United States, when the prior top-partner relationship was long-entrenched, and when media institutions can amplify the rank reversal. The Brazilian case satisfies these conditions unusually well: the displaced partner was the United States, the prior relationship was historically long, and the press environment allows the attention channel to be observed. The cross-country panel estimates the same top-partner treatment across a broader set of cases, so its pooled ATT averages over both high- and lower-salience settings.)"
replace_block("^## Hypotheses$", "^## Causal Framework$", hypotheses_block, "hipoteses e condicoes de escopo")

dag_text <- r"(text(0.24, 0.78, "China becomes\n#1 trade partner"))"
replace_line('text\\(0\\.24, 0\\.78, "Rank reversal\\\\n\\(China overtakes US\\)"\\)', dag_text, "rotulo do primeiro no do DAG", "#")

cross_country_block <- r"(## Cross-Country Design

The Brazilian SDiD and the cross-country panel estimate the same theoretical treatment: China becomes the country's top trade partner. In the cross-country data, we operationalize this status transition as China becoming the country's largest export destination. The purpose of the panel is therefore not to test a different treatment, but to estimate the same top-partner effect across a broader set of countries and scope conditions.

The cross-country treatment is reversible. Treatment begins in the first observed year in which China becomes a country's largest export destination and remains on only while China holds that position. If another partner later becomes the largest export destination, treatment returns to 0. This definition distinguishes the moment of entry into the top rank from the treated periods under China top trade-partner status. The resulting ATT should be interpreted as the average effect of treated country-years, not as a one-year discontinuity at the onset of treatment.

The theory predicts heterogeneity around this average. Cases in which China replaces the United States should exhibit larger effects because the displaced incumbent is the hegemon and strategic rival of the rising power. Brazil is one such high-salience case, and it also features unusually long prior US primacy. The pooled panel estimate, by contrast, averages over cases with varying displaced incumbents and therefore need not match the larger Brazilian estimate.

If the final operational rule restricts treatment onsets to observed reversals from 2000 onward, the text should say so explicitly: this is the period in which China's rise as an export market becomes substantively relevant and systematically observable in the panel. The restriction avoids treating countries as newly exposed when China already held the top position before the relevant window.

We estimate the counterfactual path using the `fect` estimator with interactive fixed effects [@liu2024practical]. The estimator uses untreated observations and pre-treatment data from treated units to impute untreated potential outcomes. The IFE specification relaxes strict parallel trends by allowing latent common factors to affect countries with different intensities. The number of latent factors is selected by cross-validation within the estimator and reported as an estimator output, rather than set ex ante. We estimate a baseline specification and a covariate-adjusted specification with log GDP per capita and press freedom.

To further investigate entry and exit dynamics, we complement `fect` with PanelMatch [@imai_kim_wang2023], a matching-based estimator for time-series cross-sectional data. Entry effects estimate what happens after China becomes the largest export destination; reversal effects estimate what happens after China loses that position. Because the number of observed exits is limited, these estimates are interpreted as diagnostic and descriptive rather than as the main source of inference.)"
replace_block("^## Cross-Country Design$", "^## Identification Assumptions and Diagnostics$", cross_country_block, "desenho cross-country")

identification_block <- r"(For the cross-country IFE design, identification requires strict exogeneity conditional on observed covariates and the latent factor structure. Substantively, the key concern is that China becoming the largest export destination may coincide with other time-varying changes that also shift UNGA alignment. The IFE model addresses part of this concern by allowing common shocks -- such as commodity cycles, global crises, or broad changes in China's economic role -- to affect countries with different intensities. This does not eliminate all threats: country-specific political realignments or commodity shocks that coincide with treatment onset remain possible.

We assess model adequacy via the diagnostic tests recommended by @liu2024practical. Placebo tests ask whether the model predicts pre-treatment outcomes well; carryover tests ask whether effects persist after treatment exits. Because statistical power is limited with few treated units, we rely on the equivalence logic emphasized by @liu2024practical and @chiu_etal2025: the equivalence test provides positive evidence that pre-treatment or carryover effects are substantively small, while the conventional test can only fail to reject their presence.

A reader might notice an asymmetry in the covariate sets between the two designs: the Brazilian SDiD includes a richer set of covariates, while the cross-country fect model includes log GDP per capita and press freedom. This asymmetry reflects the different roles covariates play in each estimator, not a difference in ambition. In SDiD, covariates enter the construction of synthetic-control weights and only need to be observed over the pre-treatment window. In fect IFE, covariates enter a regression adjustment that requires observations in every country-year of the switching panel; importing the full SDiD covariate set sharply reduces the sample. The retained covariates are those with near-complete coverage and clear theoretical relevance.

A second concern is that top export rank may capture material dependence rather than status salience. Both empirical designs estimate the same top-partner status transition, but the Brazilian design addresses the salience mechanism more directly through trade covariates, timing placebos, and media evidence. In the cross-country panel, we interpret the evidence more cautiously: it estimates the average effect of China holding top-partner status, but it does not fully separate ordinal rank from continuous export exposure in every country. We therefore report, where feasible, sensitivity specifications using pre-treatment or lagged measures of export exposure, while treating contemporaneous trade intensity as a potential post-treatment variable rather than a clean control.

It is important to note that mechanism analyses are interpreted as suggestive evidence, not as causally identified mechanisms.)"
replace_block("^For the cross-country IFE design", "^## Data and Variables$", identification_block, "identificacao cross-country e diagnosticos")

data_treatment_text <- r"(For the cross-country analysis, $D_{it}$ equals 1 in country-years in which China is the country's largest export destination, and 0 otherwise. This is the panel operationalization of the same treatment estimated in Brazil: China becomes the country's top trade partner. Countries enter treatment when China first becomes their largest export destination within the observed treatment-onset window. They leave treatment if another partner later becomes the largest export destination. This reversible treatment definition matches the theory's temporal implication: the political relevance of China's top-rank status should be strongest while China actually holds that position.)"
replace_line("^For the cross-country analysis, \\$D_\\{it\\}\\$ equals 1", data_treatment_text, "definicao de tratamento em Data and Variables", NULL)

cross_country_evidence_intro <- r"(# Cross-Country Evidence

The Brazilian case estimates the top-partner treatment under the strongest scope condition: China becomes Brazil's top trade partner by replacing the United States after a long period of US primacy. We now estimate the same treatment in a cross-country panel. The goal is not to introduce a different treatment, but to ask whether China's move into the number-one trade position is associated with foreign-policy realignment across a broader set of countries.

The main cross-country treatment begins when China becomes a country's largest export destination and remains on while China holds that position. This is the panel operationalization of the same theoretical status change: a rising major power becomes the country's top trade partner. The theory predicts that this average effect should be heterogeneous. It should be strongest when the displaced incumbent is the United States, because that case combines a top-partner status gain for China with the loss of privileged position by the hegemon and strategic rival of the rising power.

An important empirical feature of the cross-country sample is that treatment need not be absorbing. China can become the largest export destination and later lose that position. This switching pattern makes standard absorbing-treatment estimators inappropriate and motivates our use of the `fect` IFE estimator [@liu2024practical], which accommodates treatment switching. Consistent with H4, exit-aligned analyses ask whether the alignment effect attenuates when China no longer holds the top trade-partner position.)"
replace_block("^# Cross-Country Evidence$", "^```\\{r fect-results", cross_country_evidence_intro, "introducao da evidencia cross-country")

fect_results_block <- r"---(```{r fect-results, include=FALSE}
library(dplyr)

fect_ife_fit <- tar_read(fect_ife_china_top)
fect_fe_fit <- tar_read(fect_fe_china_top)
fect_carry_fit <- tar_read(fect_carryover_china_top)
sw_panel <- tar_read(china_top_fect_data)

ife_s <- fect_att_summary(fect_ife_fit)
fe_s <- fect_att_summary(fect_fe_fit)
china_top_s <- tar_read(fect_ife_china_top_summary)

fect_ife_cov_fit <- tar_read(fect_ife_china_top_cov)
ife_cov_s <- fect_att_summary(fect_ife_cov_fit)
china_top_cov_s <- tar_read(fect_ife_china_top_cov_summary)

att_cross <- china_top_s$att
se_cross <- china_top_s$se
p_cross <- china_top_s$p
r_cv <- china_top_s$r_cv

n_countries <- china_top_s$n_countries
n_treated_sw <- china_top_s$n_treated
n_control_sw <- china_top_s$n_control
panel_min <- china_top_s$panel_min
panel_max <- china_top_s$panel_max
n_absorbing <- NA_integer_
n_switching <- NA_integer_
att_rel_pct <- china_top_s$att_rel_pct

placebo_p <- if (!is.null(fect_fe_fit$test.out$placebo.p)) round(fect_fe_fit$test.out$placebo.p, 3) else NA
placebo_equiv_p <- if (!is.null(fect_fe_fit$test.out$placebo.equiv.p)) round(fect_fe_fit$test.out$placebo.equiv.p, 3) else NA
carryover_p <- if (!is.null(fect_carry_fit$test.out$carryover.p)) round(fect_carry_fit$test.out$carryover.p, 3) else NA
carryover_equiv_p <- if (!is.null(fect_carry_fit$test.out$carryover.equiv.p)) round(fect_carry_fit$test.out$carryover.equiv.p, 3) else NA
```)---"
replace_block("^```\\{r fect-results", "^## Main result \\(fect IFE\\)$", fect_results_block, "chunk de resultados fect cross-country")

main_result_block <- r"--(## Main cross-country result (fect IFE)

```{r fect-china-top-result-summaries, include=FALSE}
china_top_s <- tar_read(fect_ife_china_top_summary)
china_top_cov_s <- tar_read(fect_ife_china_top_cov_summary)
fmt3 <- function(x) sprintf("%.3f", unname(x))
fmt1 <- function(x) sprintf("%.1f", unname(x))
sig_sentence <- function(att, p) {
  direction <- ifelse(att < 0, "in the theoretically expected negative direction", "positive")
  if (is.na(p)) {
    "The statistical precision of this estimate is not available in the current target output."
  } else if (p < 0.05) {
    paste0("The estimate is ", direction, " and statistically distinguishable from zero at the 5% level.")
  } else {
    paste0("The estimate is ", direction, ", but the confidence interval includes zero; under the cross-validated pooled IFE specification, the average cross-country effect is not statistically distinguishable from zero.")
  }
}
china_top_window <- sprintf("%d--%d", china_top_s$panel_min, china_top_s$panel_max)
china_top_cov_window <- sprintf("%d--%d", china_top_cov_s$panel_min, china_top_cov_s$panel_max)
```

We construct a country-year panel to estimate the same treatment studied in Brazil: China becomes the country's top trade partner, operationalized as China becoming the largest export destination. Treatment begins when China enters the top position and remains on while China holds that position. The key distinction is between treatment entry -- the year in which China enters the top rank -- and treated periods, the country-years in which China continues to hold that status.

We estimate the ATT using the counterfactual estimator with interactive fixed effects (IFE) of @liu2024practical. Cross-validation selects the number of latent factors within `fect`; in the current target output, the baseline model selects $r^* = `r china_top_s$r_cv`$ factors. Negative estimates indicate that treated country-years are closer to China in UNGA ideal-point space than their estimated untreated counterfactuals.

The validated baseline panel contains `r china_top_s$n_obs` country-years from `r china_top_s$n_countries` countries over `r china_top_window`. China holds the top export-destination position in `r china_top_s$n_treated_country_years` country-years, across `r china_top_s$n_treated` ever-treated countries. There are `r china_top_s$n_entries` observed entries into treatment, `r china_top_s$n_exits` exits, and `r china_top_s$n_left_censored` left-censored treated unit already under treatment at the start of the panel.

The baseline ATT is `r fmt3(china_top_s$att)` (bootstrap SE = `r fmt3(china_top_s$se)`, 95% CI [`r fmt3(china_top_s$ci_lo)`, `r fmt3(china_top_s$ci_hi)`], p = `r fmt3(china_top_s$p)`). Substantively, this corresponds to about `r fmt1(china_top_s$att_rel_pct)`% of the pre-treatment mean distance to China, or `r fmt3(china_top_s$att_sd_units)` standard deviations of the outcome. `r sig_sentence(china_top_s$att, china_top_s$p)`

Column (2) adds log GDP per capita and press freedom. Because this specification uses complete cases for the covariates, the estimation sample changes to `r china_top_cov_s$n_obs` country-years from `r china_top_cov_s$n_countries` countries over `r china_top_cov_window`; it should therefore be described as a covariate-adjusted complete-case sample, not as the same balanced panel. Cross-validation selects $r^* = `r china_top_cov_s$r_cv`$ factors, and the ATT is `r fmt3(china_top_cov_s$att)` (bootstrap SE = `r fmt3(china_top_cov_s$se)`, 95% CI [`r fmt3(china_top_cov_s$ci_lo)`, `r fmt3(china_top_cov_s$ci_hi)`], p = `r fmt3(china_top_cov_s$p)`). `r sig_sentence(china_top_cov_s$att, china_top_cov_s$p)`

This result should be interpreted as the pooled cross-country estimate of the same top-partner treatment, averaged across heterogeneous scope conditions. The Brazilian SDiD is not a different treatment; it is the same treatment in the high-salience setting where China replaces the United States, the hegemon and strategic rival of the rising power. The theory therefore predicts that the Brazilian estimate may be larger than the pooled panel estimate. The cross-country section should be framed as an external-validity and scope-condition test of the top-partner mechanism, not as evidence that every top-partner transition is a statistically significant case of "replacing the United States.")--"
replace_block("^## Main result \\(fect IFE\\)$", "^```\\{r table-fect-specs", main_result_block, "resultado principal cross-country")

table_block <- r"---(```{r table-fect-specs, message=FALSE, warning=FALSE, echo=FALSE, results='asis'}
fmt <- function(x) formatC(round(x, 3), format = "f", digits = 3)
fmt_se <- function(x) paste0("(", fmt(x), ")")

china_top_s <- tar_read(fect_ife_china_top_summary)
china_top_cov_s <- tar_read(fect_ife_china_top_cov_summary)

tbl_rows <- data.frame(
  ` ` = c(
    "ATT", "",
    "p-value",
    "Treatment type",
    "N (country $\\times$ year)",
    "N (treated units)",
    "N (control units)",
    "Covariates",
    "Latent factors",
    "Panel window"
  ),
  `(1) fect IFE` = c(
    fmt(china_top_s$att), fmt_se(china_top_s$se),
    fmt(china_top_s$p),
    "Switching",
    as.character(china_top_s$n_obs),
    as.character(china_top_s$n_treated),
    as.character(china_top_s$n_control),
    "None",
    paste0("$r^* = ", china_top_s$r_cv, "$ (CV)"),
    paste0(china_top_s$panel_min, "--", china_top_s$panel_max)
  ),
  `(2) fect IFE` = c(
    fmt(china_top_cov_s$att), fmt_se(china_top_cov_s$se),
    fmt(china_top_cov_s$p),
    "Switching",
    as.character(china_top_cov_s$n_obs),
    as.character(china_top_cov_s$n_treated),
    as.character(china_top_cov_s$n_control),
    "log GDP pc, Free press",
    paste0("$r^* = ", china_top_cov_s$r_cv, "$ (CV)"),
    paste0(china_top_cov_s$panel_min, "--", china_top_cov_s$panel_max)
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

knitr::kable(
  tbl_rows,
  format   = "latex",
  escape   = FALSE,
  caption  = "Cross-country ATT estimates from the fect IFE specification for China top trade-partner status.",
  align    = c("l", "c", "c"),
  booktabs = TRUE,
  linesep  = ""
)

cat(
  "\n\n",
  caption_note(
    unit = "ATT in absolute UNGA ideal-point distance to China (points)",
    se = "bootstrap with 500 replications",
    cluster = "country level",
    window = sprintf("baseline panel covers %d--%d; covariate complete-case panel covers %d--%d",
                     china_top_s$panel_min, china_top_s$panel_max,
                     china_top_cov_s$panel_min, china_top_cov_s$panel_max),
    treatment = treat_def_panel
  ),
  "\n\n",
  sep = ""
)
```)---"
replace_block("^```\\{r table-fect-specs", "^Figure \\\\@ref\\(fig:plot-diagnostics\\) presents", table_block, "tabela principal cross-country")

diagnostics_text <- r"(Figure \@ref(fig:plot-diagnostics) presents the consolidated diagnostic tests following @liu2024practical. Panel (a) shows dynamic treatment effects relative to treatment entry into China top trade-partner status. Panel (b) displays the placebo test, which assesses whether the model correctly predicts pre-treatment outcomes; the conventional placebo p-value is `r placebo_p`, and the equivalence-test p-value is `r placebo_equiv_p`. Panel (c) shows the carryover test; the conventional carryover p-value is `r carryover_p`, and the equivalence-test p-value is `r carryover_equiv_p`. These diagnostics should be interpreted jointly as checks on pre-treatment fit, carryover, and substantive equivalence rather than as the main source of causal inference. The equivalence test plots are presented in the Appendix.)"
replace_line("^Figure \\\\@ref\\(fig:plot-diagnostics\\) presents", diagnostics_text, "interpretacao dos diagnosticos fect", NULL)

diagnostics_plot_chunk <- r"---(```{r plot-diagnostics, message=FALSE, warning=FALSE, echo=FALSE, fig.cap=paste0("Diagnostic tests for the cross-country fect analysis (Liu, Wang \\& Xu 2024). (a) IFE dynamic treatment effects; (b) FE placebo test with placebo periods in blue; (c) FE carryover test with carryover periods in red. ", caption_note(unit = "ATT in absolute UNGA ideal-point distance to China (points)", se = "bootstrap (500 replications)", window = sprintf("%d-%d panel", panel_min, panel_max), treatment = treat_def_panel)), fig.pos="H", fig.width=14, fig.height=5}
tar_read(plot_diagnostics_main_china_top)
```)---"
replace_chunk("^```\\{r plot-diagnostics", diagnostics_plot_chunk, "chunk de diagnosticos fect")

exit_intro <- r"(The exit-aligned analysis asks what happens when China loses the top trade-partner position. If the alignment effect is tied to current top-rank status, the effect should attenuate after China no longer holds that position. This is a test of reversibility in the same top-partner treatment, not a test that the United States specifically regains influence.)"
replace_line("^A distinctive advantage of the switching-treatment framework", exit_intro, "interpretacao de exit effects", NULL)

exit_caption <- r"---(```{r plot-fect-exit, message=FALSE, warning=FALSE, echo=FALSE, fig.cap=paste0("fect IFE: Exit-aligned gap plot showing what happens after China loses the largest-export-destination position. ", caption_note(unit = "ATT in absolute UNGA ideal-point distance to China (points)", se = "bootstrap (500 replications)", window = sprintf("%d-%d panel", panel_min, panel_max), treatment = treat_def_panel)), fig.pos="H", fig.width=7, fig.asp=0.65}
tar_read(plot_fect_ife_exit_china_top)
```)---"
replace_chunk("^```\\{r plot-fect-exit", exit_caption, "chunk do exit plot")

exit_after <- r"(The exit-aligned gap plot shows whether the treatment effect dissipates after China loses the top trade-partner position. This pattern is consistent with the salience mechanism (H4): unlike structural bandwagoning and coercion, which predict more persistent effects regardless of current trade status, the salience channel predicts that the effect is tied to the cognitive category "China = top trade partner" and should fade when that category is disrupted. We note that interest-based and trade-dependence theories may also predict reversible effects, so exit effects alone do not uniquely identify salience.)"
replace_line("^The exit-aligned gap plot shows", exit_after, "texto apos exit plot", NULL)

panelmatch_intro <- r"(PanelMatch provides a complementary matching-based view of entry and exit dynamics. Entry effects estimate what happens after China becomes the top trade partner; reversal effects estimate what happens after China loses that position. Because the number of observed exits is limited, these estimates are interpreted as diagnostic and descriptive rather than as the main source of inference.)"
replace_line("^We complement the fect analysis with PanelMatch", panelmatch_intro, "introducao PanelMatch", NULL)

panelmatch_results_chunk <- r"---(```{r panelmatch-results, include=FALSE}
pm_att <- tar_read(panelmatch_att_china_top)
pm_art <- tar_read(panelmatch_art_china_top)
pm_att_0 <- pm_att$summary_df[1, ]
pm_art_0 <- pm_art$summary_df[1, ]
```)---"
replace_chunk("^```\\{r panelmatch-results", panelmatch_results_chunk, "chunk de resultados PanelMatch")

panelmatch_caption <- r"---(```{r plot-panelmatch, message=FALSE, warning=FALSE, echo=FALSE, fig.cap=paste0("PanelMatch: Entry and exit effects of China top trade-partner status. ", caption_note(unit = "ATT/ART in absolute UNGA ideal-point distance to China (points)", se = "bootstrap (1000 iterations)", window = sprintf("%d-%d panel", panel_min, panel_max), treatment = treat_def_panel)), fig.pos="H", fig.width=7, fig.asp=0.8}
tar_read(plot_pm_combined_china_top)
```)---"
replace_chunk("^```\\{r plot-panelmatch", panelmatch_caption, "chunk PanelMatch")

panelmatch_after <- r"(The PanelMatch results are noisier than fect, as expected with matching-based inference on a small panel. The ATT estimates are small at lead 0 (`r sprintf('%.3f', pm_att_0$estimate)`) but become progressively negative at longer leads, consistent with a gradual alignment effect. The reversal estimate at lead 0 is `r sprintf('%.3f', pm_art_0$estimate)` (95% CI [`r sprintf('%.3f', pm_art_0$ci_lo)`, `r sprintf('%.3f', pm_art_0$ci_hi)`]), directionally consistent with countries moving away from China when China loses the top trade-partner position. The individual lead-level estimates are imprecise, so this evidence should be read as a diagnostic of temporal pattern rather than as the main estimate.)"
replace_line("^The PanelMatch results are noisier", panelmatch_after, "texto apos PanelMatch", NULL)

raw_intro <- r"(To provide transparency on the treated-country trajectories in the baseline estimation sample, we plot raw UNGA voting distance to China for countries with treated periods. Each panel marks periods in which China is the country's largest export destination.)"
replace_line("^To provide transparency on the treated countries driving", raw_intro, "introducao trajetorias brutas", NULL)

raw_caption <- r"---(```{r plot-treated-panel, message=FALSE, warning=FALSE, echo=FALSE, fig.cap=paste0("UNGA voting distance to China for countries with treated periods under China top trade-partner status. ", caption_note(unit = "absolute UNGA ideal-point distance to China (points)", window = "treated-country yearly series within the panel; treatment year varies by country", treatment = treat_def_panel)), fig.pos="H", fig.width=8, fig.height=8.5}
tar_read(plot_treated_panel_china_top)
```)---"
replace_chunk("^```\\{r plot-treated-panel", raw_caption, "chunk trajetorias brutas")

raw_after <- r"(The raw data reveal whether treated countries experienced lower ideological distance to China over treated periods, but the trajectories should not be read as uniform one-year breaks. They are useful for transparency and for identifying influential cases; causal interpretation comes from the counterfactual estimator.)"
replace_line("^The raw data reveal", raw_after, "texto apos trajetorias brutas", NULL)

dynamic_block <- r"(## Dynamic treatment effects and the temporality of the status effect

The dynamic treatment effects distinguish between entry into the top trade-partner position and subsequent treated periods. The theory predicts that entry should create the salient status cue, while the policy response may accumulate over subsequent years. The ATT therefore summarizes periods under China top trade-partner status rather than a single-year discontinuity at entry.

If the mechanism is status salience rather than a permanent structural shift, effects should attenuate when China loses the top rank. The exit-aligned analysis provides a more direct test of this temporality than the entry-aligned event study alone. The Brazilian case already hinted at attenuation because the raw UNGA distance data rebound after 2015, but the single-case design could not distinguish this from idiosyncratic noise. The cross-country exit effects ask whether that rebound pattern is systematic across treated countries.)"
replace_block("^## Dynamic treatment effects and the temporality of the status effect$", "^## Non-US Displacement Comparison$", dynamic_block, "dinamica temporal")

scope_header <- r"(## Scope Conditions: Hegemonic-Rival Replacement)"
replace_line("^## Non-US Displacement Comparison$", scope_header, "novo titulo para probes de escopo", NULL)

scope_text <- r"(The main treatment is China becoming the top trade partner. US displacement is therefore not a separate treatment; it is the most important scope condition for treatment intensity. The theory predicts larger effects when China replaces the United States because the displaced incumbent is the hegemon and strategic rival of the rising power. If the data permit, we compare the top-partner estimate across cases where China displaced the United States and cases where it displaced other partners, and we examine whether longer prior incumbency of the displaced partner is associated with larger effects. These analyses should be read as tests of scope conditions and effect heterogeneity, not as robustness checks for a different estimand.

> **[NOTA DE IMPLEMENTACAO - atualizar antes de compilar]** The exploratory code chunk above still points to the previous non-US comparison targets. The final paper should either replace those targets with scope-condition targets for the same top-partner treatment or move this material to an explicitly labeled exploratory scope appendix.)"
replace_line("^Our theory predicts that the effect should be strongest", scope_text, "texto de probes de escopo", NULL)

scope_chunk_note <- r"(> **[NOTA DE IMPLEMENTACAO - alvo pendente]** Remove the old `fect_ife_any` / `switching_panel_any` chunk here. If this scope-condition section is retained, add new targets that split the pooled China top-partner treatment by whether the displaced prior top partner was the United States.)"
replace_chunk("^```\\{r fect-any-results", scope_chunk_note, "chunk antigo de comparacao non-US")

loo_results_chunk <- r"---(```{r loo-results, include=FALSE}
loo_df <- tryCatch(tar_read(fect_ife_china_top_loo), error = function(e) NULL)
if (is.null(loo_df)) {
  loo_treated <- data.frame()
  loo_brazil <- data.frame()
  loo_source <- "not available"
} else {
  loo_treated <- loo_df
  loo_brazil <- loo_df[loo_df$iso3c == "BRA", ]
  loo_source <- "target"
}
```)---"
replace_chunk("^```\\{r loo-results", loo_results_chunk, "chunk leave-one-out no corpo")

loo_text <- r"(With a limited number of treated countries, a natural concern is whether the cross-country ATT is driven by a single influential country -- particularly Brazil, which generated the theory. We address this by reporting a leave-one-out sensitivity analysis: we re-estimate the fect IFE model dropping each treated country in turn. In the final version, "treated country" should refer to all countries with treated periods under the top-partner definition, not only cases where China displaced the United States. The full leave-one-out results are reported in Table \@ref(tab:table-loo-appendix) in the Appendix.)"
replace_line("^With only `r n_treated_sw` treated countries", loo_text, "leave-one-out no corpo do texto", NULL)

alternatives_block <- r"(## Alternative Explanations

We systematically consider the most plausible alternative explanations and their empirically distinguishable predictions:

| Alternative | Key prediction | What the current evidence addresses | Residual risk |
|---|---|---|---|
| Smooth trade exposure | Alignment follows continuous export dependence rather than the status change of becoming #1 | Brazil includes trade covariates and timing placebos; cross-country IFE absorbs latent common shocks | Cross-country top rank remains correlated with material dependence |
| Commodity shocks | Commodity exporters both become more China-dependent and move closer to China | IFE allows common shocks with heterogeneous loadings; unit FE absorb time-invariant export structure | Country-specific commodity shocks may remain |
| Structural bandwagoning | Persistent movement toward China after its rise | Exit analysis tests whether effects attenuate when China loses top rank | Reversibility is suggestive, not definitive |
| Chinese coercion | Alignment shifts due to pressure or inducements, not salience | Brazil is less vulnerable to simple coercion; panel patterns are evaluated through timing | Coercion and status may coexist |
| Domestic ideology/leader change | Alignment changes with government ideology | Brazil SDiD uses counterfactual timing; panel includes country and year structure | Country-specific political shifts may coincide with rank reversal |

These diagnostics narrow the set of plausible alternatives but do not eliminate them. The Brazilian evidence is strongest for distinguishing rank salience from smooth trade growth because it combines timing placebos, trade covariates, and mechanism evidence from media coverage in the high-salience case where China displaced the United States. The cross-country evidence estimates the same top-partner treatment across a broader set of cases, but it cannot fully separate ordinal rank from continuous export dependence in every country.)"
replace_block("^## Alternative Explanations$", "^# Conclusion$", alternatives_block, "alternativas e interpretacao")

conclusion_block <- r"(# Conclusion

We have proposed a theory of trade-based status gains in which a rising major power's move to the top of a trade hierarchy can reshape foreign-policy alignment. The treatment is the same in the Brazilian SDiD and in the cross-country panel: China becomes the country's top trade partner, operationalized as the largest export destination. What differs is the scope condition. Brazil is the strongest version of the treatment because China displaced the United States, the hegemon and strategic rival of the rising power, after roughly eight decades of US primacy. Under SDiD, Brazil moved closer to China in UNGA ideal-point space relative to its synthetic counterfactual, and Brazilian media coverage became more China- and trade-salient after the reversal.

The cross-country evidence estimates the same top-partner treatment across a broader set of countries. Its role is to probe external validity and scope conditions for the top-partner mechanism; the dynamically reported estimates in the results section should determine whether the pooled average is statistically distinguishable from zero in the current build. The Brazilian case shows the mechanism more directly and under the scope condition where the theory predicts the largest effect.

The findings therefore suggest a calibrated conclusion: ordinal milestones in economic relationships can matter for diplomatic alignment, and the effect should be strongest when the milestone signals a rising power's displacement of a hegemonic rival. Future research should test these scope conditions more directly, especially whether effects are larger when China displaces the United States, when the displaced partner was long-entrenched, and when media institutions amplify the rank reversal.

Our findings also carry practical implications. From the perspective of US policymakers, symbolic milestones in trade hierarchies deserve attention alongside aggregate trade volumes. If losing the top trade partner position initiates a post-reversal process of diplomatic realignment, then monitoring and responding to these threshold crossings -- rather than focusing solely on trade balances -- may be a more effective strategy for maintaining influence.

Despite these limitations, our study is the first to provide systematic evidence for trade-status effects in international relations. By highlighting trade-status salience, this study opens up new avenues for understanding how discrete milestones in economic ties can reshape international alignments and invites extensions to other domains, including FDI, foreign aid, loans, and investment.)"
replace_block("^# Conclusion$", "^# References \\{-\\}$", conclusion_block, "conclusao")

appendix_cs_block <- r"(## Cross-Country Robustness: Absorbing-Treatment Estimator (C&S)

As a supplementary check, the final paper can estimate an absorbing-treatment DiD only for countries where China enters the top trade-partner position and does not subsequently lose it within the sample. This estimator is not the main specification because the theory and data allow treatment reversals. It should be reported only as a restricted comparison for the same top-partner treatment.

> **[NOTA DE IMPLEMENTACAO - atualizar antes de compilar]** The existing wild-bootstrap, Fisher-test, and C&S code in this section is tied to the US-displacement subset. It should not be presented as a robustness check for the pooled top-partner estimate unless the corresponding targets are recomputed with the pooled treatment definition. If retained before recomputation, label it as a scope-condition analysis for hegemonic-rival replacement.)"
replace_block("^## Cross-Country Robustness: Absorbing-Treatment Estimator \\(C&S\\)$", "^## Cross-Country Diagnostic: No-Pretrend Equivalence Tests$", appendix_cs_block, "apendice C&S e inferencia antiga")

equiv_plot_chunk <- r"---(```{r plot-equiv-appendix, message=FALSE, warning=FALSE, echo=FALSE, fig.cap=paste0("Equivalence tests for the no-pretrend assumption in the China top-partner fect specification. ", caption_note(se = "bootstrap (500 replications)", window = sprintf("%d-%d panel", panel_min, panel_max), treatment = treat_def_panel)), fig.pos="H", fig.width=10, fig.height=5}
tar_read(plot_diagnostics_equiv_china_top)
```)---"
replace_chunk("^```\\{r plot-equiv-appendix", equiv_plot_chunk, "chunk de equivalencia fect no apendice")

treated_appendix_text <- r"(Table \@ref(tab:table-treated-appendix) describes countries that experience treated periods under the cross-country top-partner definition. For each country, we report the first observed year in which China becomes the largest export destination, the number of treated years, whether China later loses the top position, and pre/post mean UNGA distance to China.)"
replace_line("^Table \\\\@ref\\(tab:table-treated-appendix\\) describes", treated_appendix_text, "descricao da tabela de tratados no apendice", NULL)

treated_appendix_chunk <- r"---(```{r table-treated-appendix, message=FALSE, warning=FALSE, echo=FALSE, results='asis'}
library(kableExtra)

treated_tbl <- tar_read(china_top_panel) %>%
  dplyr::arrange(iso3c, year) %>%
  dplyr::group_by(iso3c, country_name) %>%
  dplyr::mutate(
    china_top_lag = dplyr::lag(china_top),
    entry = china_top == 1L & !is.na(china_top_lag) & china_top_lag == 0L,
    exit = china_top == 0L & !is.na(china_top_lag) & china_top_lag == 1L
  ) %>%
  dplyr::summarise(
    first_treat_year = ifelse(any(entry, na.rm = TRUE), min(year[entry], na.rm = TRUE), NA_integer_),
    treated_years = sum(china_top == 1L, na.rm = TRUE),
    exits = sum(exit, na.rm = TRUE),
    left_censored = dplyr::first(china_top) == 1L,
    mean_distance_pre = ifelse(
      any(entry, na.rm = TRUE),
      mean(abs_distance_china[year < first_treat_year], na.rm = TRUE),
      NA_real_
    ),
    mean_distance_treated = mean(abs_distance_china[china_top == 1L], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::filter(treated_years > 0) %>%
  dplyr::mutate(
    switching = ifelse(exits > 0, "Yes", "No"),
    first_treat_year = ifelse(is.na(first_treat_year), "Left-censored", as.character(first_treat_year)),
    diff = mean_distance_treated - mean_distance_pre
  ) %>%
  dplyr::select(country_name, iso3c, first_treat_year, treated_years, switching,
                left_censored, mean_distance_pre, mean_distance_treated, diff)

kable(treated_tbl,
      format = "latex",
      booktabs = TRUE,
      digits = 3,
      caption = "Descriptive statistics of treated countries under China top trade-partner status.",
      col.names = c("Country", "ISO3c", "Treatment year", "Treated years",
                    "Switching", "Left-censored", "Mean dist. (pre)",
                    "Mean dist. (treated)", "Diff"),
      align = "llccccccc") %>%
  kable_styling(latex_options = c("hold_position", "scale_down"),
                font_size = 8) %>%
  footnote(general = paste0("Switching = China later loses the largest-export-destination position. ",
                            "Left-censored = China was already the largest export destination in the first observed panel year. ",
                            "Treatment year = first observed entry into China top export-destination status. ",
                            "Mean dist. = absolute distance to China in UNGA ideal points. ",
                            "Diff = treated-period mean minus pre-treatment mean."),
           general_title = "Note: ",
           escape = FALSE,
           threeparttable = TRUE)
```)---"
replace_chunk("^```\\{r table-treated-appendix", treated_appendix_chunk, "tabela de tratados no apendice")

absorbing_plot_note <- r"(The dynamic event study below should be omitted until the absorbing-treatment C\&S targets are recomputed for the pooled China top-partner treatment. The previous figure used US-displacement targets, so it is not the same estimand as the revised cross-country design.)"
replace_line("^The dynamic event study below displays", absorbing_plot_note, "nota sobre C&S absorvente pendente", NULL)

absorbing_plot_chunk <- r"(> **[NOTA DE IMPLEMENTACAO - alvo pendente]** Add a pooled absorbing-treatment target before restoring this figure. Do not use `plot_es_displaced_usa` here, because it refers to the prior US-displacement subset rather than the pooled China top-partner treatment.)"
replace_chunk("^```\\{r plot-es-facet-appendix", absorbing_plot_chunk, "remove plot C&S antigo")

loo_appendix_chunk <- r"---(```{r table-loo-appendix, message=FALSE, warning=FALSE, echo=FALSE, results='asis'}
library(knitr)

loo_raw <- tryCatch(tar_read(fect_ife_china_top_loo), error = function(e) NULL)
treated_iso <- tar_read(china_top_panel) %>%
  dplyr::filter(china_top == 1) %>%
  dplyr::distinct(iso3c) %>%
  dplyr::pull(iso3c)
full_s <- fect_att_summary(tar_read(fect_ife_china_top))

if (is.null(loo_raw)) {
  loo_treated <- data.frame()
} else {
  loo_treated <- loo_raw[loo_raw$iso3c %in% treated_iso, ]
}

loo_tbl <- rbind(
  data.frame(dropped = "Full model", iso3c = "ALL",
             att = full_s$att, se = full_s$se, p = full_s$p, r_cv = full_s$r_cv,
             stringsAsFactors = FALSE),
  loo_treated
)

loo_display <- loo_tbl %>%
  dplyr::mutate(
    att = sprintf("%.3f", att),
    se = sprintf("%.3f", se),
    p = sprintf("%.3f", p)
  ) %>%
  dplyr::select(dropped, att, se, p, r_cv)

kable(loo_display,
      format = "latex",
      booktabs = TRUE,
      caption = "Leave-one-out sensitivity: fect IFE ATT when each treated country is excluded.",
      col.names = c("Dropped country", "ATT", "SE", "p-value", "$r^*$"),
      escape = FALSE,
      align = "lcccc")
```)---"
replace_chunk("^```\\{r table-loo-appendix", loo_appendix_chunk, "tabela leave-one-out no apendice")

dir.create(dirname(map_file), showWarnings = FALSE, recursive = TRUE)
writeLines(edited, out_file, useBytes = TRUE)

map_lines <- c(
  "# Mapa de alteracoes: `paper_v4_cross_country_rewrite_marked.Rmd`",
  "",
  "Fonte verificada: `paper_v4.Rmd` no estado atual do arquivo no momento da geracao.",
  "",
  "| Bloco | Linhas no original atual | Acao |",
  "|---|---:|---|"
)
for (i in seq_len(nrow(changes))) {
  map_lines <- c(
    map_lines,
    sprintf(
      "| %s | %d-%d | %s |",
      changes$label[[i]],
      changes$old_start[[i]],
      changes$old_end[[i]],
      changes$action[[i]]
    )
  )
}
writeLines(map_lines, map_file, useBytes = TRUE)

message(sprintf("Wrote %s", out_file))
message(sprintf("Wrote %s", map_file))
