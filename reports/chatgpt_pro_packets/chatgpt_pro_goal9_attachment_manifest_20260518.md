# Goal 9 ChatGPT Pro Attachment Manifest

Prepared: 2026-05-18

## Packet

- `reports/chatgpt_pro_packets/chatgpt_pro_goal9_instruction_packet_paper_v4_20260518.md`

## Attachments Ready Now

- `paper_v4.Rmd`
- `paper_v4.pdf`
- `quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.md`
- `quality_reports/2026-05-18_goal3_rank_vs_volume_diagnostic.md`
- `quality_reports/goal4_h2_scope_condition/goal4_h2_methodological_report_20260518.md`
- `quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.md`
- `quality_reports/goal6_outcome_robustness/2026-05-18_goal6_outcome_robustness_report.md`
- `quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.md`

## Future Output Path

- `reports/chatgpt_pro_goal9_implementation_guide_paper_v4_20260518.md`

## Future Send Command Template

```sh
/Users/manoelgaldino/.codex/skills/pro-peer-review/.venv/bin/python \
  /Users/manoelgaldino/.codex/skills/pro-peer-review/scripts/chatgpt_pro_review.py \
  reports/chatgpt_pro_packets/chatgpt_pro_goal9_instruction_packet_paper_v4_20260518.md \
  --paper paper_v4.pdf \
  --attachment paper_v4.Rmd \
  --attachment quality_reports/chatgpt_pro_revision_goals_paper_v4_20260517_1916.md \
  --attachment quality_reports/2026-05-18_goal3_rank_vs_volume_diagnostic.md \
  --attachment quality_reports/goal4_h2_scope_condition/goal4_h2_methodological_report_20260518.md \
  --attachment quality_reports/2026-05-18_goal5_sdid_identification_prompt_report.md \
  --attachment quality_reports/goal6_outcome_robustness/2026-05-18_goal6_outcome_robustness_report.md \
  --attachment quality_reports/2026-05-18_goal7_cross_country_scope_prompt_report.md \
  --out reports/chatgpt_pro_goal9_implementation_guide_paper_v4_20260518.md \
  --headed \
  --browser-channel chrome
```

Important: the current `chatgpt_pro_review.py` helper can upload and save the response, but it does not have a title-based conversation selector. Before sending, use the headed browser automation to open the existing ChatGPT conversation titled **ChatGPT Pro Review Guide** rather than starting a new conversation. It is expected to be the antepenultimate conversation in the sidebar.
