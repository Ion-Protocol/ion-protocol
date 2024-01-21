# Formal Verification Details

## Introduction

The Formal Verification (FV) component of the contest is about using the Certora Prover to formally verify properties in the Solidity smart contracts in scope. Participants are incentivized to implement and verify high coverage properties. Submissions, incentives, and judging are different from the main contest so please read this document in its entirety.

## Scope

| Contract                                                                                                                                                                                               | SLOC |     
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --- |
| [IonPool.sol](https://github.com/Ion-Protocol/ion-protocol/blob/master/src/IonPool.sol)                                                                   | 578   |
| [Liquidation.sol](https://github.com/Ion-Protocol/ion-protocol/blob/master/src/Liquidation.sol)             | 149  |
| [InterestRate.sol](https://github.com/Ion-Protocol/ion-protocol/blob/master/src/InterestRate.sol)                       | 212  |

## Overview
- 25% (10,000 USDC) of this contest will be allocated for FV.
- Conventional bug submission, issue judgment, and all reward distribution will be managed by Hats Finance.
- FV component is unique as participants are incentivized to implement and verify high coverage properties using the Certora Prover.
- The judging of FV is conducted by Certora, with different submissions, incentives, and judging processes compared to the standard contest. These processes are explained in this document.

## Getting Started
- **Get access to the Prover**:
  - First time participants, [Register](https://www.certora.com/signup?plan=prover) to automatically receive an access key.
- **Update expired key**: 
  - Send a message in the [Certora Discord](https://discord.gg/usnJm6p4)'s `access-key-request` channel.
- **Tool Installation**: 
  - Follow [installation instructions](https://docs.certora.com/en/latest/docs/user-guide/getting-started/install.html) to download the `certora-cli` tool. Use the latest version of the tool available at the start of the contest, throughout the whole contest.
- **Learning Resources**: 
  - Complete the [tutorials](https://docs.certora.com/projects/tutorials/en/latest).
  - Search the [docs](https://docs.certora.com/en/latest/index.html) for any additional information.
  - Check out some of our [examples](https://www.github.com/certora/examples).
- **Contest Participation**:
  - [Import](https://github.com/new/import) the public repository into a new private repository at the contest's commencement.
  - Conduct verifications on the main branch.
  - Grant access to `teryanarmen` and `pistiner` for judging.
- **Support Channels**:
  - For tool-related issues, send a detailed message with a job link in `help-desk` channel in Discord. Remove the anonymousKey component from the link if you wish to limit viewing to Certora employees. 
  - For FV contest questions, use the relevant community verification channel in Discord.

## Incentives
- 25% (10k) of the total pool is allocated for FV.
- FV pool is split into three categories
  - **Participation**: 10% of pool awarded for properties identifying public mutants.    
  - **Real Bugs**: 20% of pool awarded for properties uncovering actual bugs.
  - **Coverage**: 70% of pool awarded for properties identifying private mutants.
- If no properties are accepted for real bugs, the pool will be rebalanced to 90% coverage and 10% participation.
- Mutants are mutated versions of the original code which create vulnerabilities. These mutants are used to gauge verified properties' coverage of the original code.
  - Public mutants used for evaluating participation rewards can be found in `certora/mutations`.
- Participation and coverage reward can be calculated as follows
    - Each mutant is worth $0.9^{n-1}$ points where $n$ is the number of participants that caught the mutant.
    - If we let $P$ be the total FV pool and $T$ be the sum of all mutants' points, we can define each participant's reward as $ \frac{P}{T} \cdot \frac{0.9^{n-1}}{n} $
- Real bug rewards will be awarded for properties that are violated because of the bug. Only the bug submitter can submit a spec for that bug. 25, 12, or 1 points will be allocated based on the severity of the bug (H/M/L).

## Submission Guidelines
- **Development Constraints**:
  - Participants are allowed to create and modify configuration, harnesses, and specification files.
    - Some conf files have commented out settings which can be used to help with running time.
  - All coverage and participation submissions must pass on the unaltered original codebase.
  - Source code modifications are prohibited.
    - Evaluations are based on the original code; configurations reliant on code changes will be disregarded.
  - Utilize the latest version of `certoraRun` available at contest start.
    - Avoid updates during the contest, even if new versions are released.
    - Only update if explicitly told to by Certora team.
  - Submissions with tool errors, compilation errors, or timing-out rules will not be considered.
    - Ensure configurations do not time out; retest to confirm consistency.
- **Configuration Naming**:
  - For coverage and participation: Name configuration files as `ContractName_[identifier]_verified.conf`. The identifier is optional and should be used when multiple configurations are created for one contract.     
    - Example: `ERC20_summarized_verified.conf`.
  - For real bugs: Replace `_verified` with `_violated` in the configuration file name.
- **Real bug submissions**:
  - Real bug submissions must include a GitHub issue in your private fork, detailing the impact, specifics, violated rule, and a solution.
    - Properties for real bugs will only be accepted if the underlying issue is accepted by the hosting platform judge.
    - If possible, link to the original bug submission.
    - Submission must explain the property that catches the bug.
    - A link to the violated run must be included.
    - A proposed solution must be included as a diff between the buggy and fixed code.
    - A verified run of the property on the fixed version must be included.

## Evaluation Process
- **Preliminary Results**: Initial findings will be announced along with the mutations used for evaluation. A google sheet showing which mutants were caught by which participants will be shared. Participants will have a 72-hour period for review and submit corrections in case a certain mutant is marked as not caught but they actually caught it.
- **Correction Submissions**: Corrections must include a verified run on the source code and a violated run on the mutant. Any changes other than the mutation will result in exclusion of the correction.
- **Check your work**: Use `certoraMutate` to evaluate your work on public mutations and random mutations created by gambit.
  - Gambit confs will be provided for all the in scope contracts. To run mutation testing, you can do `certoraMutate --prover_conf certora/confs/contract_verified.conf --mutation_conf certora/confs/gambit/contract.mconf` from root of the directory, same as `certoraRun`. 
  - You can change the number of bugs that are injected by adding manual mutations in the `mutations` folder in a similar fashion to the public mutations or by changing the value of automatic mutation in the contract's mutation conf.
  - Use `--dump_csv file_path.csv` flag with `certoraMutate` to get a csv output of your results. During evaluation, the data from this output is aggregated for all participants used for coverage and participation evaluation. Make sure everthing looks right, specifically, all rules should have "SUCCESS" for the original run.

## Report Compilation
- **Public Disclosure**: The report, encompassing top submissions and mutation descriptions, will be made public post-analysis.
  - Not all top properties focus on the quantity of mutations caught; high-level invariants are highly valued.
    - Future mutations will be adjusted to properly value high quality properties.
  - Guidelines for superior specifications:
    - Avoid code duplication.
    - Eschew simplistic unit tests.
    - Limit excessive assertions.
    - Focus on concise, high-level properties.
    - Reduce overuse of `require` statements.
    - Ensure clear documentation, proper naming, and formatting.
- **Participant Contributions**: The top participants' `certora` folders will be included in the public repository.