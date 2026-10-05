function experimentResults = run_experiments(outDir)
%RUN_EXPERIMENTS Automated investigation for the Smart Tuk-Tuk simulation.
%
% Experimental sequence:
%   1. Baseline: equal weights, zero hysteresis.
%   2. Exploratory joint optimisation; its winners are NOT adopted.
%   3. Random-weight robustness using shared unique samples.
%   4. Controlled network-degradation scenarios + full time series.
%   5. Single-criterion threshold sensitivity.
%   6. Random-seed robustness of the final SAW/TOPSIS configurations.
%   7. Fixed-weight hysteresis sensitivity; investigator chooses M = 0.08.
%
% The optimisation is exhaustive over a defined discrete grid and therefore
% gives a global optimum over that grid, not a claim of continuous global
% optimality. Option C is used: satisfy QoS constraints first, then minimise
% ping-pong, then total handovers, with QoS tie-breaks.
%
% Cost is retained as a selection criterion and as a supporting output, but
% no separate cost-sensitivity experiment is performed.
%
% The SUMO trace is parsed once and reused. The direct XML parser inside
% NetworkSim2 is intentionally not modified by this file.
clc;
close all;
if exist('generate_report_plots','file') ~= 2
    error('Place generate_report_plots.m in this folder or on the MATLAB path.');
end
fprintf('\n====================================================\n');
fprintf(' FINAL AUTOMATED NETWORK-SELECTION EXPERIMENTS\n');
fprintf('====================================================\n\n');
%% Base configuration: supervisor-defined baseline
baseCfg = simulation_config();
baseCfg.weights = [0.20 0.20 0.20 0.20 0.20];
baseCfg.hysteresis = 0;
baseCfg.plotResults = false;
baseCfg.verbose = false;
baseCfg.randomSeed = 16;
% Complete normal-scenario configuration for every non-degradation run.
baseCfg.degradation = struct( ...
    'enabled',false, ...
    'scenario',"normal", ...
    'targetNetworks',1, ...
    'startFraction',0.35, ...
    'endFraction',0.75, ...
    'severity',0.70);
% User-selected configuration: the only settings used for final evaluation.
chosenWeights = [0.30 0.30 0.20 0.10 0.10];
chosenHysteresis = 0.08;
chosenCfg = baseCfg;
chosenCfg.weights = chosenWeights;
chosenCfg.hysteresis = chosenHysteresis;
if nargin < 1 || isempty(outDir)
    outDir = fullfile(pwd,'experiment_results');
end
outDir = char(outDir);
if ~exist(outDir,'dir'), mkdir(outDir); end
% A failed/incomplete run must not leave old metadata marking it complete.
metadataPath = fullfile(outDir,'experiment_metadata.csv');
if isfile(metadataPath), delete(metadataPath); end
algorithms = ["SAW","TOPSIS","Throughput","Latency","PacketLoss","SignalStrength"];
multiCriteriaAlgorithms = ["SAW","TOPSIS"];
%% Parse SUMO trace once
fprintf('Parsing SUMO trace once for all experiments...\n');
baseCfg.algorithm = "SAW";
baseline = NetworkSim2(baseCfg);
traceData = baseline.traceData;
%% ================================================================
% 1. BASELINE: EQUAL WEIGHTS, ZERO HYSTERESIS
% ================================================================
fprintf('\n[1/7] Baseline: equal weights and zero hysteresis...\n');
algorithmRows = zeros(numel(algorithms),16);
for i = 1:numel(algorithms)
    cfg = baseCfg;
    cfg.algorithm = algorithms(i);
    r = NetworkSim2(cfg,traceData);
    pp = count_ping_pong(r.selectedLog,r.time);
    algorithmRows(i,:) = [ ...
        r.switches,r.handoverRate,pp, ...
        r.meanSelectedScore,r.meanOracleScore,r.oracleMatchRate, ...
        r.meanSelectedMetrics(1),r.meanSelectedMetrics(2), ...
        r.meanSelectedMetrics(3),r.meanSelectedMetrics(4), ...
        r.meanSelectedMetrics(5),r.modelledDataCost_R,r.timeOnNetwork];
    fprintf('  %-14s | handovers=%3d | ping-pong=%3d | latency=%7.2f ms | loss=%6.2f %% | throughput=%7.2f Mbps\n', ...
        char(algorithms(i)),r.switches,pp,r.meanSelectedMetrics(1), ...
        r.meanSelectedMetrics(2),r.meanSelectedMetrics(3));
end
algorithmTable = array2table(algorithmRows,'VariableNames',{ ...
    'Handovers','HandoversPerSecond','PingPongHandovers', ...
    'MeanSelectedScore','MeanOracleScore','OracleAgreementPercent', ...
    'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB','TotalDataCost_R', ...
    'TimeWiFi_percent','TimeVodacom_percent','TimeMTN_percent', ...
    'TimeSatellite_percent'});
algorithmTable = addvars(algorithmTable,algorithms(:), ...
    'Before',1,'NewVariableNames','Algorithm');
writetable(algorithmTable,fullfile(outDir,'algorithm_comparison.csv'));
export_algorithm_timeseries(baseCfg,algorithms,traceData,outDir,16,'baseline');
%% ================================================================
% 2. GLOBAL WEIGHT + HYSTERESIS OPTIMISATION
% ================================================================
fprintf('\n[2/7] Global SAW/TOPSIS optimisation of weights and hysteresis...\n');
% The baseline above is deliberately NOT optimised:
%   weights = [0.2 0.2 0.2 0.2 0.2], hysteresis = 0.
%
% The optimisation below searches the complete defined discrete parameter
% space. This is therefore a GLOBAL optimum over the stated grid, rather
% than the best member of a hand-picked set of weight profiles.
%
% Option C selection rule:
%   1) Require acceptable mean latency, packet loss and throughput.
%   2) Among feasible configurations, minimise ping-pong handovers.
%   3) Then minimise total handovers.
%   4) Then prefer lower latency, lower packet loss and higher throughput.
%
% If no candidate is feasible, the candidate with the smallest normalised
% QoS constraint violation is selected before applying the same tie-breaks.
weightStep = baseCfg.optimization.weightStep;
hysteresisValues = 0:baseCfg.optimization.hysteresisStep:baseCfg.optimization.maxHysteresis;
weightGrid = generate_weight_grid(weightStep);
fprintf('  Searching %d weight combinations x %d hysteresis values.\n', ...
    size(weightGrid,1),numel(hysteresisValues));
fprintf('  This is an exhaustive search over the defined discrete grid.\n');
% Run once to generate the common stochastic network metrics. Selection
% weights/hysteresis do not alter the underlying network metrics.
metricCfg = baseCfg;
metricCfg.algorithm = "SAW";
metricCfg.weights = [0.20 0.20 0.20 0.20 0.20];
metricCfg.hysteresis = 0;
metricBase = NetworkSim2(metricCfg,traceData);
optimisationResults = struct();
finalConfigurationTable = table();
for a = 1:numel(multiCriteriaAlgorithms)
    alg = multiCriteriaAlgorithms(a);
    fprintf('  Optimising %s...\n',char(alg));
    best = global_mcdm_search(metricBase,baseCfg,alg,weightGrid,hysteresisValues);
    optimisationResults.(char(alg)) = best;
    fprintf(['    Best weights = [%.2f %.2f %.2f %.2f %.2f], H = %.2f | ', ...
             'feasible=%d | ping-pong=%d | handovers=%d\n'], ...
        best.weights(1),best.weights(2),best.weights(3),best.weights(4),best.weights(5), ...
        best.hysteresis,best.feasible,best.pingPong,best.handovers);
end
% Exploratory winners are reported ONLY for Experiment 2.
jointRows = zeros(numel(multiCriteriaAlgorithms),16);
for a = 1:numel(multiCriteriaAlgorithms)
    alg = multiCriteriaAlgorithms(a);
    b = optimisationResults.(char(alg));
    cfg = set_selector_cfg(baseCfg,alg,b.weights,b.hysteresis);
    r = NetworkSim2(cfg,traceData);
    jointRows(a,:) = configuration_row(r,b.weights,b.hysteresis,baseCfg);
end
jointConfigurationTable = configuration_table(jointRows,multiCriteriaAlgorithms);
jointConfigurationTable.ConfigurationSource = repmat("Exploratory joint search", ...
    height(jointConfigurationTable),1);
writetable(jointConfigurationTable,fullfile(outDir,'joint_optimisation_configuration.csv'));

% Final means, switching, costs and references use the chosen configuration.
finalRows = zeros(numel(multiCriteriaAlgorithms),16);
for a = 1:numel(multiCriteriaAlgorithms)
    cfg = set_selector_cfg(chosenCfg,multiCriteriaAlgorithms(a), ...
        chosenWeights,chosenHysteresis);
    r = NetworkSim2(cfg,traceData);
    finalRows(a,:) = configuration_row(r,chosenWeights,chosenHysteresis,baseCfg);
end
finalConfigurationTable = configuration_table(finalRows,multiCriteriaAlgorithms);
finalConfigurationTable.ConfigurationSource = repmat("Investigator selected", ...
    height(finalConfigurationTable),1);
% Includes single-criterion references at the SAME margin and seed.
policyRows = zeros(numel(algorithms),16);
for a = 1:numel(algorithms)
    cfg = set_selector_cfg(chosenCfg,algorithms(a),chosenWeights,chosenHysteresis);
    r = NetworkSim2(cfg,traceData);
    policyRows(a,:) = configuration_row(r,chosenWeights,chosenHysteresis,baseCfg);
    export_single_timeseries(r,algorithms(a),16,'chosen_normal',outDir);
end
finalPolicyTable = configuration_table(policyRows,algorithms);
writetable(finalPolicyTable,fullfile(outDir,'final_policy_comparison.csv'));
% Explicit baseline-to-final comparison for the main supervisor argument.
baselineRows = zeros(height(finalConfigurationTable),8);
for a = 1:height(finalConfigurationTable)
    alg = string(finalConfigurationTable.Algorithm(a));
    baseRow = algorithmTable(string(algorithmTable.Algorithm)==alg,:);
    finalRow = finalConfigurationTable(a,:);
    baselineRows(a,:) = [ ...
        baseRow.Handovers,baseRow.PingPongHandovers, ...
        finalRow.Handovers,finalRow.PingPongHandovers, ...
        baseRow.MeanLatency_ms,finalRow.MeanLatency_ms, ...
        baseRow.MeanPacketLoss_percent,finalRow.MeanPacketLoss_percent];
end
baselineFinalTable = array2table(baselineRows,'VariableNames',{ ...
    'BaselineHandovers','BaselinePingPongHandovers','FinalHandovers', ...
    'FinalPingPongHandovers','BaselineLatency_ms','FinalLatency_ms', ...
    'BaselinePacketLoss_percent','FinalPacketLoss_percent'});
baselineFinalTable = addvars(baselineFinalTable, ...
    finalConfigurationTable.Algorithm(:),'Before',1,'NewVariableNames','Algorithm');
baselineFinalTable.PingPongReductionPercent = 100*( ...
    baselineFinalTable.BaselinePingPongHandovers-baselineFinalTable.FinalPingPongHandovers) ./ ...
    max(baselineFinalTable.BaselinePingPongHandovers,1);
writetable(finalConfigurationTable,fullfile(outDir,'final_configuration.csv'));
writetable(baselineFinalTable,fullfile(outDir,'baseline_vs_final.csv'));
% Detailed global-search result tables are saved for auditability.
for a = 1:numel(multiCriteriaAlgorithms)
    b = optimisationResults.(char(multiCriteriaAlgorithms(a)));
    writetable(b.searchTable,fullfile(outDir, ...
        sprintf('global_search_%s.csv',char(multiCriteriaAlgorithms(a)))));
end
%% Final selected configuration versus independent per-metric references.
oracleRows = zeros(height(finalConfigurationTable),13);
for a = 1:height(finalConfigurationTable)
    cfg = baseCfg;
    cfg.algorithm = string(finalConfigurationTable.Algorithm(a));
    cfg.weights = [finalConfigurationTable.WeightLatency(a), ...
        finalConfigurationTable.WeightPacketLoss(a), ...
        finalConfigurationTable.WeightThroughput(a), ...
        finalConfigurationTable.WeightSignal(a), ...
        finalConfigurationTable.WeightCost(a)];
    cfg.hysteresis = finalConfigurationTable.Hysteresis(a);
    r = NetworkSim2(cfg,traceData);
    [signalReference,costReference] = supporting_metric_references(r,cfg);
    oracleRows(a,:) = [ ...
        mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
        mean(r.selectedMetricsLog(:,3)),mean(r.metricOracleLog(:,1)), ...
        mean(r.metricOracleLog(:,2)),mean(r.metricOracleLog(:,3)), ...
        r.oracleMatchRate,r.meanSelectedScore,r.meanOracleScore, ...
        r.meanSelectedMetrics(4),r.meanSelectedMetrics(5),signalReference,costReference];
end
oracleComparisonTable = array2table(oracleRows,'VariableNames',{ ...
    'SelectedLatency_ms','SelectedPacketLoss_percent','SelectedThroughput_Mbps', ...
    'MetricOracleLatency_ms','MetricOraclePacketLoss_percent', ...
    'MetricOracleThroughput_Mbps','ScoreOracleAgreement_percent', ...
    'MeanSelectedScore','MeanScoreOracleScore','SelectedSignalQuality_dB', ...
    'SelectedCost_R_per_MB','MetricOracleSignalQuality_dB','MetricOracleCost_R_per_MB'});
oracleComparisonTable = addvars(oracleComparisonTable, ...
    finalConfigurationTable.Algorithm(:),'Before',1,'NewVariableNames','Algorithm');
oracleComparisonTable.Hysteresis = repmat(chosenHysteresis,height(oracleComparisonTable),1);
oracleComparisonTable.WeightLatency = repmat(chosenWeights(1),height(oracleComparisonTable),1);
oracleComparisonTable.WeightPacketLoss = repmat(chosenWeights(2),height(oracleComparisonTable),1);
oracleComparisonTable.WeightThroughput = repmat(chosenWeights(3),height(oracleComparisonTable),1);
oracleComparisonTable.WeightSignal = repmat(chosenWeights(4),height(oracleComparisonTable),1);
oracleComparisonTable.WeightCost = repmat(chosenWeights(5),height(oracleComparisonTable),1);
writetable(oracleComparisonTable,fullfile(outDir,'final_oracle_comparison.csv'));
%% ================================================================
% 3. RANDOM-WEIGHT ROBUSTNESS
% ================================================================
fprintf('\n[3/7] Random-weight robustness using shared unique samples...\n');
rng(2026);
numRandomWeights = 100;
randomWeightSet = zeros(numRandomWeights,5);
for i = 1:numRandomWeights
    while true
        w = rand(1,5);
        w = w/sum(w);
        if i == 1 || ~any(all(abs(randomWeightSet(1:i-1,:)-w) < 1e-12,2))
            randomWeightSet(i,:) = w;
            break;
        end
    end
end
randomWeightRows = [];
for a = 1:numel(multiCriteriaAlgorithms)
    alg = multiCriteriaAlgorithms(a);
    fr = finalConfigurationTable(string(finalConfigurationTable.Algorithm)==alg,:);
    hRow = fr.Hysteresis;
    for i = 1:numRandomWeights
        cfg = baseCfg;
        cfg.algorithm = alg;
        cfg.weights = randomWeightSet(i,:);
        cfg.hysteresis = hRow;
        r = NetworkSim2(cfg,traceData);
        randomWeightRows(end+1,:) = [ ...
            a,i,randomWeightSet(i,:),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.oracleMatchRate,mean(r.selectedMetricsLog(:,1)), ...
            mean(r.selectedMetricsLog(:,2)),mean(r.selectedMetricsLog(:,3)), ...
            mean(r.selectedMetricsLog(:,4)),mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
end
randomWeightTable = array2table(randomWeightRows,'VariableNames',{ ...
    'AlgorithmID','Run','WeightLatency','WeightPacketLoss', ...
    'WeightThroughput','WeightSignal','WeightCost','Handovers', ...
    'PingPongHandovers','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB'});
randomWeightTable.Algorithm = reshape( ...
    multiCriteriaAlgorithms(randomWeightTable.AlgorithmID),[],1);
randomWeightTable = movevars(randomWeightTable,'Algorithm','Before',1);
randomWeightTable.AlgorithmID = [];
randomWeightTable.Hysteresis = repmat(chosenHysteresis,height(randomWeightTable),1);
writetable(randomWeightTable,fullfile(outDir,'random_weight_sensitivity.csv'));
%% ================================================================
% 4. CONTROLLED NETWORK-DEGRADATION SCENARIOS + TIME SERIES
% ================================================================
fprintf('\n[4/7] Network-degradation scenarios and time-series analysis...\n');
scenarioNames = ["normal","gradual","abrupt","combined"];
scenarioRows = [];
degradationCfg = baseCfg;
degradationCfg.degradation.enabled = true;
degradationCfg.degradation.startFraction = 0.35;
degradationCfg.degradation.endFraction = 0.75;
degradationCfg.degradation.severity = 0.70;
for sc = 1:numel(scenarioNames)
    for a = 1:numel(multiCriteriaAlgorithms)
        alg = multiCriteriaAlgorithms(a);
        fr = finalConfigurationTable(string(finalConfigurationTable.Algorithm)==alg,:);
        cfg = degradationCfg;
        cfg.algorithm = alg;
        cfg.weights = [fr.WeightLatency,fr.WeightPacketLoss,fr.WeightThroughput,fr.WeightSignal,fr.WeightCost];
        cfg.hysteresis = fr.Hysteresis;
        cfg.degradation.scenario = scenarioNames(sc);
        if scenarioNames(sc)=="combined"
            cfg.degradation.targetNetworks = [1 2 3];
        else
            cfg.degradation.targetNetworks = 1;
        end
        r = NetworkSim2(cfg,traceData);
        scenarioRows(end+1,:) = [ ...
            sc,a,r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),r.modelledDataCost_R,r.timeOnNetwork]; %#ok<AGROW>
        export_single_timeseries(r,alg,16,scenarioNames(sc),outDir);
    end
end
scenarioTable = array2table(scenarioRows,'VariableNames',{ ...
    'ScenarioID','AlgorithmID','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB','TotalDataCost_R','TimeWiFi_percent', ...
    'TimeVodacom_percent','TimeMTN_percent','TimeSatellite_percent'});
scenarioTable.Scenario = reshape(scenarioNames(scenarioTable.ScenarioID),[],1);
scenarioTable.Algorithm = reshape(multiCriteriaAlgorithms(scenarioTable.AlgorithmID),[],1);
scenarioTable = movevars(scenarioTable,{'Scenario','Algorithm'},'Before',1);
scenarioTable.ScenarioID = [];
scenarioTable.AlgorithmID = [];
scenarioTable.Hysteresis = repmat(chosenHysteresis,height(scenarioTable),1);
scenarioTable.WeightLatency = repmat(chosenWeights(1),height(scenarioTable),1);
scenarioTable.WeightPacketLoss = repmat(chosenWeights(2),height(scenarioTable),1);
scenarioTable.WeightThroughput = repmat(chosenWeights(3),height(scenarioTable),1);
scenarioTable.WeightSignal = repmat(chosenWeights(4),height(scenarioTable),1);
scenarioTable.WeightCost = repmat(chosenWeights(5),height(scenarioTable),1);
writetable(scenarioTable,fullfile(outDir,'degradation_scenarios_summary.csv'));
export_saw_topsis_timeseries(baseCfg,traceData,outDir,finalConfigurationTable);
% Degradation figures are generated by generate_report_plots.
%% ================================================================
% 5. SINGLE-CRITERION THRESHOLD SENSITIVITY
% ================================================================
fprintf('\n[5/7] Single-criterion threshold sensitivity...\n');
criterionNames = ["Throughput","Latency","PacketLoss","SignalStrength"];
thresholdValues = { ...
    [1 2 5 10 20 50], ...
    [20 50 75 100 150 200], ...
    [1 5 10 20 30 50], ...
    [-110 -100 -90 -80 -70 -60]};
thresholdRows = [];
for cidx = 1:numel(criterionNames)
    alg = criterionNames(cidx);
    values = thresholdValues{cidx};
    for v = 1:numel(values)
        cfg = baseCfg;
        cfg.algorithm = alg;
        cfg.weights = chosenWeights;
        cfg.hysteresis = chosenHysteresis;
        switch alg
            case "Throughput",    cfg.threshold.throughput_Mbps = values(v);
            case "Latency",       cfg.threshold.latency_ms = values(v);
            case "PacketLoss",    cfg.threshold.packetLoss_percent = values(v);
            case "SignalStrength",cfg.threshold.signalQuality_dB = values(v);
        end
        r = NetworkSim2(cfg,traceData);
        thresholdRows(end+1,:) = [ ...
            cidx,values(v),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
end
thresholdTable = array2table(thresholdRows,'VariableNames',{ ...
    'CriterionID','Threshold','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB'});
thresholdTable.Criterion = reshape(criterionNames(thresholdTable.CriterionID),[],1);
thresholdTable = movevars(thresholdTable,'Criterion','Before',1);
thresholdTable.CriterionID = [];
thresholdTable.Hysteresis = repmat(chosenHysteresis,height(thresholdTable),1);
thresholdTable.WeightLatency = repmat(chosenWeights(1),height(thresholdTable),1);
thresholdTable.WeightPacketLoss = repmat(chosenWeights(2),height(thresholdTable),1);
thresholdTable.WeightThroughput = repmat(chosenWeights(3),height(thresholdTable),1);
thresholdTable.WeightSignal = repmat(chosenWeights(4),height(thresholdTable),1);
thresholdTable.WeightCost = repmat(chosenWeights(5),height(thresholdTable),1);
writetable(thresholdTable,fullfile(outDir,'single_criterion_threshold_sensitivity.csv'));
% Threshold figures are generated by generate_report_plots.
%% ================================================================
% 6. RANDOM-SEED ROBUSTNESS OF FINAL SAW/TOPSIS CONFIGURATIONS
% ================================================================
fprintf('\n[6/7] Random-seed robustness of final SAW/TOPSIS configurations...\n');
seeds = 1:10;
seedRows = [];
for a = 1:numel(multiCriteriaAlgorithms)
    alg = multiCriteriaAlgorithms(a);
    fr = finalConfigurationTable(string(finalConfigurationTable.Algorithm)==alg,:);
    for s = 1:numel(seeds)
        cfg = baseCfg;
        cfg.algorithm = alg;
        cfg.weights = [fr.WeightLatency,fr.WeightPacketLoss,fr.WeightThroughput,fr.WeightSignal,fr.WeightCost];
        cfg.hysteresis = fr.Hysteresis;
        cfg.randomSeed = seeds(s);
        r = NetworkSim2(cfg,traceData);
        seedRows(end+1,:) = [ ...
            a,seeds(s),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),r.modelledDataCost_R]; %#ok<AGROW>
    end
end
seedTable = array2table(seedRows,'VariableNames',{ ...
    'AlgorithmID','Seed','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB','TotalDataCost_R'});
seedTable.Algorithm = reshape(multiCriteriaAlgorithms(seedTable.AlgorithmID),[],1);
seedTable = movevars(seedTable,'Algorithm','Before',1);
seedTable.AlgorithmID = [];
seedTable.Hysteresis = repmat(chosenHysteresis,height(seedTable),1);
seedTable.WeightLatency = repmat(chosenWeights(1),height(seedTable),1);
seedTable.WeightPacketLoss = repmat(chosenWeights(2),height(seedTable),1);
seedTable.WeightThroughput = repmat(chosenWeights(3),height(seedTable),1);
seedTable.WeightSignal = repmat(chosenWeights(4),height(seedTable),1);
seedTable.WeightCost = repmat(chosenWeights(5),height(seedTable),1);
writetable(seedTable,fullfile(outDir,'random_seed_robustness.csv'));
summaryRows = [];
for a = 1:numel(multiCriteriaAlgorithms)
    idx = seedTable.Algorithm == multiCriteriaAlgorithms(a);
    summaryRows(end+1,:) = [ ...
        mean(seedTable.Handovers(idx)),std(seedTable.Handovers(idx)), ...
        mean(seedTable.PingPongHandovers(idx)),std(seedTable.PingPongHandovers(idx)), ...
        mean(seedTable.MeanThroughput_Mbps(idx)),std(seedTable.MeanThroughput_Mbps(idx)), ...
        mean(seedTable.MeanLatency_ms(idx)),std(seedTable.MeanLatency_ms(idx)), ...
        mean(seedTable.MeanPacketLoss_percent(idx)),std(seedTable.MeanPacketLoss_percent(idx)), ...
        mean(seedTable.TotalDataCost_R(idx)),std(seedTable.TotalDataCost_R(idx))]; %#ok<AGROW>
end
summaryTable = array2table(summaryRows,'VariableNames',{ ...
    'Handovers_Mean','Handovers_SD','PingPong_Mean','PingPong_SD', ...
    'Throughput_Mean_Mbps','Throughput_SD_Mbps','Latency_Mean_ms','Latency_SD_ms', ...
    'PacketLoss_Mean_percent','PacketLoss_SD_percent', ...
    'TotalDataCost_Mean_R','TotalDataCost_SD_R'});
summaryTable = addvars(summaryTable,multiCriteriaAlgorithms(:), ...
    'Before',1,'NewVariableNames','Algorithm');
summaryTable.Hysteresis = repmat(chosenHysteresis,height(summaryTable),1);
summaryTable.WeightLatency = repmat(chosenWeights(1),height(summaryTable),1);
summaryTable.WeightPacketLoss = repmat(chosenWeights(2),height(summaryTable),1);
summaryTable.WeightThroughput = repmat(chosenWeights(3),height(summaryTable),1);
summaryTable.WeightSignal = repmat(chosenWeights(4),height(summaryTable),1);
summaryTable.WeightCost = repmat(chosenWeights(5),height(summaryTable),1);
writetable(summaryTable,fullfile(outDir,'random_seed_summary.csv'));
%% ================================================================
% 7. HYSTERESIS OPTIMISATION WITH CONTEXT-CHOSEN FIXED WEIGHTS
% ================================================================
fprintf('\n[7/7] Fixed-weight hysteresis sensitivity; chosen M = %.2f...\n',chosenHysteresis);
fixedWeights = chosenWeights;
fixedAlgorithms = ["SAW","TOPSIS"];
fixedHValues = 0:baseCfg.optimization.hysteresisStep: ...
                 baseCfg.optimization.maxHysteresis;
fixedHValues = unique([fixedHValues chosenHysteresis]);
fixedRows = zeros(numel(fixedAlgorithms)*numel(fixedHValues),9);
row = 0;
for a = 1:numel(fixedAlgorithms)
    for hi = 1:numel(fixedHValues)
        cfg = baseCfg;
        cfg.algorithm = fixedAlgorithms(a);
        cfg.weights = fixedWeights;
        cfg.hysteresis = fixedHValues(hi);
        cfg.randomSeed = 16;
        cfg.plotResults = false;
        cfg.verbose = false;
        % This experiment uses the normal network scenario.
        cfg.degradation.enabled = false;
        r = NetworkSim2(cfg,traceData);
        lat = r.meanSelectedMetrics(1);
        loss = r.meanSelectedMetrics(2);
        thr = r.meanSelectedMetrics(3);
        feasible = ...
            lat <= baseCfg.qosLimits.maxLatency_ms && ...
            loss <= baseCfg.qosLimits.maxPacketLoss_percent && ...
            thr >= baseCfg.qosLimits.minThroughput_Mbps;
        violation = ...
            max(0,lat/baseCfg.qosLimits.maxLatency_ms-1) + ...
            max(0,loss/baseCfg.qosLimits.maxPacketLoss_percent-1) + ...
            max(0,baseCfg.qosLimits.minThroughput_Mbps/max(thr,eps)-1);
        row = row+1;
        fixedRows(row,:) = [ ...
            a,cfg.hysteresis,feasible,violation, ...
            count_ping_pong(r.selectedLog,r.time),r.switches, ...
            lat,loss,thr];
    end
end
fixedHysteresisTable = array2table(fixedRows,'VariableNames',{ ...
    'AlgorithmID','Hysteresis','QoSFeasible','QoSViolation', ...
    'PingPongHandovers','Handovers','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps'});
fixedHysteresisTable.Algorithm = reshape( ...
    fixedAlgorithms(fixedHysteresisTable.AlgorithmID),[],1);
fixedHysteresisTable.AlgorithmID = [];
fixedHysteresisTable = movevars( ...
    fixedHysteresisTable,'Algorithm','Before',1);
fixedHysteresisTable.Selected = false(height(fixedHysteresisTable),1);
% Selection is the investigator's decision, not the stability-first optimum.
fixedHysteresisTable.Selected = abs( ...
    fixedHysteresisTable.Hysteresis-chosenHysteresis) < 1e-10;
fixedHysteresisBest = fixedHysteresisTable(fixedHysteresisTable.Selected,:);
assert(height(fixedHysteresisBest)==numel(fixedAlgorithms), ...
    'Expected one investigator-selected sweep point per method.');
writetable(fixedHysteresisTable, ...
    fullfile(outDir,'fixed_weight_hysteresis_sensitivity.csv'));
writetable(fixedHysteresisBest, ...
    fullfile(outDir,'fixed_weight_selected_hysteresis.csv'));
% Selected slice must reproduce the final normal-scenario evaluation.
for a = 1:numel(fixedAlgorithms)
    f = finalConfigurationTable(string(finalConfigurationTable.Algorithm)==fixedAlgorithms(a),:);
    h = fixedHysteresisBest(string(fixedHysteresisBest.Algorithm)==fixedAlgorithms(a),:);
    assert(abs(f.MeanLatency_ms-h.MeanLatency_ms)<1e-9 && ...
           abs(f.MeanPacketLoss_percent-h.MeanPacketLoss_percent)<1e-9 && ...
           abs(f.MeanThroughput_Mbps-h.MeanThroughput_Mbps)<1e-9 && ...
           f.Handovers==h.Handovers && f.PingPongHandovers==h.PingPongHandovers, ...
           'Final evaluation and selected Experiment 7 point differ.');
end
% Persist provenance: plotting rejects old joint-search final outputs.
metadata = table("chosen_fixed_weights_v1",chosenHysteresis,16, ...
    chosenWeights(1),chosenWeights(2),chosenWeights(3), ...
    chosenWeights(4),chosenWeights(5),0.35,0.75,0.70, ...
    'VariableNames',{'ConfigurationFamily','Hysteresis','CommonSeed', ...
    'WeightLatency','WeightPacketLoss','WeightThroughput','WeightSignal', ...
    'WeightCost','DegradationStartFraction','DegradationEndFraction', ...
    'DegradationSeverity'});
writetable(metadata,fullfile(outDir,'experiment_metadata.csv'));
%% Save complete results
experimentResults = struct();
experimentResults.algorithmComparison = algorithmTable;
experimentResults.optimisationResults = optimisationResults;
experimentResults.jointOptimisationConfiguration = jointConfigurationTable;
experimentResults.finalConfiguration = finalConfigurationTable;
experimentResults.finalPolicyComparison = finalPolicyTable;
experimentResults.metadata = metadata;
experimentResults.baselineVsFinal = baselineFinalTable;
experimentResults.finalOracleComparison = oracleComparisonTable;
experimentResults.randomWeights = randomWeightTable;
experimentResults.degradationScenarios = scenarioTable;
experimentResults.thresholdSensitivity = thresholdTable;
experimentResults.randomSeeds = seedTable;
experimentResults.randomSeedSummary = summaryTable;
experimentResults.baseline = baseline;
experimentResults.fixedWeightHysteresis = fixedHysteresisTable;
experimentResults.fixedWeightSelectedHysteresis = fixedHysteresisBest;
save(fullfile(outDir,'experimentResults.mat'),'experimentResults');
generate_report_plots(outDir);

fprintf('\n====================================================\n');
fprintf(' EXPERIMENTS COMPLETE\n');
fprintf(' Results saved to:\n %s\n',outDir);
fprintf('====================================================\n\n');
end
%% ========================================================================
function export_algorithm_timeseries(baseCfg,algorithms,traceData,outDir,seed,scenario)
for a = 1:numel(algorithms)
    cfg = baseCfg;
    cfg.algorithm = algorithms(a);
    cfg.randomSeed = seed;
    cfg.plotResults = false;
    cfg.verbose = false;
    r = NetworkSim2(cfg,traceData);
    export_single_timeseries(r,algorithms(a),seed,scenario,outDir);
end
end
%% ========================================================================
function export_single_timeseries(r,algorithm,seed,scenario,outDir)
selectedNetworkName = strings(numel(r.selectedLog),1);
for n = 1:numel(r.networkNames)
    selectedNetworkName(r.selectedLog==n) = r.networkNames(n);
end
detailTable = table( ...
    r.time(:),r.selectedLog(:),selectedNetworkName, ...
    r.selectedMetricsLog(:,1),r.selectedMetricsLog(:,2), ...
    r.selectedMetricsLog(:,3),r.selectedMetricsLog(:,4), ...
    r.selectedMetricsLog(:,5), ...
    'VariableNames',{'Time_s','SelectedNetwork','SelectedNetworkName', ...
    'Latency_ms','PacketLoss_percent','Throughput_Mbps', ...
    'SignalQuality_dB','Cost_R_per_MB'});
detailTable.Algorithm = repmat(string(algorithm),height(detailTable),1);
detailTable.Seed = repmat(seed,height(detailTable),1);
detailTable.Scenario = repmat(string(scenario),height(detailTable),1);
detailTable = movevars(detailTable,{'Scenario','Algorithm','Seed'},'Before','Time_s');
filename = sprintf('timeseries_%s_seed%d_%s.csv',char(algorithm),seed,char(scenario));
writetable(detailTable,fullfile(outDir,filename));
end
%% ========================================================================
function export_saw_topsis_timeseries(baseCfg,traceData,outDir,finalConfigurationTable)
for scenario = ["normal","gradual","abrupt","combined"]
    frSAW = finalConfigurationTable(string(finalConfigurationTable.Algorithm)=="SAW",:);
    frTOP = finalConfigurationTable(string(finalConfigurationTable.Algorithm)=="TOPSIS",:);
    cfgSAW = baseCfg;
    cfgSAW.algorithm = "SAW";
    cfgSAW.weights = [frSAW.WeightLatency,frSAW.WeightPacketLoss,frSAW.WeightThroughput,frSAW.WeightSignal,frSAW.WeightCost];
    cfgSAW.hysteresis = frSAW.Hysteresis;
    cfgSAW.randomSeed = 16;
    cfgSAW.degradation.enabled = true;
    cfgSAW.degradation.scenario = scenario;
    cfgSAW.degradation.startFraction = 0.35;
    cfgSAW.degradation.endFraction = 0.75;
    cfgSAW.degradation.severity = 0.70;
    cfgSAW.degradation.targetNetworks = 1;
    if scenario=="combined", cfgSAW.degradation.targetNetworks=[1 2 3]; end
    cfgTOPSIS = cfgSAW;
    cfgTOPSIS.algorithm = "TOPSIS";
    cfgTOPSIS.weights = [frTOP.WeightLatency,frTOP.WeightPacketLoss,frTOP.WeightThroughput,frTOP.WeightSignal,frTOP.WeightCost];
    cfgTOPSIS.hysteresis = frTOP.Hysteresis;
    saw = NetworkSim2(cfgSAW,traceData);
    topsis = NetworkSim2(cfgTOPSIS,traceData);
    out = table(saw.time(:),saw.selectedLog(:),topsis.selectedLog(:), ...
        saw.selectedMetricsLog(:,1),topsis.selectedMetricsLog(:,1), ...
        saw.selectedMetricsLog(:,2),topsis.selectedMetricsLog(:,2), ...
        saw.selectedMetricsLog(:,3),topsis.selectedMetricsLog(:,3), ...
        saw.selectedMetricsLog(:,4),topsis.selectedMetricsLog(:,4), ...
        saw.selectedMetricsLog(:,5),topsis.selectedMetricsLog(:,5), ...
        'VariableNames',{ ...
        'Time_s','SAW_Network','TOPSIS_Network', ...
        'SAW_Latency_ms','TOPSIS_Latency_ms', ...
        'SAW_PacketLoss_percent','TOPSIS_PacketLoss_percent', ...
        'SAW_Throughput_Mbps','TOPSIS_Throughput_Mbps', ...
        'SAW_SignalQuality_dB','TOPSIS_SignalQuality_dB', ...
        'SAW_Cost_R_per_MB','TOPSIS_Cost_R_per_MB'});
    writetable(out,fullfile(outDir,sprintf('SAW_vs_TOPSIS_timeseries_%s.csv',char(scenario))));
end
end
%% ========================================================================
function count = count_ping_pong(selectedLog,time,T_pp)
% Count A->B->A patterns where the intermediate network is held for <= T_pp.
if nargin < 3 || isempty(T_pp), T_pp = 1.0; end
if numel(selectedLog)<3 || numel(time)~=numel(selectedLog)
    count=0; return;
end
switchIdx = find(diff(selectedLog)~=0);
if numel(switchIdx)<2, count=0; return; end
switchNetworks = selectedLog(switchIdx+1);
switchTimes = time(switchIdx+1);
count=0;
for i=3:numel(switchNetworks)
    if switchNetworks(i)==switchNetworks(i-2) && switchNetworks(i)~=switchNetworks(i-1)
        if switchTimes(i)-switchTimes(i-1)<=T_pp
            count=count+1;
        end
    end
end
end
%% ========================================================================
function W = generate_weight_grid(step)
% All five weights are strictly positive and sum to one.
% The minimum weight for each criterion is step.
validateattributes(step, {'numeric'}, ...
    {'scalar','real','finite','positive'});
N = round(1/step);
if abs(N*step - 1) > 1e-10
    error('weightStep must divide 1 exactly, e.g. 0.05 or 0.10.');
end
if N < 5
    error('weightStep must allow five positive weights summing to one.');
end
W = zeros(nchoosek(N-1,4),5);
row = 0;
for i = 1:(N-4)
    for j = 1:(N-i-3)
        for k = 1:(N-i-j-2)
            for l = 1:(N-i-j-k-1)
                m = N-i-j-k-l;  % Guaranteed to be >= 1
                row = row + 1;
                W(row,:) = [i j k l m]/N;
            end
        end
    end
end
end
%% ========================================================================
function best = global_mcdm_search(metricBase,baseCfg,algorithm,weightGrid,hysteresisValues)
% Exhaustive global search over the supplied discrete weight/H grid.
% The network metrics are fixed across candidates; only the selector is
% evaluated repeatedly. This prevents the optimisation from changing the
% underlying stochastic channel realisation between candidates.
metricsLog = metricBase.metricsLog;
time = metricBase.time(:);
xPos = metricBase.xPos(:);
yPos = metricBase.yPos(:);
nSteps = numel(time);
availableLog = true(nSteps,4);
if isfield(baseCfg,'wifi') && isfield(baseCfg.wifi,'enforceCoverage') && baseCfg.wifi.enforceCoverage
    d = sqrt((xPos-baseCfg.wifi.apPos(1)).^2 + ...
             (yPos-baseCfg.wifi.apPos(2)).^2 + ...
             (1.5-baseCfg.wifi.apPos(3)).^2);
    availableLog(:,1) = d <= baseCfg.wifi.radius_m;
end
nCandidates = size(weightGrid,1)*numel(hysteresisValues);
rows = zeros(nCandidates,13);
rowIdx = 0;
for wi = 1:size(weightGrid,1)
    w = weightGrid(wi,:);
    scoreLog = zeros(nSteps,4);
    % Precompute the instantaneous MCDM score for every timestep.
    for k = 1:nSteps
        M = squeeze(metricsLog(k,:,:));
        avail = availableLog(k,:).';
        [~,scores,~] = selection_algorithms(M,0, ...
            set_selector_cfg(baseCfg,algorithm,w,0),avail);
        scoreLog(k,:) = scores(:).';
    end
    for hi = 1:numel(hysteresisValues)
        H = hysteresisValues(hi);
        selected = zeros(nSteps,1);
        current = 0;
        for k = 1:nSteps
            scores = scoreLog(k,:).';
            [bestScore,bestNet] = max(scores);
            if current == 0
                current = bestNet;
            else
                currentScore = scores(current);
                if bestNet ~= current && (bestScore-currentScore) > H
                    current = bestNet;
                end
            end
            selected(k) = current;
        end
        switches = sum(diff(selected)~=0);
        pp = count_ping_pong(selected,time);
        selectedMetrics = zeros(nSteps,5);
        for k = 1:nSteps
            M = squeeze(metricsLog(k,:,:));
            selectedMetrics(k,:) = M(selected(k),:);
        end
        lat = mean(selectedMetrics(:,1));
        loss = mean(selectedMetrics(:,2));
        thr = mean(selectedMetrics(:,3));
        sig = mean(selectedMetrics(:,4));
        cost = mean(selectedMetrics(:,5));
        feasible = lat <= baseCfg.qosLimits.maxLatency_ms && ...
                   loss <= baseCfg.qosLimits.maxPacketLoss_percent && ...
                   thr >= baseCfg.qosLimits.minThroughput_Mbps;
        violation = max(0,lat/baseCfg.qosLimits.maxLatency_ms-1) + ...
                    max(0,loss/baseCfg.qosLimits.maxPacketLoss_percent-1) + ...
                    max(0,baseCfg.qosLimits.minThroughput_Mbps/max(thr,eps)-1);
        dataCost = 0.125*trapz(time,selectedMetrics(:,3).*selectedMetrics(:,5));
        rowIdx = rowIdx+1;
        rows(rowIdx,:) = [wi,H,feasible,violation,pp,switches,lat,loss,thr,sig,cost,dataCost,0];
    end
end
rows = rows(1:rowIdx,:);
searchTable = array2table(rows,'VariableNames',{ ...
    'WeightIndex','Hysteresis','QoSFeasible','QoSViolation', ...
    'PingPongHandovers','Handovers','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB','TotalDataCost_R','Selected'});
searchTable.WeightLatency = weightGrid(searchTable.WeightIndex,1);
searchTable.WeightPacketLoss = weightGrid(searchTable.WeightIndex,2);
searchTable.WeightThroughput = weightGrid(searchTable.WeightIndex,3);
searchTable.WeightSignal = weightGrid(searchTable.WeightIndex,4);
searchTable.WeightCost = weightGrid(searchTable.WeightIndex,5);
searchTable = movevars(searchTable, ...
    {'WeightLatency','WeightPacketLoss','WeightThroughput','WeightSignal','WeightCost'}, ...
    'After','Hysteresis');
feasibleIdx = find(searchTable.QoSFeasible);
if isempty(feasibleIdx)
    candidates = searchTable(searchTable.QoSViolation == min(searchTable.QoSViolation),:);
else
    candidates = searchTable(feasibleIdx,:);
end
% Option C lexicographic objective:
% first QoS feasibility/violation, then ping-pong, then total handovers,
% then latency, packet loss, and finally maximise throughput.
if isempty(feasibleIdx)
    candidates = sortrows(candidates,{'QoSViolation','PingPongHandovers', ...
        'Handovers','MeanLatency_ms','MeanPacketLoss_percent'});
else
    candidates = sortrows(candidates,{'PingPongHandovers','Handovers', ...
        'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps'});
    candidates.MeanThroughput_Mbps = -candidates.MeanThroughput_Mbps;
    candidates = sortrows(candidates,{'PingPongHandovers','Handovers', ...
        'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps'});
    candidates.MeanThroughput_Mbps = -candidates.MeanThroughput_Mbps;
end
bestRow = candidates(1,:);
searchTable.Selected(:) = false;
match = searchTable.WeightIndex==bestRow.WeightIndex & ...
        abs(searchTable.Hysteresis-bestRow.Hysteresis)<1e-12;
searchTable.Selected(match) = true;
best = struct();
best.weights = weightGrid(bestRow.WeightIndex,:);
best.hysteresis = bestRow.Hysteresis;
best.feasible = logical(bestRow.QoSFeasible);
best.qosViolation = bestRow.QoSViolation;
best.pingPong = bestRow.PingPongHandovers;
best.handovers = bestRow.Handovers;
best.searchTable = searchTable;
end
%% ========================================================================
function cfg = set_selector_cfg(baseCfg,algorithm,weights,hysteresis)
cfg = baseCfg;
cfg.algorithm = algorithm;
cfg.weights = weights;
cfg.hysteresis = hysteresis;
cfg.plotResults = false;
cfg.verbose = false;
end
%% ========================================================================
function row = configuration_row(r,weights,hysteresis,cfg)
lat = r.meanSelectedMetrics(1);
loss = r.meanSelectedMetrics(2);
thr = r.meanSelectedMetrics(3);
feasible = lat <= cfg.qosLimits.maxLatency_ms && ...
    loss <= cfg.qosLimits.maxPacketLoss_percent && ...
    thr >= cfg.qosLimits.minThroughput_Mbps;
violation = max(0,lat/cfg.qosLimits.maxLatency_ms-1) + ...
    max(0,loss/cfg.qosLimits.maxPacketLoss_percent-1) + ...
    max(0,cfg.qosLimits.minThroughput_Mbps/max(thr,eps)-1);
row = [weights,hysteresis,r.switches,count_ping_pong(r.selectedLog,r.time), ...
    r.meanSelectedMetrics,r.modelledDataCost_R,feasible,violation];
end

function t = configuration_table(rows,algorithms)
t = array2table(rows,'VariableNames',{ ...
    'WeightLatency','WeightPacketLoss','WeightThroughput','WeightSignal', ...
    'WeightCost','Hysteresis','Handovers','PingPongHandovers', ...
    'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB','TotalDataCost_R', ...
    'QoSFeasible','QoSViolation'});
t = addvars(t,algorithms(:),'Before',1,'NewVariableNames','Algorithm');
end

function [signalReference,costReference] = supporting_metric_references(r,cfg)
% Match NetworkSim2's availability rule; terrestrial cellular/satellite links
% remain available. Signal is still a mixed-unit model criterion.
count = numel(r.time);
refs = zeros(count,2);
for k=1:count
    available = true(4,1);
    if cfg.wifi.enforceCoverage
        position = [r.xPos(k) r.yPos(k) 1.5];
        available(1) = norm(position-cfg.wifi.apPos) <= cfg.wifi.radius_m;
    end
    metrics = squeeze(r.metricsLog(k,:,:));
    refs(k,:) = [max(metrics(available,4)),min(metrics(available,5))];
end
signalReference = mean(refs(:,1));
costReference = mean(refs(:,2));
end
