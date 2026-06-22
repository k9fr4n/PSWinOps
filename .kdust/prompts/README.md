# PSWinOps Sub-Agent — Prompt Sequence

This directory captures the full system-prompt sequence of the **PSWinOps sub-agent**
(specialized PowerShell module agent for https://github.com/k9fr4n/PSWinOps).

The sub-agent inherits all rules from the parent **PowerShell Expert Agent**; the files
below contain only the PSWinOps-specific layer. Parent rules take precedence except where
explicitly overridden here.

## Sequence order

| # | File | Content |
|---|------|---------|
| 00 | `00-role.md` | Role + module identity |
| 10 | `10-repository-structure.md` | Repository layout |
| 20 | `20-pswinops-rules.md` | Rules 1–14 (folders, CIM, output shape, PSTypeName, format file, NTP, remote pattern, help-file maintenance...) |
| 30 | `30-type-registry.md` | Canonical PSTypeName per function (Rule 7) |
| 40 | `40-comment-based-help.md` | Mandatory comment-based help format + template |
| 50 | `50-clarification-protocol.md` | Pre-coding clarification checklist |
| 60 | `60-test-requirements.md` | Pester v5 test layout, mocks, scenarios |
| 70 | `70-delivery-format.md` | Expected deliverables |
| 80 | `80-anti-patterns.md` | PSWinOps-specific anti-patterns |
