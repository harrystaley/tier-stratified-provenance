# Empirical Grounding for Attacker Attestation Profiles

Evidence base for the poison-tier distributions used in the attestation-gate
evaluation. The profiles model **attacker attestation capability** as a
distribution over the three tiers (T_S strong, T_W weak, T_N none). The
literature supports the *ordering and shape* of a cost/capability-gated
gradient; the exact proportions are illustrative interpolations spanning that
gradient (and constrained to quarter-granularity by EHRAgent's 4 poison
entries), examined for sensitivity via the regime sweep.

## The cost/capability gradient (the spine of the ladder)

Attestation capability is gated by cost, producing a natural sophistication
gradient:

- Commodity crypting services: ~$10–30 per encryption [Recorded Future 2018].
- Basic code-signing certificate: ~$299 [CyberScoop 2018; Recorded Future 2018].
- Extended-Validation (EV) certificate w/ SmartScreen reputation: ~$1599
  [CyberScoop 2018] — "much more likely to be used by well-funded groups."
- Counterfeit/strong certs "not anticipated to become a mainstream staple of
  cybercrime due to prohibitive cost," but "nation-state actors ... will
  continue using" them [Recorded Future 2018; SecurityWeek 2018].

Historical diffusion confirms the ordering: strong-attested attacks began as
nation-state operations (Stuxnet, Duqu 2.0; attributed to US/Israel) and are
"climbing down ... to prices affordable to a wider range of cybercriminals"
[CyberScoop 2018].

## Per-tier evidence

### T_N (none) — commodity default
Most commodity malware/content is unsigned: crypting ($10–30) is far cheaper
than signing ($299+), so the mainstream attacker path stays unattested
[Recorded Future 2018]. Signed malware is a measurable but *minority* path:
1M+ signed malicious samples since 2021, 87% with valid certificates
[VirusTotal/Security Boulevard 2022] — a large absolute count but a subset of
total malware volume.

### T_W (weak: custody/platform-level OR self-signed/unvalidated)
Low barrier for both defenders and attackers. Platform attestation hardware is
near-ubiquitous: a TPM is provided by "nearly all PC and notebook
manufacturers" as of 2025, and Windows 11 mandates TPM 2.0 [TCG/Wikipedia 2025;
Intel]. On the attacker side, weak/automated certificate issuance "only requires
a valid company registration number and a contact person" [TheHackerNews 2024],
making weak attestation reachable by capable-but-not-elite actors.

### T_S (strong: author-level PKI/C2PA validating to a trust root)
Rare and expensive. For content provenance, "few CAs are listed [on the C2PA
trust list], no Let's Encrypt equivalent," and unrecognized signers show as
"unknown source" [SoftwareSeni 2026]; the provenance market was only $1.63B in
2025, still early adoption [TBRC 2026]. For code, strong attestation is the
cost-gated, well-funded/nation-state path [CyberScoop 2018]. Critically, even
sophisticated actors rarely achieve *exclusively* strong attestation — they mix
unsigned/weak payloads opportunistically — motivating A3 (state) at S:0.75,W:0.25
rather than a pure S:1.0.

## Profile distributions

| Profile | Poison dist | Resolves (4 entries) | Rationale |
|---------|-------------|----------------------|-----------|
| A0 unsophisticated (= pure P_N) | N:1.0       | 4 N        | Commodity; crypting not signing; unsigned mainstream path. |
| A1 capable                      | N:0.5,W:0.5 | 2 N, 2 W   | Financially-motivated; can buy basic ($299)/self-sign for some payloads, not all. |
| A2 sophisticated                | W:0.5,S:0.5 | 2 W, 2 S   | APT-tier; automated weak issuance + occasional EV/stolen author-level. |
| A3 state                        | S:0.75,W:0.25 | 3 S, 1 W | Nation-state; steals author-level certs / compromises CAs; S-heavy but not exclusive. |

Pure buckets P_W (W:1.0) and P_S (S:1.0) are retained as *controlled per-tier
references* (clean "what the gate does to tier T" rows); the mixed A1–A3
profiles are the *realistic* scenarios. Note P_S (S:1.0) is the theoretical
worst case; A3 (S:0.75,W:0.25) is the empirically-motivated realistic state actor.

## Framing for the paper (important)

Report these as **"illustrative attacker-capability distributions modeled from
the attestation-economics literature, with proportions chosen to span the
cost/capability gradient and constrained to the benchmark's injection
granularity; sensitivity examined across deployment regimes."** Do NOT report
them as measured signing frequencies — no source gives an exact per-payload
signing rate per attacker class. The literature justifies the *gradient and the
rarity of strong attestation*, not specific percentages.

## References (IEEE format)

[1] A. Barysevich and Recorded Future Insikt Group, "The Use of Counterfeit
Code Signing Certificates Is on the Rise," Recorded Future, Feb. 2018.
[Online]. Available: https://www.recordedfuture.com/blog/code-signing-certificates

[2] P. O'Neill, "Criminals sell counterfeit certificates to make malware look
legitimate," CyberScoop, Feb. 2018. [Online]. Available:
https://cyberscoop.com/criminals-sell-fake-certificates-rendering-malware-virtually-undetectable/

[3] "Study Shows Widespread Abuse of Code Signing Certificates," Security
Boulevard, Aug. 2022. [Online]. Available:
https://securityboulevard.com/2022/08/study-shows-widespread-abuse-of-code-signing-certificates/

[4] Chronicle (Alphabet), "Abusing Code Signing for Profit," May 2019.
[Online]. Available: https://chroniclesec.medium.com/abusing-code-signing-for-profit-ef80a37b50f4

[5] D. Kim, B. J. Kwon, and T. Dumitras, "Certified Malware: Measuring Breaches
of Trust in the Windows Code-Signing PKI," in Proc. ACM SIGSAC Conf.
Computer and Communications Security (CCS), 2017, pp. 1435-1448.

[6] B. J. Kwon et al., "Issued for Abuse: Measuring the Underground Trade in
Code Signing Certificates," arXiv:1803.02931, 2018.

[7] "Researchers Uncover Hijack Loader Malware Using Stolen Code-Signing
Certificates," The Hacker News, Oct. 2024. [Online]. Available:
https://thehackernews.com/2024/10/researchers-uncover-hijack-loader.html

[8] Trusted Computing Group, "Trusted Platform Module," 2025. [Online].
Available: https://en.wikipedia.org/wiki/Trusted_Platform_Module

[9] Coalition for Content Provenance and Authenticity (C2PA) content-provenance
adoption status, 2026. [Online]. Available:
https://www.softwareseni.com/what-is-c2pa-and-how-does-content-provenance-infrastructure-work/

[10] The Business Research Company, "C2PA Content Provenance Solutions Global
Market Report 2026," 2026.

NOTE: Several sources above are industry/press analyses. For a peer-reviewed
venue, prefer the academic anchors [5] (CCS'17) and [6] (arXiv) for the
code-signing-abuse claims, and cite primary standards/measurement work where
possible. The press sources are acceptable for market/pricing facts but should
be supplemented with the academic measurement literature for the core claims.