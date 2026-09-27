function experimentResults = run_experiments()
% Automated comparison of network-selection algorithms.
%
% Algorithms compared:
%   SAW
%   TOPSIS
%   Throughput + threshold + hysteresis
%   Latency + threshold + hysteresis
%   Packet loss + threshold + hysteresis
%   Signal strength + threshold + hysteresis
%
% Experiments:
%   1. Algorithm comparison using identical network conditions
%   2. Hysteresis sweep across all algorithms
%   3. SAW/TOPSIS weight-profile sensitivity
%   4. Random weight sensitivity for SAW/TOPSIS
%   5. Cost sensitivity
%   6. Random-seed robustness
%
% Outputs are written to ./experiment_results/ as CSV and MAT files.

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

%% Parse the SUMO trace once
fprintf('Checking SUMO trace and generating common baseline metrics...\n');
baseCfg.algorithm = "SAW";
baseCfg.randomSeed = 16;
baseline = NetworkSim2(baseCfg);
traceData = baseline.traceData;

%% ================================================================
% 1. ALGORITHM COMPARISON
% ================================================================
fprintf('\n[1/6] Comparing selection algorithms...\n');

algorithmRows = zeros(numel(algorithms),18);

for i = 1:numel(algorithms)
    cfg = baseCfg;
    cfg.algorithm = algorithms(i);
    cfg.plotResults = false;
    cfg.verbose = false;

    r = NetworkSim2(cfg,traceData);

    algorithmRows(i,:) = [ ...
        r.switches, ...
        r.handoverRate, ...
        r.meanSelectedScore, ...
        r.meanOracleScore, ...
        r.oracleMatchRate, ...
        r.meanSelectedMetrics(1), ...
        r.meanSelectedMetrics(2), ...
        r.meanSelectedMetrics(3), ...
        r.meanSelectedMetrics(4), ...
        r.meanSelectedMetrics(5), ...
        r.timeOnNetwork(1), ...
        r.timeOnNetwork(2), ...
        r.timeOnNetwork(3), ...
        r.timeOnNetwork(4), ...
        mean(r.selectedMetricsLog(:,3)), ...
        mean(r.selectedMetricsLog(:,1)), ...
        mean(r.selectedMetricsLog(:,2)), ...
        mean(r.selectedMetricsLog(:,5))];

    fprintf('  %-16s | handovers=%3d | agreement=%6.2f%% | throughput=%8.2f Mbps\n', ...
        char(algorithms(i)),r.switches,r.oracleMatchRate,mean(r.selectedMetricsLog(:,3)));
end

algorithmTable = array2table(algorithmRows,'VariableNames',{ ...
    'Handovers', ...
    'HandoversPerSecond', ...
    'MeanSelectedScore', ...
    'MeanOracleScore', ...
    'OracleAgreementPercent', ...
    'MeanLatency_ms', ...
    'MeanPacketLoss_percent', ...
    'MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB', ...
    'TimeWiFi_percent', ...
    'TimeVodacom_percent', ...
    'TimeMTN_percent', ...
    'TimeSatellite_percent', ...
    'SelectedThroughput_Mbps', ...
    'SelectedLatency_ms', ...
    'SelectedPacketLoss_percent', ...
    'SelectedCost_R_per_MB'});
algorithmTable = addvars(algorithmTable,algorithms(:),'Before',1,'NewVariableNames','Algorithm');
writetable(algorithmTable,fullfile(outDir,'algorithm_comparison.csv'));

%% ================================================================
% 2. HYSTERESIS SWEEP
% ================================================================
fprintf('\n[2/6] Hysteresis sweep across all algorithms...\n');

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
            a, hysteresisValues(h), r.switches, r.handoverRate, ...
            r.oracleMatchRate, mean(r.selectedMetricsLog(:,1)), ...
            mean(r.selectedMetricsLog(:,2)), mean(r.selectedMetricsLog(:,3)), ...
            mean(r.selectedMetricsLog(:,4)), mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
end

hysteresisTable = array2table(hRows,'VariableNames',{ ...
    'AlgorithmID','Hysteresis','Handovers','HandoversPerSecond', ...
    'OracleAgreementPercent','MeanLatency_ms','MeanPacketLoss_percent', ...
    'MeanThroughput_Mbps','MeanSignalQuality_dB','MeanCost_R_per_MB'});
hysteresisTable.Algorithm = algorithms(hysteresisTable.AlgorithmID)';
hysteresisTable = movevars(hysteresisTable,'Algorithm','Before',1);
hysteresisTable.AlgorithmID = [];
writetable(hysteresisTable,fullfile(outDir,'hysteresis_all_algorithms.csv'));

%% ================================================================
% 3. WEIGHT PROFILE SENSITIVITY
% ================================================================
fprintf('\n[3/6] Weight-profile sensitivity for SAW/TOPSIS...\n');

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

multiCriteriaAlgorithms = ["SAW","TOPSIS"];
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
            a,p,cfg.weights,r.switches,r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)),r.timeOnNetwork]; %#ok<AGROW>
    end
end

weightTable = array2table(wRows,'VariableNames',{ ...
    'AlgorithmID','ProfileID','WeightLatency','WeightPacketLoss', ...
    'WeightThroughput','WeightSignal','WeightCost','Handovers', ...
    'HandoversPerSecond','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanSignalQuality_dB', ...
    'MeanCost_R_per_MB','TimeWiFi_percent','TimeVodacom_percent', ...
    'TimeMTN_percent','TimeSatellite_percent'});
weightTable.Algorithm = multiCriteriaAlgorithms(weightTable.AlgorithmID)';
weightTable.Profile = profileNames(weightTable.ProfileID)';
weightTable = movevars(weightTable,{'Algorithm','Profile'},'Before',1);
weightTable.AlgorithmID = [];
weightTable.ProfileID = [];
writetable(weightTable,fullfile(outDir,'weight_sensitivity.csv'));

%% ================================================================
% 4. RANDOM WEIGHT SENSITIVITY
% ================================================================
fprintf('\n[4/6] Random-weight sensitivity...\n');

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
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);

        randomWeightRows(end+1,:) = [ ...
            a,i,w,r.switches,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5))]; %#ok<AGROW>
    end
    fprintf('  %s random-weight runs complete.\n',char(multiCriteriaAlgorithms(a)));
end

randomWeightTable = array2table(randomWeightRows,'VariableNames',{ ...
    'AlgorithmID','Run','WeightLatency','WeightPacketLoss','WeightThroughput', ...
    'WeightSignal','WeightCost','Handovers','OracleAgreementPercent', ...
    'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps', ...
    'MeanSignalQuality_dB','MeanCost_R_per_MB'});
randomWeightTable.Algorithm = multiCriteriaAlgorithms(randomWeightTable.AlgorithmID)';
randomWeightTable = movevars(randomWeightTable,'Algorithm','Before',1);
randomWeightTable.AlgorithmID = [];
writetable(randomWeightTable,fullfile(outDir,'random_weight_sensitivity.csv'));

%% ================================================================
% 5. COST SENSITIVITY
% ================================================================
fprintf('\n[5/6] Cost sensitivity...\n');

costFactors = [0.25 0.5 1 2 5 10];
costRows = [];

for f = 1:numel(costFactors)
    cfg = baseCfg;
    cfg.algorithm = "SAW";
    cfg.costFactor = costFactors(f); %#ok<STRNU>
    cfg.wifi.cost_R_per_MB = baseCfg.wifi.cost_R_per_MB*costFactors(f);
    cfg.vodacom.cost_R_per_MB = baseCfg.vodacom.cost_R_per_MB*costFactors(f);
    cfg.mtn.cost_R_per_MB = baseCfg.mtn.cost_R_per_MB*costFactors(f);
    cfg.sat.cost_R_per_MB = baseCfg.sat.cost_R_per_MB*costFactors(f);
    cfg.plotResults = false;
    cfg.verbose = false;

    r = NetworkSim2(cfg,traceData);

    costRows(end+1,:) = [ ...
        costFactors(f),r.switches,r.oracleMatchRate, ...
        mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
        mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,5)), ...
        r.timeOnNetwork]; %#ok<AGROW>
end

costTable = array2table(costRows,'VariableNames',{ ...
    'CostFactor','Handovers','OracleAgreementPercent','MeanLatency_ms', ...
    'MeanPacketLoss_percent','MeanThroughput_Mbps','MeanCost_R_per_MB', ...
    'TimeWiFi_percent','TimeVodacom_percent','TimeMTN_percent', ...
    'TimeSatellite_percent'});
writetable(costTable,fullfile(outDir,'cost_sensitivity.csv'));

%% ================================================================
% 6. RANDOM-SEED ROBUSTNESS
% ================================================================
fprintf('\n[6/6] Random-seed robustness...\n');

seeds = 1:10;
seedRows = [];

for a = 1:numel(algorithms)
    for s = 1:numel(seeds)
        cfg = baseCfg;
        cfg.algorithm = algorithms(a);
        cfg.randomSeed = seeds(s);
        cfg.plotResults = false;
        cfg.verbose = false;

        r = NetworkSim2(cfg,traceData);
        %% Total data cost

        throughput_Mbps = r.selectedMetricsLog(:,3);
        cost_R_per_MB = r.selectedMetricsLog(:,5);

        dt = mean(diff(r.time));

        % Mbps -> MB/s
        data_MB = throughput_Mbps * 0.125 * dt;

        totalDataCost_R = sum(data_MB .* cost_R_per_MB);

        % Export timestep-level selected-network data
        %time might be missing
        detailTable = table( ...
            r.time(:), ...
            r.selectedLog(:), ...
            r.selectedMetricsLog(:,1), ...
            r.selectedMetricsLog(:,2), ...
            r.selectedMetricsLog(:,3), ...
            r.selectedMetricsLog(:,4), ...
            r.selectedMetricsLog(:,5), ...
            'VariableNames', { ...
            'Time_s', ...
            'SelectedNetwork', ...
            'Latency_ms', ...
            'PacketLoss_percent', ...
            'Throughput_Mbps', ...
            'SignalQuality_dB', ...
            'Cost_R_per_MB'});

        detailTable.Algorithm = repmat(algorithms(a),height(detailTable),1);
        detailTable.Seed = repmat(seeds(s),height(detailTable),1);

        detailTable = movevars(detailTable, ...
            {'Algorithm','Seed'},'Before','Time_s');

        writetable(detailTable, fullfile(outDir, ...
            sprintf('timeseries_%s_seed%d.csv', ...
            char(algorithms(a)), seeds(s))));

        seedRows(end+1,:) = [ ...
            a,seeds(s),r.switches,r.handoverRate,r.oracleMatchRate, ...
            mean(r.selectedMetricsLog(:,1)),mean(r.selectedMetricsLog(:,2)), ...
            mean(r.selectedMetricsLog(:,3)),mean(r.selectedMetricsLog(:,4)), ...
            mean(r.selectedMetricsLog(:,5)), totalDataCost_R]; %#ok<AGROW>
    end
end

seedTable = array2table(seedRows,'VariableNames',{ ...
    'AlgorithmID','Seed','Handovers','HandoversPerSecond', ...
    'OracleAgreementPercent','MeanLatency_ms','MeanPacketLoss_percent', ...
    'MeanThroughput_Mbps','MeanSignalQuality_dB','MeanCost_R_per_MB','TotalDataCost_R'});
seedTable.Algorithm = algorithms(seedTable.AlgorithmID)';
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
    costTotal = seedTable.TotalDataCost_R;

    summaryRows(end+1,:) = [ ...
        mean(h), std(h), ...
        mean(thr), std(thr), ...
        mean(lat), std(lat), ...
        mean(loss), std(loss), ...
        mean(cost), std(cost),
        mean(costTotal), std(costTotal)]; %#ok<AGROW>
end

summaryTable = array2table(summaryRows, ...
    'VariableNames',{ ...
    'Handovers_Mean','Handovers_SD', ...
    'Throughput_Mean_Mbps','Throughput_SD_Mbps', ...
    'Latency_Mean_ms','Latency_SD_ms', ...
    'PacketLoss_Mean_percent','PacketLoss_SD_percent', ...
    'Cost_Mean_R','Cost_SD_R', ...
    'Cost_Total_R','Cost_Total_R'});

summaryTable = addvars(summaryTable,algorithms(:), ...
    'Before',1,'NewVariableNames','Algorithm');

writetable(summaryTable, ...
    fullfile(outDir,'random_seed_summary.csv'));

%% Performance vs cost summary

performanceCostTable = summaryTable(:, ...
    {'Algorithm', ...
    'Throughput_Mean_Mbps', ...
    'Throughput_SD_Mbps', ...
    'Cost_Mean_R', ...
    'Cost_SD_R', ...
    'Handovers_Mean', ...
    'Handovers_SD'});

writetable(performanceCostTable, ...
    fullfile(outDir,'performance_cost_handover.csv'));

%% Save MATLAB structure
experimentResults = struct();
experimentResults.algorithmComparison = algorithmTable;
experimentResults.hysteresis = hysteresisTable;
experimentResults.weightSensitivity = weightTable;
experimentResults.randomWeights = randomWeightTable;
experimentResults.costSensitivity = costTable;
experimentResults.randomSeeds = seedTable;
experimentResults.baseline = baseline;

save(fullfile(outDir,'experimentResults.mat'),'experimentResults');

generate_experiment_plots(algorithmTable,hysteresisTable,weightTable,costTable);

fprintf('\n====================================================\n');
fprintf(' EXPERIMENTS COMPLETE\n');
fprintf(' Results saved to:\n %s\n',outDir);
fprintf('====================================================\n\n');
end

%% ========================================================================
function generate_experiment_plots(a,h,w,c)

figure('Name','Algorithm Comparison');
bar(categorical(a.Algorithm),[a.MeanThroughput_Mbps,a.MeanLatency_ms]);
ylabel('Metric value');
legend('Mean Throughput (Mbps)','Mean Latency (ms)','Location','best');
title('Selection-Algorithm Comparison'); grid on;

figure('Name','Algorithm Handovers');
bar(categorical(a.Algorithm),a.Handovers);
ylabel('Handovers');
title('Number of Network Handovers by Algorithm'); grid on;

figure('Name','Hysteresis Comparison');
methods = unique(h.Algorithm,'stable');
for i = 1:numel(methods)
    idx = h.Algorithm == methods(i);
    plot(h.Hysteresis(idx),h.Handovers(idx),'o-','LineWidth',1.2); hold on;
end
xlabel('Hysteresis'); ylabel('Handovers');
legend(methods,'Location','best');
title('Hysteresis Sensitivity Across Selection Methods'); grid on;

figure('Name','Weight Profile Network Usage');
idxSAW = w.Algorithm == "SAW";
bar(categorical(w.Profile(idxSAW)), ...
    [w.TimeWiFi_percent(idxSAW),w.TimeVodacom_percent(idxSAW), ...
     w.TimeMTN_percent(idxSAW),w.TimeSatellite_percent(idxSAW)],'stacked');
ylabel('Time selected (%)');
legend('Wi-Fi','Vodacom 5G','MTN 5G','Satellite','Location','best');
title('SAW Network Selection Under Different Weight Profiles'); grid on;

figure('Name','Cost Sensitivity');
plot(c.CostFactor,c.MeanCost_R_per_MB,'o-','LineWidth',1.5);
xlabel('Cost multiplier'); ylabel('Mean selected cost (R/MB)');
title('SAW Sensitivity to Network Cost'); grid on;

figure('Name','Cost Sensitivity Network Usage');
bar(c.CostFactor,[c.TimeWiFi_percent,c.TimeVodacom_percent, ...
    c.TimeMTN_percent,c.TimeSatellite_percent],'stacked');
xlabel('Cost multiplier'); ylabel('Time selected (%)');
legend('Wi-Fi','Vodacom 5G','MTN 5G','Satellite','Location','best');
title('Effect of Relative Network Cost on SAW Selection'); grid on;
end
