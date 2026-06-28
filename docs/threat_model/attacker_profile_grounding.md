# Empirical Grounding for Attacker Attestation Profiles

Evidence base for the attacker-capability profiles used in the attestation-gate
evaluation. Each profile models an **attacker's signing capability**; the
attestation tier of injected poison is then *derived* by validating the
signature that capability can produce (commodity -> unsigned -> T_N; capable ->
self-signed/untrusted -> T_W; state -> trust-anchored key -> T_S). The
literature supports the *ordering and shape* of a cost/capability-gated
gradient -- which capability an attacker class can realistically obtain -- not
exact per-payload signing frequencies.

## The cost/capability gradient (the spine of the ladder)

Attestation capability is gated by cost, producing a natural sophistication
gradient:

- Commodity crypting services: ~$10-30 per encryption [Recorded Future 2018].
- Basic code-signing certificate: ~$299 [CyberScoop 2018; Recorded Future 2018].
- Extended-Validation (EV) certificate w/ SmartScreen reputation: ~$1599
  [CyberScoop 2018] -- "much more likely to be used by well-funded groups."
- Counterfeit/strong certs "not anticipated to become a mainstream staple of
  cybercrime due to prohibitive cost," but "nation-state actors ... will
  continue using" them [Recorded Future 2018; SecurityWeek 2018].

Historical diffusion confirms the ordering: strong-attested attacks began as
nation-state operations (Stuxnet, Duqu 2.0; attributed to US/Israel) and are
"climbing down ... to prices affordable to a wider range of cybercriminals"
[CyberScoop 2018].

## Per-tier evidence

### T_N (none) -- commodity default
Most commodity malware/content is unsigned: crypting ($10-30) is far cheaper
than signing ($299+), so the mainstream attacker path stays unattested
[Recorded Future 2018]. Signed malware is a measurable but *minority* path:
1M+ signed malicious samples since 2021, 87% with valid certificates
[VirusTotal/Security Boulevard 2022] -- a large absolute count but a subset of
total malware volume.

### T_W (weak: custody/platform-level OR self-signed/unvalidated)
Low barrier for both defenders and attackers. Platform attestation hardware is
near-ubiquitous: a TPM is provided by "nearly all PC and notebook
manufacturers" as of 2025, and Windows 11 mandates TPM 2.0 [TCG/Wikipedia 2025;
Intel]. On the attacker side, weak/automated certificate issuance "only requires
a valid company registration number and a contact person" [TheHackerNews 2024],
making weak attestation reachable by capable-but-not-elite actors. In the
evaluation this is the *self-signed* case: a valid signature whose key is not a
trust root, which validates as authentic-but-unanchored -> T_W.

### T_S (strong: author-level PKI/C2PA validating to a trust root)
Rare and expensive. For content provenance, "few CAs are listed [on the C2PA
trust list], no Let's Encrypt equivalent," and unrecognized signers show as
"unknown source" [SoftwareSeni 2026]; the provenance market was only $1.63B in
2025, still early adoption [TBRC 2026]. For code, strong attestation is the
cost-gated, well-funded/nation-state path [CyberScoop 2018]. Critically, an
attacker reaches T_S in the evaluation only by signing with a key that chains to
the trust root -- i.e. a *compromised trust anchor* (a stolen author/CA key),
not "sophistication." Forged or tampered claims fail validation and remain
T_W/T_N. This is the honest condition under which poison is trusted.

## Attacker-capability profiles (capability model)

Each profile is a single signing capability; the poison tier is derived by
validating the resulting signature (not assigned). The deployment regime is a
separate axis applied to *legitimate* content as an adoption distribution over
the same capabilities.

| Profile     | Capability (env) | Signs with         | Derived tier | Maps to |
|-------------|------------------|--------------------|--------------|---------|
| Commodity   | `none`           | nothing (unsigned) | T_N          | Crypting-only actor; signing is not cost-effective. |
| Capable     | `untrusted`      | a valid key NOT in the trust roots (self-signed) | T_W | Financially-motivated actor who can obtain/operate a key but not a trust-anchored one. |
| State       | `root`           | a key that chains to the trust root (compromised anchor) | T_S | Nation-state / supply-chain actor who has stolen or compromised a trust-anchored signing key. |

The single-capability design (all poison signed with one capability) is
deliberate: it isolates the gate's response to each tier and avoids any
dependence on *which* injected entry receives *which* tier. Because the tier is
derived per entry from a real signature, there is no tier-proportion parameter
and no stratification artifact -- a poison entry is T_S iff its signature
actually validates against the trust root.

## Framing for the paper (important)

Report the profiles as **"attacker signing-capability levels grounded in the
attestation-economics literature (commodity / capable / state), with the poison
attestation tier derived by cryptographic validation."** The literature
justifies *which capability each attacker class can realistically obtain* and
*the rarity of trust-anchored signing* -- not specific per-payload signing
rates. The central, honest claim the evaluation supports: the gate stops poison
from every modeled capability *except* one that controls a trust-anchored key
(a compromised anchor), which is the residual-risk bound. The legitimate-content
adoption distribution (deployment regime) is the separate axis whose proportions
are illustrative and swept for sensitivity.

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