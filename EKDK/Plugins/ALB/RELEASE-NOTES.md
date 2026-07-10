# ALB 0.3.0 Release Notes

ALB 0.3.0 marks the loader/core architecture milestone for the EuroScope plugin.
`ALB.dll` remains the stable EuroScope-facing loader, while `ALBCore.dll`
continues as the main runtime payload used for autoupdate.

Highlights:

- loader/core packaging milestone completed for manual install and core-only
  autoupdate delivery;
- backend-primary / canonical sequence-state work advanced for shared sequence
  authority;
- RDA gross stale-route detection improved;
- ODR post-via / IAP no-hold suppression improved;
- stale terminal cleanup improved for No Fix / No Via cases;
- manual LT resequence / advance-one authority expanded;
- sequencing diagnostics and visibility audits improved;
- general stability improvements across the runtime.

Validation note:

- manual LT authority and ODR suppression should still be watched closely in
  the first 0.3.0 playback / release-candidate run if they have not yet had a
  full long-run validation pass.
