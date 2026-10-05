# Chosen-configuration experiment and plotting code

Replace `run_experiments.m` and `betterplots.m` in your simulation folder, and add `generate_report_plots.m` from this package. Keep your existing `NetworkSim2.m`, `selection_algorithms.m`, `simulation_config.m`, SUMO trace and network files in place. The model and original ping-pong counting convention are unchanged.

Run in MATLAB from the simulation folder:

```matlab
clear run_experiments generate_report_plots betterplots
experimentResults = run_experiments;
```

This runs all experiments and generates the figures automatically. To regenerate figures without rerunning experiments:

```matlab
generate_report_plots
% Or, using the old entry-point name:
betterplots
```

An optional separate results folder is supported:

```matlab
experimentResults = run_experiments(fullfile(pwd,'results_chosen_M008'));
generate_report_plots(fullfile(pwd,'results_chosen_M008'));
```

## Configuration policy

- Final settings for both SAW and TOPSIS: weights `[0.30 0.30 0.20 0.10 0.10]`, margin `0.08`.
- Experiment 2 remains the original exhaustive joint search with all five weights positive. Its winners are reported only in `joint_optimisation_configuration.csv` and the search tables; they are never adopted by other experiments.
- Experiment 1 remains the equal-weight, zero-margin baseline.
- Experiment 3 deliberately varies weights, with the chosen margin `0.08` held fixed.
- Experiments 4 and 6 use the chosen weights and margin for degradation and seeds 1–10 respectively.
- Experiment 5 varies each single-criterion threshold with margin `0.08`. Multi-criteria weights have no effect on these single-criterion policies.
- Experiment 7 varies margin with your fixed weights, marking `0.08` as the investigator-selected setting. No automatic selection of `0.10` occurs.
- Final single-criterion comparisons also use margin `0.08`, the same route and seed, and the existing thresholds. The separate untuned baseline remains available for comparison.
- All final QoS, switching, cost, occupancy and independent metric-reference outputs use the chosen configuration.

`final_configuration.csv` now means the investigator-selected setting. `fixed_weight_selected_hysteresis.csv` replaces the misleading name `fixed_weight_optimal_hysteresis.csv`. The latter may remain from an earlier run; the new code never reads it. Normal final metrics are checked against the selected Experiment 7 points at runtime. Downstream tables include configuration columns. A completed-run metadata file is required by plotting, and old joint-search outputs are rejected.

## Figures corresponding to the report

New figures are saved under `experiment_results/report_figures/chosen_M008/`, with both a 300 dpi PNG and a vector PDF. This separate directory avoids confusing earlier joint-search figures with the new outputs.

| Report evidence | Filename without extension |
| --- | --- |
| Baseline handovers and ping-pong | `Fig1_Baseline_Handovers` |
| Fixed-weight hysteresis sweep; chosen M marked | `Exp7_Fixed_Weight_Hysteresis_Sensitivity` |
| Final SAW/TOPSIS latency, loss and capacity | `Fig4_Final_Core_QoS` |
| Final latency/loss versus independent metric references | `Fig5_Final_Oracle_Comparison` |
| Combined degradation and selected interfaces | `Degradation_combined` |
| Seed robustness, means with sample SD | `Random_Seed_Robustness` |
| Baseline versus chosen-final switching | `Supporting_Baseline_vs_Final_Switching` |

The `appendix/` subfolder contains the capacity sweep, normal/gradual/abrupt time series, single-criterion comparisons, cost and signal, scenario occupancy, random weights, threshold sensitivity and the full five-criterion reference comparison. The full reference figure explicitly labels the mixed signal units and own-score agreement limitations.

Use the following regenerated CSVs for report tables:

| Table | CSV |
| --- | --- |
| Exploratory joint-search winners | `joint_optimisation_configuration.csv` |
| Adopted settings and final performance | `final_configuration.csv` |
| Final multi-criteria/single-criterion comparison | `final_policy_comparison.csv` |
| Chosen margin points | `fixed_weight_selected_hysteresis.csv` |
| Degradation summary and occupancy | `degradation_scenarios_summary.csv` |
| Ten-seed mean ± sample SD | `random_seed_summary.csv` |
| Independent metric-reference gaps | `final_oracle_comparison.csv` |

## Report wording and numerical checks

Describe the joint search as an exploratory result that was rejected as impractical. Describe the weights and M=0.08 as an investigator-selected trade-off informed by Experiment 7, not an automatic or continuous global optimum.

The already supplied Experiment 7 CSV contains these seed-16, normal-scenario values at M=0.08. They are reference checks from your existing results, not claims that this replacement code has been executed here:

| Policy | Handovers | Ping-pong | Latency (ms) | Modelled loss (%) | Capacity (Mb/s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| SAW | 42 | 16 | 16.671337 | 6.783190 | 132.077211 |
| TOPSIS | 42 | 16 | 16.208138 | 8.469060 | 131.949105 |

Replace the old report's M=0.10 comparison, joint-based degradation, seed, oracle and cost analysis with regenerated outcomes. The previous joint-search results cannot be relabelled as evidence for the chosen setting. In particular, threshold-reference outcomes at M=0.08 may differ from the previous zero-margin references.

The simulation still includes satellite as a candidate. Choosing practical priorities does not make the candidate set match the physical Wi-Fi/three-LTE gateway; retain that limitation in the report. Capacity, modelled loss, synthetic degradation and zero switch interruption retain their original definitions.

## Validation

All three MATLAB files passed a MATLAB syntax/lint check. MATLAB and the SUMO trace were not available in the execution environment, so the complete experiment run and figure rendering were not executed here. The run includes a consistency assertion linking final metrics to the chosen Experiment 7 rows, and the plotting script checks configuration provenance before reading final results.
