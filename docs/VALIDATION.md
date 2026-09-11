# v0.2.0 validation record

Software checks: Node HTTP protocol and application regression tests; Python build/failure recovery, layout and deterministic-package tests; Lua syntax checks; simulated KOReader lifecycle/network/decode failures; SHA-256 standard vectors; real public-data Chinese/English builds; content-addressed manifest checks. Daily/work/minimal layouts rendered in both languages at 1072×1448, 758×1024 and 600×800 respectively.

Hardware checks remain pending: USB installation, real KOReader display lifecycle, Wi-Fi reconnect behavior, power-button recovery, the two-minute RTC experiment, and 48-hour battery measurements. The release is marked prerelease for this reason. The RTC code is a one-shot test, not recurring low-power mode. No hardware check is counted as passed by simulation.

Before promoting to a hardware-validated stable release, record the Kindle model, firmware, KOReader version, each failure scenario, image update success count and battery change. Keep diagnostic logs local unless deliberately shared. Public cloud generation checks do not prove that a physical Kindle displayed the image.
