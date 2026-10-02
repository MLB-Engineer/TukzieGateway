function experimentResults = run_experiments()
% Automated network-selection experiments for the Smart Tuk-Tuk simulation.
%
% Algorithms:
%   SAW, TOPSIS, Throughput, Latency, PacketLoss, SignalStrength
%
% Main experiments:
%   1. Algorithm comparison / handovers
%   2. Hysteresis sensitivity
%   3. Weight-profile sensitivity for SAW/TOPSIS
%   4. Random-weight robustness for SAW/TOPSIS
%   5. Cost sensitivity
%   6. Network-degradation scenarios with FULL TIME-SERIES DATA
%   7. Single-criterion threshold sensitivity
%   8. Random-seed robustness
%
% IMPORTANT:
%   The SUMO trace is parsed once and then reused for all experiments.
%   The direct XML parser inside NetworkSim2 is not modified by this file.
%
% Experiment 6 exports timestep-level selected metrics for every algorithm
% and every degradation scenario. This allows plots such as:
%   SAW latency vs time versus TOPSIS latency vs time
%   SAW throughput vs time versus TOPSIS throughput vs time
%   SAW cost vs time versus TOPSIS cost vs time
% under normal, gradual, abrupt and combined degradation.

clc;
close all;

fprintf('\n====================================================\n');
fprintf(' AUTOMATED NETWORK-SELECTION EXPERIMENTS\n');
fprintf('====================================================\n\n');

%% Base configuration
baseCfg = simulation_config();
baseCfg.plotResults = false;
baseCfg.verbose = false;

outDir = fullfile(pwd,'experiment_results');
if ~exist(outDir,'dir')
    mkdir(outDir);
end

algorithms = ["SAW","TOPSIS","Throughput","Latency", ...
              "PacketLoss","SignalStrength"];
multiCriteriaAlgorithms = ["SAW","TOPSIS"];

%% Parse the SUMO trace once
fprintf('Checking SUMO trace and generating common baseline trace...\n');
baseCfg.algorithm = "SAW";
baseCfg.randomSeed = 16;
baseline = NetworkSim2(baseCfg);
traceData = baseline.traceData;

%% ================================================================
% 1. ALGORITHM COMPARISON
% ================================================================
fprintf('\n[1/8] Comparing selection algorithms...\n');

algorithmRows = zeros(numel(algorithms),16);

for i = 1:numel(algorithms)
    cfg = baseCfg;
    cfg.algorithm = algorithms(i);
    cfg.plotResults = false;
    cfg.verbose = false;

    r = NetworkSim2(cfg,traceData);
    pingPong = count_ping_pong(r.selectedLog,r.time);

    algorithmRows(i,:) = [ ...
        r.switches, r.handoverRate, pingPong, ...
        r.meanSelectedScore, r.meanOracleScore, r.oracleMatchRate, ...
        r.meanSelectedMetrics(1), r.meanSelectedMetrics(2), ...
        r.meanSelectedMetrics(3), r.meanSelectedMetrics(4), ...
        r.meanSelectedMetrics(5), r.modelledDataCost_R, r.timeOnNetwork];

    fprintf('  %-16s | handovers=%3d | ping-pong=%3d | agreement=%6.2f%%\n', ...
        char(algorithms(i)),r.switches,pingPong,r.oracleMatchRate);
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

% Export baseline time-series for every algorithm.
export_algorithm_timeseries(baseCfg,algorithms,traceData,outDir,16,'normal');

%% ================================================================
% 2. HYSTERESIS SWEEP
% ================================================================
fprintf('\n[2/8] Hysteresis sweep across all algorithms...\n');

hysteresisValues = 0:0.02:0.20;
hRows = [];

for a = 1:numel(algorithms)
    for h = 1:numel(hysteresisValues)
        cfg = baseCfg;
        cfg.algorithm = algorithms(a);
        cfg.hysteresis = hysteresisValues(h);
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);

        hRows(end+1,:) = [ ...
            a,hysteresisValues(h),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
end

hysteresisTable = array2table(hRows,'VariableNames',{ ...
    'AlgorithmID','Hysteresis','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB'});
hysteresisTable.Algorithm = algorithms(hysteresisTable.AlgorithmID)';
hysteresisTable = movevars(hysteresisTable,'Algorithm','Before',1);
hysteresisTable.AlgorithmID = [];
writetable(hysteresisTable,fullfile(outDir,'hysteresis_all_algorithms.csv'));

%% ================================================================
% 3. WEIGHT PROFILE SENSITIVITY
% ================================================================
fprintf('\n[3/8] Weight-profile sensitivity for SAW/TOPSIS...\n');

profileNames = ["Current","Balanced","LatencyFocus","LossFocus", ...
                "ThroughputFocus","SignalFocus","CostFocus"];
profileWeights = [ ...
    0.450 0.180 0.045 0.225 0.100; ...
    0.200 0.200 0.200 0.200 0.200; ...
    0.600 0.100 0.050 0.150 0.100; ...
    0.150 0.600 0.050 0.100 0.100; ...
    0.100 0.100 0.550 0.150 0.100; ...
    0.100 0.100 0.050 0.600 0.150; ...
    0.100 0.100 0.050 0.150 0.600];

wRows = [];

for a = 1:numel(multiCriteriaAlgorithms)
    for p = 1:numel(profileNames)
        cfg = baseCfg;
        cfg.algorithm = multiCriteriaAlgorithms(a);
        cfg.weights = profileWeights(p,:);
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);

        wRows(end+1,:) = [ ...
            a,p,cfg.weights,r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),r.modelledDataCost_R,r.timeOnNetwork]; %#ok<AGROW>
    end
end

weightTable = array2table(wRows,'VariableNames',{ ...
    'AlgorithmID','ProfileID','WeightLatency','WeightPacketLoss', ...
    'WeightThroughput','WeightSignal','WeightCost','Handovers', ...
    'PingPongHandovers','HandoversPerSecond','OracleAgreementPercent', ...
    'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB','TotalDataCost_R','TimeWiFi_percent', ...
    'TimeVodacom_percent','TimeMTN_percent','TimeSatellite_percent'});
weightTable.Algorithm = multiCriteriaAlgorithms(weightTable.AlgorithmID)';
weightTable.Profile = profileNames(weightTable.ProfileID)';
weightTable = movevars(weightTable,{'Algorithm','Profile'},'Before',1);
weightTable.AlgorithmID = [];
weightTable.ProfileID = [];
writetable(weightTable,fullfile(outDir,'weight_sensitivity.csv'));

% Evaluate candidate weight profiles using the project's core QoS metrics.
% This evaluation is deliberately separate from the selector's own weights:
% latency, packet loss, throughput and handovers are treated as outcomes.
weightTable = add_profile_evaluation(weightTable);
writetable(weightTable,fullfile(outDir,'weight_sensitivity.csv'));

selectedProfiles = select_best_profiles(weightTable);

%% Re-tune hysteresis using the selected weight profile for each MCDM method.
finalHRows = [];
finalHysteresisValues = hysteresisValues;
for a = 1:height(selectedProfiles)
    alg = string(selectedProfiles.Algorithm(a));
    w = [selectedProfiles.WeightLatency(a), selectedProfiles.WeightPacketLoss(a), ...
         selectedProfiles.WeightThroughput(a), selectedProfiles.WeightSignal(a), ...
         selectedProfiles.WeightCost(a)];

    % Reference run at H=0 with the selected weights.
    cfgRef = baseCfg;
    cfgRef.algorithm = alg;
    cfgRef.weights = w;
    cfgRef.hysteresis = 0;
    cfgRef.plotResults = false;
    cfgRef.verbose = false;
    ref = NetworkSim2(cfgRef,traceData);

    for h = 1:numel(finalHysteresisValues)
        cfg = cfgRef;
        cfg.hysteresis = finalHysteresisValues(h);
        r = NetworkSim2(cfg,traceData);
        finalHRows(end+1,:) = [ ...
            a,finalHysteresisValues(h),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            r.modelledDataCost_R, ...
            ref.meanSelectedMetrics(1),ref.meanSelectedMetrics(2),ref.meanSelectedMetrics(3)]; %#ok<AGROW>
    end
end

finalHysteresisTable = array2table(finalHRows,'VariableNames',{ ...
    'AlgorithmID','Hysteresis','Handovers','PingPongHandovers', ...
    'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','TotalDataCost_R','ReferenceLatency_ms', ...
    'ReferencePacketLoss_percent','ReferenceThroughput_Mbps'});
finalHysteresisTable.Algorithm = selectedProfiles.Algorithm(finalHysteresisTable.AlgorithmID);
finalHysteresisTable = movevars(finalHysteresisTable,'Algorithm','Before',1);
finalHysteresisTable.AlgorithmID = [];

selectedH = select_best_hysteresis(finalHysteresisTable,baseCfg);

% Final configuration: selected weight profile + selected hysteresis.
finalConfigRows = zeros(height(selectedProfiles),13);
for a = 1:height(selectedProfiles)
    alg = string(selectedProfiles.Algorithm(a));
    hidx = finalHysteresisTable.Algorithm == alg & ...
           finalHysteresisTable.Hysteresis == selectedH.Hysteresis(a);
    row = finalHysteresisTable(find(hidx,1),:);
    finalConfigRows(a,:) = [ ...
        selectedProfiles.WeightLatency(a),selectedProfiles.WeightPacketLoss(a), ...
        selectedProfiles.WeightThroughput(a),selectedProfiles.WeightSignal(a), ...
        selectedProfiles.WeightCost(a),selectedH.Hysteresis(a), ...
        row.Handovers,row.MeanLatency_ms,row.MeanPacketLoss_percent, ...
        row.MeanThroughput_Mbps,row.MeanSignalQuality_dB,row.TotalDataCost_R, ...
        selectedProfiles.CoreQoSScore(a)];
end

finalConfigurationTable = array2table(finalConfigRows,'VariableNames',{ ...
    'WeightLatency','WeightPacketLoss','WeightThroughput','WeightSignal', ...
    'WeightCost','Hysteresis','Handovers','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'TotalDataCost_R','CoreQoSScore'});
finalConfigurationTable = addvars(finalConfigurationTable,selectedProfiles.Algorithm, ...
    'Before',1,'NewVariableNames','Algorithm');
finalConfigurationTable = addvars(finalConfigurationTable,selectedProfiles.Profile, ...
    'After',1,'NewVariableNames','SelectedWeightProfile');
writetable(finalHysteresisTable,fullfile(outDir,'final_hysteresis_sensitivity.csv'));
writetable(finalConfigurationTable,fullfile(outDir,'final_configuration.csv'));

% Re-run each final configuration once to capture selected-vs-per-metric-oracle QoS.
oracleRows = zeros(height(finalConfigurationTable),5);
for a = 1:height(finalConfigurationTable)
    cfg = baseCfg;
    cfg.algorithm = string(finalConfigurationTable.Algorithm(a));
    cfg.weights = [finalConfigurationTable.WeightLatency(a), ...
        finalConfigurationTable.WeightPacketLoss(a), ...
        finalConfigurationTable.WeightThroughput(a), ...
        finalConfigurationTable.WeightSignal(a), ...
        finalConfigurationTable.WeightCost(a)];
    cfg.hysteresis = finalConfigurationTable.Hysteresis(a);
    cfg.plotResults = false;
    cfg.verbose = false;
    r = NetworkSim2(cfg,traceData);
    oracleRows(a,:) = [mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
        mean(r.selectedMetricsLog(:,3)),mean(r.metricOracleLog(:,1)), ...
        mean(r.metricOracleLog(:,2))];
end
oracleComparisonTable = array2table(oracleRows,'VariableNames',{ ...
    'SelectedLatency_ms','SelectedPacketLoss_percent','SelectedThroughput_Mbps', ...
    'MetricOracleLatency_ms','MetricOraclePacketLoss_percent'});
oracleComparisonTable = addvars(oracleComparisonTable,finalConfigurationTable.Algorithm, ...
    'Before',1,'NewVariableNames','Algorithm');
writetable(oracleComparisonTable,fullfile(outDir,'final_oracle_comparison.csv'));

% Final configuration comparison score. This is an outcome score, not the
% internal SAW/TOPSIS selection score: equal importance is given to the
% three project-critical QoS metrics plus handover count.
finalConfigurationTable.FinalAssessmentScore = final_outcome_score( ...
    finalConfigurationTable.MeanLatency_ms, ...
    finalConfigurationTable.MeanPacketLoss_percent, ...
    finalConfigurationTable.MeanThroughput_Mbps, ...
    finalConfigurationTable.Handovers);
writetable(finalConfigurationTable,fullfile(outDir,'final_configuration.csv'));

%% ================================================================
% 4. RANDOM WEIGHT SENSITIVITY
% ================================================================
fprintf('\n[4/8] Random-weight sensitivity...\n');

rng(2026);
numRandomWeights = 100;
randomWeightRows = [];

for a = 1:numel(multiCriteriaAlgorithms)
    for i = 1:numRandomWeights
        w = rand(1,5);
        w = w/sum(w);

        cfg = baseCfg;
        cfg.algorithm = multiCriteriaAlgorithms(a);
        cfg.weights = w;
        algName = string(multiCriteriaAlgorithms(a));
        hRow = selectedH.Hysteresis(selectedH.Algorithm == algName);
        cfg.hysteresis = hRow;
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);

        randomWeightRows(end+1,:) = [ ...
            a,i,w,r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.oracleMatchRate,mean(r.selectedMetricsLog(:,1)), ...
            mean(r.selectedMetricsLog(:,2)),mean(r.selectedMetricsLog(:,3)), ...
            mean(r.selectedMetricsLog(:,4)),mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
    fprintf('  %s random-weight runs complete.\n',char(multiCriteriaAlgorithms(a)));
end

randomWeightTable = array2table(randomWeightRows,'VariableNames',{ ...
    'AlgorithmID','Run','WeightLatency','WeightPacketLoss', ...
    'WeightThroughput','WeightSignal','WeightCost','Handovers', ...
    'PingPongHandovers','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB'});
randomWeightTable.Algorithm = multiCriteriaAlgorithms(randomWeightTable.AlgorithmID)';
randomWeightTable = movevars(randomWeightTable,'Algorithm','Before',1);
randomWeightTable.AlgorithmID = [];
writetable(randomWeightTable,fullfile(outDir,'random_weight_sensitivity.csv'));

%% ================================================================
% 5. COST SENSITIVITY
% ================================================================
fprintf('\n[5/8] Cost sensitivity...\n');

% Vary the satellite tariff because it is the fallback network and has a
% materially different tariff from terrestrial links. Report total modelled
% data cost rather than an instantaneous R/MB value.
costFactors = [0.25 0.5 1 2 5 10];
costRows = [];

for a = 1:height(finalConfigurationTable)
    alg = string(finalConfigurationTable.Algorithm(a));
    cfgBase = baseCfg;
    cfgBase.algorithm = alg;
    cfgBase.weights = [finalConfigurationTable.WeightLatency(a), ...
        finalConfigurationTable.WeightPacketLoss(a), ...
        finalConfigurationTable.WeightThroughput(a), ...
        finalConfigurationTable.WeightSignal(a), ...
        finalConfigurationTable.WeightCost(a)];
    cfgBase.hysteresis = finalConfigurationTable.Hysteresis(a);

    for f = 1:numel(costFactors)
        cfg = cfgBase;
        cfg.sat.cost_R_per_MB = baseCfg.sat.cost_R_per_MB*costFactors(f);
        cfg.plotResults = false;
        cfg.verbose = false;
        r = NetworkSim2(cfg,traceData);

        costRows(end+1,:) = [ ...
            a,costFactors(f),r.switches,mean(r.selectedMetricsLog(:,1)), ...
            mean(r.selectedMetricsLog(:,2)),mean(r.selectedMetricsLog(:,3)), ...
            r.modelledDataCost_R]; %#ok<AGROW>
    end
end

costTable = array2table(costRows,'VariableNames',{ ...
    'AlgorithmID','SatelliteCostFactor','Handovers','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','TotalDataCost_R'});
costTable.Algorithm = finalConfigurationTable.Algorithm(costTable.AlgorithmID);
costTable = movevars(costTable,'Algorithm','Before',1);
costTable.AlgorithmID = [];
writetable(costTable,fullfile(outDir,'cost_sensitivity.csv'));

%% ================================================================
% 6. NETWORK-DEGRADATION SCENARIOS + TIME SERIES
% ================================================================
fprintf('\n[6/8] Network-degradation scenarios and time-series analysis...\n');

scenarioNames = ["normal","gradual","abrupt","combined"];
scenarioRows = [];

degradationCfg = baseCfg;
degradationCfg.degradation.enabled = true;
degradationCfg.degradation.startFraction = 0.35;
degradationCfg.degradation.endFraction = 0.75;
degradationCfg.degradation.severity = 0.70;
% Fixed target for individual-network degradation. This avoids making the
% environment algorithm-dependent.
degradationCfg.degradation.targetNetworks = 1; % Wi-Fi

for sc = 1:numel(scenarioNames)
    for a = 1:numel(algorithms)
        cfg = degradationCfg;
        cfg.algorithm = algorithms(a);
        if cfg.algorithm == "SAW" || cfg.algorithm == "TOPSIS"
            fr = finalConfigurationTable(finalConfigurationTable.Algorithm == cfg.algorithm,:);
            cfg.weights = [fr.WeightLatency,fr.WeightPacketLoss,fr.WeightThroughput,fr.WeightSignal,fr.WeightCost];
            cfg.hysteresis = fr.Hysteresis;
        end
        cfg.degradation.scenario = scenarioNames(sc);
        cfg.plotResults = false;
        cfg.verbose = false;

        if scenarioNames(sc) == "combined"
            cfg.degradation.targetNetworks = [1 2 3];
        else
            cfg.degradation.targetNetworks = 1;
        end

        r = NetworkSim2(cfg,traceData);
        pingPong = count_ping_pong(r.selectedLog,r.time);

        scenarioRows(end+1,:) = [ ...
            sc,a,r.switches,pingPong,r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),r.modelledDataCost_R,r.timeOnNetwork]; %#ok<AGROW>

        % Every run gets its complete timestep-level data.
        export_single_timeseries(r,algorithms(a),16,scenarioNames(sc),outDir);
    end
end

scenarioTable = array2table(scenarioRows,'VariableNames',{ ...
    'ScenarioID','AlgorithmID','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB','TotalDataCost_R','TimeWiFi_percent','TimeVodacom_percent', ...
    'TimeMTN_percent','TimeSatellite_percent'});
scenarioTable.Scenario = reshape(scenarioNames(scenarioTable.ScenarioID), [], 1);
scenarioTable.Algorithm = reshape(algorithms(scenarioTable.AlgorithmID), [], 1);
scenarioTable = movevars(scenarioTable,{'Scenario','Algorithm'},'Before',1);
scenarioTable.ScenarioID = [];
scenarioTable.AlgorithmID = [];
writetable(scenarioTable,fullfile(outDir,'degradation_scenarios_summary.csv'));

% Create direct SAW-vs-TOPSIS time-series CSVs for convenient plotting.
export_saw_topsis_timeseries(baseCfg,traceData,outDir,finalConfigurationTable);

% Create metric-over-time plots for SAW and TOPSIS across all scenarios.
generate_degradation_timeseries_plots(outDir,scenarioNames);

%% ================================================================
% 7. SINGLE-CRITERION THRESHOLD SENSITIVITY
% ================================================================
fprintf('\n[7/8] Single-criterion threshold sensitivity...\n');

thresholdRows = [];

criterionNames = ["Throughput","Latency","PacketLoss","SignalStrength"];
thresholdValues = { ...
    [1 2 5 10 20 50], ...
    [20 50 75 100 150 200], ...
    [1 5 10 20 30 50], ...
    [-110 -100 -90 -80 -70 -60]};

for cidx = 1:numel(criterionNames)
    alg = criterionNames(cidx);
    values = thresholdValues{cidx};

    for v = 1:numel(values)
        cfg = baseCfg;
        cfg.algorithm = alg;
        cfg.plotResults = false;
        cfg.verbose = false;

        switch alg
            case "Throughput"
                cfg.threshold.throughput_Mbps = values(v);
            case "Latency"
                cfg.threshold.latency_ms = values(v);
            case "PacketLoss"
                cfg.threshold.packetLoss_percent = values(v);
            case "SignalStrength"
                cfg.threshold.signalQuality_dB = values(v);
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
thresholdTable.Criterion = reshape( ...
    criterionNames(thresholdTable.CriterionID),[],1);
thresholdTable = movevars(thresholdTable,'Criterion','Before',1);
thresholdTable.CriterionID = [];
writetable(thresholdTable,fullfile(outDir,'single_criterion_threshold_sensitivity.csv'));

generate_threshold_plot(thresholdTable);

%% ================================================================
% 8. RANDOM-SEED ROBUSTNESS
% ================================================================
fprintf('\n[8/8] Random-seed robustness...\n');

seeds = 1:10;
seedRows = [];

for a = 1:numel(algorithms)
    for s = 1:numel(seeds)
        cfg = baseCfg;
        cfg.algorithm = algorithms(a);
        if cfg.algorithm == "SAW" || cfg.algorithm == "TOPSIS"
            fr = finalConfigurationTable(finalConfigurationTable.Algorithm == cfg.algorithm,:);
            cfg.weights = [fr.WeightLatency,fr.WeightPacketLoss,fr.WeightThroughput,fr.WeightSignal,fr.WeightCost];
            cfg.hysteresis = fr.Hysteresis;
        end
        cfg.randomSeed = seeds(s);
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);

        totalDataCost_R = r.modelledDataCost_R;

        seedRows(end+1,:) = [ ...
            a,seeds(s),r.switches,count_ping_pong(r.selectedLog,r.time), ...
            r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),totalDataCost_R]; %#ok<AGROW>
    end
end

seedTable = array2table(seedRows,'VariableNames',{ ...
    'AlgorithmID','Seed','Handovers','PingPongHandovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB','TotalDataCost_R'});
seedTable.Algorithm = reshape( ...
    algorithms(seedTable.AlgorithmID),[],1);
seedTable = movevars(seedTable,'Algorithm','Before',1);
seedTable.AlgorithmID = [];
writetable(seedTable,fullfile(outDir,'random_seed_robustness.csv'));

%% Summary statistics across random seeds
summaryRows = [];

for a = 1:numel(algorithms)
    idx = seedTable.Algorithm == algorithms(a);

    h = seedTable.Handovers(idx);
    lat = seedTable.MeanLatency_ms(idx);
    loss = seedTable.MeanPacketLoss_percent(idx);
    thr = seedTable.MeanThroughput_Mbps(idx);
    cost = seedTable.MeanCost_R_per_MB(idx);
    costTotal = seedTable.TotalDataCost_R(idx);

    summaryRows(end+1,:) = [ ...
        mean(h),std(h), ...
        mean(thr),std(thr), ...
        mean(lat),std(lat), ...
        mean(loss),std(loss), ...
        mean(cost),std(cost), ...
        mean(costTotal),std(costTotal)]; %#ok<AGROW>
end

summaryTable = array2table(summaryRows,'VariableNames',{ ...
    'Handovers_Mean','Handovers_SD', ...
    'Throughput_Mean_Mbps','Throughput_SD_Mbps', ...
    'Latency_Mean_ms','Latency_SD_ms', ...
    'PacketLoss_Mean_percent','PacketLoss_SD_percent', ...
    'Cost_Mean_R_per_MB','Cost_SD_R_per_MB', ...
    'TotalDataCost_Mean_R','TotalDataCost_SD_R'});
summaryTable = addvars(summaryTable,algorithms(:), ...
    'Before',1,'NewVariableNames','Algorithm');
writetable(summaryTable,fullfile(outDir,'random_seed_summary.csv'));

performanceCostTable = summaryTable(:,{ ...
    'Algorithm','Throughput_Mean_Mbps','Throughput_SD_Mbps', ...
    'Latency_Mean_ms','Latency_SD_ms','Cost_Mean_R_per_MB', ...
    'Cost_SD_R_per_MB','TotalDataCost_Mean_R','TotalDataCost_SD_R', ...
    'Handovers_Mean','Handovers_SD'});
writetable(performanceCostTable, ...
    fullfile(outDir,'performance_cost_handover.csv'));

%% Save MATLAB structure
experimentResults = struct();
experimentResults.algorithmComparison = algorithmTable;
experimentResults.hysteresis = hysteresisTable;
experimentResults.weightSensitivity = weightTable;
experimentResults.finalHysteresis = finalHysteresisTable;
experimentResults.finalConfiguration = finalConfigurationTable;
experimentResults.finalOracleComparison = oracleComparisonTable;
experimentResults.randomWeights = randomWeightTable;
experimentResults.costSensitivity = costTable;
experimentResults.degradationScenarios = scenarioTable;
experimentResults.thresholdSensitivity = thresholdTable;
experimentResults.randomSeeds = seedTable;
experimentResults.randomSeedSummary = summaryTable;
experimentResults.baseline = baseline;

save(fullfile(outDir,'experimentResults.mat'),'experimentResults');

if exist('generate_report_plots','file') == 2
    generate_report_plots();
end

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
    selectedNetworkName(r.selectedLog == n) = r.networkNames(n);
end

detailTable = table( ...
    r.time(:),r.selectedLog(:),selectedNetworkName, ...
    r.selectedMetricsLog(:,1),r.selectedMetricsLog(:,2), ...
    r.selectedMetricsLog(:,3),r.selectedMetricsLog(:,4), ...
    r.selectedMetricsLog(:,5), ...
    'VariableNames',{ ...
    'Time_s','SelectedNetwork','SelectedNetworkName', ...
    'Latency_ms','PacketLoss_percent','Throughput_Mbps', ...
    'SignalQuality_dB','Cost_R_per_MB'});

detailTable.Algorithm = repmat(string(algorithm),height(detailTable),1);
detailTable.Seed = repmat(seed,height(detailTable),1);
detailTable.Scenario = repmat(string(scenario),height(detailTable),1);

detailTable = movevars(detailTable, ...
    {'Scenario','Algorithm','Seed'},'Before','Time_s');

filename = sprintf('timeseries_%s_seed%d_%s.csv', ...
    char(algorithm),seed,char(scenario));
writetable(detailTable,fullfile(outDir,filename));
end

%% ========================================================================
function export_saw_topsis_timeseries(baseCfg,traceData,outDir,finalConfigurationTable)
for scenario = ["normal","gradual","abrupt","combined"]
    cfgSAW = baseCfg;
    cfgSAW.algorithm = "SAW";
    cfgSAW.randomSeed = 16;
    cfgSAW.plotResults = false;
    cfgSAW.verbose = false;
    frSAW = finalConfigurationTable(finalConfigurationTable.Algorithm == "SAW",:);
    frTOP = finalConfigurationTable(finalConfigurationTable.Algorithm == "TOPSIS",:);
    cfgSAW.weights = [frSAW.WeightLatency,frSAW.WeightPacketLoss,frSAW.WeightThroughput,frSAW.WeightSignal,frSAW.WeightCost];
    cfgSAW.hysteresis = frSAW.Hysteresis;
    cfgSAW.degradation.enabled = true;
    cfgSAW.degradation.scenario = scenario;
    cfgSAW.degradation.startFraction = 0.35;
    cfgSAW.degradation.endFraction = 0.75;
    cfgSAW.degradation.severity = 0.70;
    cfgSAW.degradation.targetNetworks = 1;
    if scenario == "combined"
        cfgSAW.degradation.targetNetworks = [1 2 3];
    end

    cfgTOPSIS = cfgSAW;
    cfgTOPSIS.algorithm = "TOPSIS";
    cfgTOPSIS.weights = [frTOP.WeightLatency,frTOP.WeightPacketLoss,frTOP.WeightThroughput,frTOP.WeightSignal,frTOP.WeightCost];
    cfgTOPSIS.hysteresis = frTOP.Hysteresis;

    saw = NetworkSim2(cfgSAW,traceData);
    topsis = NetworkSim2(cfgTOPSIS,traceData);

    out = table( ...
        saw.time(:), ...
        saw.selectedLog(:),topsis.selectedLog(:), ...
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

    writetable(out,fullfile(outDir, ...
        sprintf('SAW_vs_TOPSIS_timeseries_%s.csv',char(scenario))));
end
end

%% ========================================================================
function count = count_ping_pong(selectedLog, time, T_pp)
% Counts A->B->A handover patterns occurring within T_pp seconds (default: 1.0s)
if nargin < 3 || isempty(T_pp)
    T_pp = 1.0; 
end

if numel(selectedLog) < 3 || nargin < 2 || numel(time) ~= numel(selectedLog)
    count = 0;
    return;
end

switchIdx = find(diff(selectedLog) ~= 0);
if numel(switchIdx) < 2
    count = 0;
    return;
end

switchNetworks = selectedLog(switchIdx + 1);
switchTimes = time(switchIdx + 1);

count = 0;
for i = 3:numel(switchNetworks)
    % Check for A -> B -> A sequence
    if switchNetworks(i) == switchNetworks(i-2) && switchNetworks(i) ~= switchNetworks(i-1)
        % Measure dwell time on intermediate network B
        dwellTime = switchTimes(i) - switchTimes(i-1);
        if dwellTime <= T_pp
            count = count + 1;
        end
    end
end
end
function score = final_outcome_score(lat,loss,thr,hand)
score = 0.25*(inverse_minmax(lat) + inverse_minmax(loss) + ...
    direct_minmax(thr) + inverse_minmax(hand));
end

%% ========================================================================
function t = add_profile_evaluation(t)
% Evaluate candidate weight profiles using outcome metrics, not selector score.
% Equal importance is assigned to latency, packet loss, throughput and
% handovers because these are the observable system-level outcomes used in
% the investigation. Cost and signal quality remain supporting metrics.

algorithms = unique(string(t.Algorithm),'stable');
t.CoreQoSScore = zeros(height(t),1);
t.QoSFeasible = false(height(t),1);

for a = 1:numel(algorithms)
    idx = string(t.Algorithm) == algorithms(a);

    lat = t.MeanLatency_ms(idx);
    loss = t.MeanPacketLoss_percent(idx);
    thr = t.MeanThroughput_Mbps(idx);
    hand = t.Handovers(idx);

    latScore = inverse_minmax(lat);
    lossScore = inverse_minmax(loss);
    thrScore = direct_minmax(thr);
    handScore = inverse_minmax(hand);

    t.CoreQoSScore(idx) = 0.25*(latScore + lossScore + thrScore + handScore);
    t.QoSFeasible(idx) = lat <= simulation_config().qosLimits.maxLatency_ms & ...
        loss <= simulation_config().qosLimits.maxPacketLoss_percent & ...
        thr >= simulation_config().qosLimits.minThroughput_Mbps;
end
end

function selected = select_best_profiles(t)
algorithms = unique(string(t.Algorithm),'stable');
rows = zeros(numel(algorithms),1);
for a = 1:numel(algorithms)
    idx = find(string(t.Algorithm) == algorithms(a));
    feasible = idx(t.QoSFeasible(idx));
    if isempty(feasible)
        candidates = idx;
    else
        candidates = feasible;
    end
    score = t.CoreQoSScore(candidates);
    bestScore = max(score);
    candidates = candidates(abs(score-bestScore) < 1e-12);
    if numel(candidates) > 1
        [~,j] = min(t.TotalDataCost_R(candidates));
        candidates = candidates(j);
    end
    if numel(candidates) > 1
        [~,j] = min(t.Handovers(candidates));
        candidates = candidates(j);
    end
    rows(a) = candidates(1);
end
selected = t(rows,:);
end

function selected = select_best_hysteresis(t,cfg)
algorithms = unique(string(t.Algorithm),'stable');
selected = table(strings(numel(algorithms),1),zeros(numel(algorithms),1), ...
    'VariableNames',{'Algorithm','Hysteresis'});

for a = 1:numel(algorithms)
    idx = string(t.Algorithm) == algorithms(a);
    rows = t(idx,:);
    ref = rows(abs(rows.Hysteresis) < 1e-12,:);
    if isempty(ref)
        error('Hysteresis sweep must include H=0 for %s.',algorithms(a));
    end

    feasible = rows.Hysteresis >= 0 & ...
        rows.MeanLatency_ms <= ref.MeanLatency_ms*(1+cfg.optimization.maxLatencyIncreaseFraction) & ...
        rows.MeanThroughput_Mbps >= ref.MeanThroughput_Mbps*cfg.optimization.minThroughputRetentionFraction & ...
        rows.MeanPacketLoss_percent <= ref.MeanPacketLoss_percent + cfg.optimization.maxPacketLossIncrease_percent;

    candidates = rows(feasible,:);
    if isempty(candidates)
        candidates = ref;
    end

    % Select the largest hysteresis that remains within the QoS tolerances.
    % This explicitly favours fewer unnecessary handovers after performance
    % degradation remains acceptably small.
    h = max(candidates.Hysteresis);
    selected.Algorithm(a) = algorithms(a);
    selected.Hysteresis(a) = h;
end
end

function y = inverse_minmax(x)
lo = min(x); hi = max(x);
if hi-lo < eps
    y = ones(size(x));
else
    y = (hi-x)/(hi-lo);
end
end

function y = direct_minmax(x)
lo = min(x); hi = max(x);
if hi-lo < eps
    y = ones(size(x));
else
    y = (x-lo)/(hi-lo);
end
end

%% ========================================================================
function generate_threshold_plot(t)
figure('Name','Single-Criterion Threshold Sensitivity');
methods = unique(t.Criterion,'stable');
for i = 1:numel(methods)
    idx = t.Criterion == methods(i);
    plot(t.Threshold(idx),t.Handovers(idx),'o-','LineWidth',1.2); hold on;
end
xlabel('Threshold value'); ylabel('Handovers');
legend(methods,'Location','best');
title('Single-Criterion Threshold Sensitivity'); grid on;
end

%% ========================================================================
function generate_degradation_timeseries_plots(outDir,scenarioNames)
figDir = fullfile(outDir,'report_figures');
if ~exist(figDir,'dir'), mkdir(figDir); end
% One figure per degradation scenario. Each figure contains only the three
% project-critical end-to-end metrics: latency, packet loss and throughput.

sawVars = {'SAW_Latency_ms','SAW_PacketLoss_percent','SAW_Throughput_Mbps'};
topVars = {'TOPSIS_Latency_ms','TOPSIS_PacketLoss_percent','TOPSIS_Throughput_Mbps'};
yLabels = {'Latency (ms)','Packet loss (%)','Throughput (Mbps)'};

for s = 1:numel(scenarioNames)
    filename = fullfile(outDir,sprintf('SAW_vs_TOPSIS_timeseries_%s.csv',char(scenarioNames(s))));
    T = readtable(filename);

    f = figure('Name',['Degradation - ',char(scenarioNames(s))], ...
        'Position',[100 100 900 700]);

    for m = 1:3
        subplot(3,1,m);
        if ~ismember(sawVars{m},T.Properties.VariableNames) || ...
                ~ismember(topVars{m},T.Properties.VariableNames)
            error('Expected SAW/TOPSIS time-series variables are missing from %s.',filename);
        end
        plot(T.Time_s,T.(sawVars{m}),'LineWidth',1.2,'DisplayName','SAW'); hold on;
        plot(T.Time_s,T.(topVars{m}),'--','LineWidth',1.2,'DisplayName','TOPSIS');
        ylabel(yLabels{m}); grid on;
        legend('Location','best');
        if m == 1
            title(['Degradation scenario: ',char(scenarioNames(s))]);
        end
        if m == 3
            xlabel('Time (s)');
        end
    end

    saveas(f,fullfile(outDir,'report_figures',['Degradation_',char(scenarioNames(s)),'.png']));
end
end

