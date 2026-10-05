function generate_report_plots()
%GENERATE_REPORT_PLOTS Report figures for the joint weight/hysteresis search.
%
% Run after run_experiments:
%   generate_report_plots
%
% Hysteresis sensitivity is extracted from the global-search tables at
% each algorithm's selected weight vector. No experiments are rerun.
clc;
resDir = fullfile(pwd,'experiment_results');
figDir = fullfile(resDir,'report_figures');
if ~exist(figDir,'dir')
    mkdir(figDir);
end
%% Load current experiment outputs
requiredFiles = {
    'algorithm_comparison.csv'
    'final_configuration.csv'
    'baseline_vs_final.csv'
    'final_oracle_comparison.csv'
    'global_search_SAW.csv'
    'global_search_TOPSIS.csv'
};
for i = 1:numel(requiredFiles)
    filePath = fullfile(resDir,requiredFiles{i});
    if ~isfile(filePath)
        error('Missing results file: %s',filePath);
    end
end
algTab = readtable(fullfile(resDir,'algorithm_comparison.csv'));
finalTab = readtable(fullfile(resDir,'final_configuration.csv'));
baseFinalTab = readtable(fullfile(resDir,'baseline_vs_final.csv'));
oracleTab = readtable(fullfile(resDir,'final_oracle_comparison.csv'));
searchSAW = readtable(fullfile(resDir,'global_search_SAW.csv'));
searchTOPSIS = readtable(fullfile(resDir,'global_search_TOPSIS.csv'));
methodNames = ["SAW","TOPSIS"];
% Explicitly order all comparison tables as SAW, then TOPSIS.
baseline = order_methods(algTab,methodNames);
finalTab = order_methods(finalTab,methodNames);
baseFinalTab = order_methods(baseFinalTab,methodNames);
oracleTab = order_methods(oracleTab,methodNames);
weightCols = {
    'WeightLatency'
    'WeightPacketLoss'
    'WeightThroughput'
    'WeightSignal'
    'WeightCost'
}';
%% Extract hysteresis sensitivity at the selected weights
searchTables = {searchSAW,searchTOPSIS};
hysteresisTables = cell(1,numel(methodNames));
for a = 1:numel(methodNames)
    searchTab = searchTables{a};
    selectedWeights = finalTab{a,weightCols};
    matches = all( ...
        abs(searchTab{:,weightCols} - selectedWeights) < 1e-10,2);
    slice = searchTab(matches,:);
    if isempty(slice)
        error(['Selected weights for %s were not found in the ' ...
               'global-search CSV. Ensure all CSVs come from the same run.'], ...
              char(methodNames(a)));
    end
    slice = sortrows(slice,'Hysteresis');
    selectedH = finalTab.Hysteresis(a);
    if ~any(abs(slice.Hysteresis-selectedH) < 1e-10)
        error('Selected hysteresis for %s is missing from its search table.', ...
              char(methodNames(a)));
    end
    hysteresisTables{a} = slice;
end
hystSAW = hysteresisTables{1};
hystTOPSIS = hysteresisTables{2};
algs = categorical(methodNames,methodNames);
%% Figure 1: baseline handover behaviour
f1 = figure( ...
    'Name','Fig 1: Baseline', ...
    'Position',[100 100 800 430]);
bar(algs, ...
    [baseline.Handovers,baseline.PingPongHandovers],'grouped');
ylabel('Count');
xlabel('Selection algorithm');
title('Baseline: Equal Weights and Zero Hysteresis');
legend({'Total handovers','Ping-pong returns'},'Location','best');
grid on;
saveas(f1,fullfile(figDir,'Fig1_Baseline_Handovers.png'));
%% Figure 2: selected weight vectors
f2 = figure( ...
    'Name','Fig 2: Selected Weights', ...
    'Position',[100 100 950 450]);
weights = finalTab{:,weightCols};
criterionNames = [
    "Latency"
    "Packet loss"
    "Throughput"
    "Signal quality"
    "Cost"
];
criteria = categorical(criterionNames,criterionNames);
bar(criteria,weights','grouped');
ylabel('Selected criterion weight');
xlabel('Selection criterion');
title('Weights Selected by the Joint Weight/Hysteresis Search');
legend({'SAW','TOPSIS'},'Location','best');
ylim([0 1]);
grid on;
saveas(f2,fullfile(figDir,'Fig2_Selected_Weights.png'));
%% Figure 3: hysteresis sensitivity at selected weights
f3 = figure( ...
    'Name','Fig 3: Hysteresis Sensitivity', ...
    'Position',[100 100 1100 850]);
metricFields = {
    'Handovers'
    'PingPongHandovers'
    'MeanLatency_ms'
    'MeanPacketLoss_percent'
    'MeanThroughput_Mbps'
};
metricLabels = {
    'Total handovers'
    'Ping-pong returns'
    'Mean latency (ms)'
    'Mean modelled packet loss (%)'
    'Mean estimated capacity (Mbps)'
};
panelTitles = {
    '(a) Handover count'
    '(b) Ping-pong behaviour'
    '(c) Latency'
    '(d) Packet loss'
    '(e) Capacity'
};
for panel = 1:numel(metricFields)
    subplot(3,2,panel);
    field = metricFields{panel};
    plot(hystSAW.Hysteresis,hystSAW.(field), ...
        'o-','LineWidth',1.2,'DisplayName','SAW');
    hold on;
    plot(hystTOPSIS.Hysteresis,hystTOPSIS.(field), ...
        's--','LineWidth',1.2,'DisplayName','TOPSIS');
    xline(finalTab.Hysteresis(1),':','SAW selected', ...
        'HandleVisibility','off');
    xline(finalTab.Hysteresis(2),'--','TOPSIS selected', ...
        'HandleVisibility','off');
    xlabel('Hysteresis margin');
    ylabel(metricLabels{panel});
    title(panelTitles{panel});
    legend('Location','best');
    grid on;
end
subplot(3,2,6);
axis off;
text(0,0.9, ...
    sprintf(['Each curve holds its algorithm''s selected weights fixed.\n\n' ...
             'Selected hysteresis:\nSAW: %.2f\nTOPSIS: %.2f\n\n' ...
             'These curves are slices of the joint grid search,\n' ...
             'not separate sequential optimisation experiments.'], ...
             finalTab.Hysteresis(1),finalTab.Hysteresis(2)), ...
    'Units','normalized', ...
    'VerticalAlignment','top', ...
    'FontSize',10);
sgtitle('Hysteresis Sensitivity at Each Algorithm''s Selected Weights');
saveas(f3,fullfile(figDir, ...
    'Fig3_Hysteresis_at_Selected_Weights.png'));
%% Figure 4: final modelled link QoS
f4 = figure( ...
    'Name','Fig 4: Final QoS', ...
    'Position',[100 100 1100 400]);
qosLabels = {
    'Mean latency (ms)'
    'Mean modelled packet loss (%)'
    'Mean estimated capacity (Mbps)'
};
qosTitles = {'Latency','Packet loss','Capacity'};
qosValues = [
    finalTab.MeanLatency_ms, ...
    finalTab.MeanPacketLoss_percent, ...
    finalTab.MeanThroughput_Mbps
];
for m = 1:3
    subplot(1,3,m);
    bar(algs,qosValues(:,m));
    ylabel(qosLabels{m});
    title(qosTitles{m});
    grid on;
end
sgtitle('Final Configurations: Modelled Link QoS');
saveas(f4,fullfile(figDir,'Fig4_Final_Core_QoS.png'));
%% Figure 5: selected versus independent per-metric references
f5 = figure( ...
    'Name','Fig 5: Per-Metric References', ...
    'Position',[100 100 1000 400]);
subplot(1,2,1);
bar(algs, ...
    [oracleTab.SelectedLatency_ms, ...
     oracleTab.MetricOracleLatency_ms],'grouped');
ylabel('Mean latency (ms)');
title('Selected vs Minimum-Latency Reference');
legend({'Selected','Per-metric reference'},'Location','best');
grid on;
subplot(1,2,2);
bar(algs, ...
    [oracleTab.SelectedPacketLoss_percent, ...
     oracleTab.MetricOraclePacketLoss_percent],'grouped');
ylabel('Mean modelled packet loss (%)');
title('Selected vs Minimum-Loss Reference');
legend({'Selected','Per-metric reference'},'Location','best');
grid on;
sgtitle('Independent Per-Metric Bounds: Not a Jointly Achievable Policy');
saveas(f5,fullfile(figDir,'Fig5_Final_Oracle_Comparison.png'));
%% Figure 6: baseline-to-final switching comparison
f6 = figure( ...
    'Name','Fig 6: Baseline to Final', ...
    'Position',[100 100 1000 430]);
subplot(1,2,1);
bar(algs, ...
    [baseFinalTab.BaselineHandovers, ...
     baseFinalTab.FinalHandovers],'grouped');
ylabel('Total handovers');
xlabel('Selection algorithm');
title('Baseline vs Final Handovers');
legend({'Baseline','Final'},'Location','best');
grid on;
subplot(1,2,2);
bar(algs, ...
    [baseFinalTab.BaselinePingPongHandovers, ...
     baseFinalTab.FinalPingPongHandovers],'grouped');
ylabel('Ping-pong returns');
xlabel('Selection algorithm');
title('Baseline vs Final Ping-Pong Behaviour');
legend({'Baseline','Final'},'Location','best');
grid on;
sgtitle('Switching Behaviour Before and After Configuration Selection');
saveas(f6,fullfile(figDir,'Fig6_Baseline_vs_Final_Switching.png'));
%% Appendix: single-criterion baseline comparison
f7 = figure( ...
    'Name','Appendix: Single-Criterion Comparison', ...
    'Position',[100 100 1150 450]);
allAlgorithmNames = string(algTab.Algorithm);
allAlgs = categorical(allAlgorithmNames,allAlgorithmNames);
appendixFields = {
    'MeanLatency_ms'
    'MeanPacketLoss_percent'
    'MeanThroughput_Mbps'
};
for m = 1:3
    subplot(1,3,m);
    bar(allAlgs,algTab.(appendixFields{m}));
    ylabel(qosLabels{m});
    title(qosTitles{m});
    xtickangle(35);
    grid on;
end
sgtitle('Baseline Comparison: Multi-Criteria and Single-Criterion Policies');
saveas(f7,fullfile(figDir,'Appendix_Single_Criterion_Comparison.png'));
%% Optional: robustness across random seeds
seedSummaryPath = fullfile(resDir,'random_seed_summary.csv');
if isfile(seedSummaryPath)
    seedSummary = readtable(seedSummaryPath);
    seedSummary = order_methods(seedSummary,methodNames);
    f8 = figure( ...
        'Name','Supporting: Random-Seed Robustness', ...
        'Position',[100 100 1100 430]);
    meanFields = {
        'Latency_Mean_ms'
        'PacketLoss_Mean_percent'
        'Throughput_Mean_Mbps'
    };
    sdFields = {
        'Latency_SD_ms'
        'PacketLoss_SD_percent'
        'Throughput_SD_Mbps'
    };
    for m = 1:3
        subplot(1,3,m);
        means = seedSummary.(meanFields{m});
        deviations = seedSummary.(sdFields{m});
        bar(1:2,means);
        hold on;
        errorbar(1:2,means,deviations, ...
            'k.','LineWidth',1.2,'CapSize',10);
        xticks(1:2);
        xticklabels({'SAW','TOPSIS'});
        xlim([0.5 2.5]);
        ylabel(qosLabels{m});
        title(qosTitles{m});
        grid on;
    end
    sgtitle('Normal Scenario: Mean +/- SD Across Random-Seed Runs');
    saveas(f8,fullfile(figDir,'Supporting_Random_Seed_Robustness.png'));
end
%% Experiment 7: fixed context-chosen weights
plot_experiment7(resDir,figDir,methodNames);

fprintf('\nReport figures generated in:\n%s\n',figDir);
end
%% ========================================================================
function orderedTable = order_methods(inputTable,methodNames)
% Extract exactly one row per requested method in the specified order.
rowIndices = zeros(numel(methodNames),1);
for a = 1:numel(methodNames)
    matches = find(string(inputTable.Algorithm)==methodNames(a));
    if numel(matches) ~= 1
        error('Expected exactly one row for %s; found %d.', ...
              char(methodNames(a)),numel(matches));
    end
    rowIndices(a) = matches;
end
orderedTable = inputTable(rowIndices,:);
end
%% ========================================================================
function plot_experiment7(resDir,figDir,methodNames)
% Plot saved Experiment 7 outputs; no simulation calls are made.
% Fixed weights [Latency, Loss, Capacity, Signal, Cost] = [.3 .3 .2 .1 .1].

sweepPath = fullfile(resDir,'fixed_weight_hysteresis_sensitivity.csv');
bestPath = fullfile(resDir,'fixed_weight_optimal_hysteresis.csv');

if ~isfile(sweepPath) || ~isfile(bestPath)
    error(['Experiment 7 CSVs are missing. Complete Experiment 7 first: ' ...
           'fixed_weight_hysteresis_sensitivity.csv and ' ...
           'fixed_weight_optimal_hysteresis.csv are required.']);
end

sweep = readtable(sweepPath);
best = order_methods(readtable(bestPath),methodNames);

fields = {'Handovers','PingPongHandovers','MeanLatency_ms', ...
          'MeanPacketLoss_percent','MeanThroughput_Mbps'};
labels = {'Total handovers','Ping-pong returns','Mean latency (ms)', ...
          'Mean modelled packet loss (%)','Mean estimated capacity (Mbps)'};
styles = {'o-','s--'};
colours = lines(numel(methodNames));
zeroRows = zeros(numel(methodNames),numel(fields));

f = figure('Name','Experiment 7: Fixed-Weight Hysteresis', ...
           'Position',[100 100 1100 850]);

for panel = 1:numel(fields)
    subplot(3,2,panel);
    hold on;
    for a = 1:numel(methodNames)
        t = sweep(string(sweep.Algorithm)==methodNames(a),:);
        t = sortrows(t,'Hysteresis');
        selected = t(abs(t.Hysteresis-best.Hysteresis(a))<1e-10,:);
        zero = t(abs(t.Hysteresis)<1e-10,:);

        if height(selected) ~= 1 || height(zero) ~= 1
            error(['Expected one selected and one H=0 row for %s. ' ...
                   'Ensure the Experiment 7 CSVs come from the same run.'], ...
                  char(methodNames(a)));
        end
        if any(abs(selected{1,fields}-best{a,fields}) > ...
               1e-8*max(1,abs(best{a,fields})))
            error('Experiment 7 sweep and selected outputs disagree for %s.', ...
                  char(methodNames(a)));
        end

        zeroRows(a,panel) = zero.(fields{panel});
        plot(t.Hysteresis,t.(fields{panel}),styles{a}, ...
             'Color',colours(a,:),'LineWidth',1.3, ...
             'DisplayName',char(methodNames(a)));
        plot(selected.Hysteresis,selected.(fields{panel}),'p', ...
             'MarkerSize',13,'MarkerFaceColor',colours(a,:), ...
             'MarkerEdgeColor','k','HandleVisibility','off');
        xline(best.Hysteresis(a),':','Color',colours(a,:), ...
              'HandleVisibility','off');
    end
    xlabel('Hysteresis margin');
    ylabel(labels{panel});
    title(labels{panel});
    legend('Location','best');
    grid on;
end

subplot(3,2,6);
axis off;
summary = sprintf(['Fixed weights [L, P, T, Q, C]:\n' ...
                   '[0.30, 0.30, 0.20, 0.10, 0.10]\n\n' ...
                   'Normal scenario; seed 16\n' ...
                   'Stars mark selected tested settings.\n\n']);
for a = 1:numel(methodNames)
    summary = [summary,sprintf('%s: H = %.2f; QoS feasible = %d\n', ...
               char(methodNames(a)),best.Hysteresis(a), ...
               best.QoSFeasible(a))]; %#ok<AGROW>
end
summary = [summary,sprintf(['\nSelection: QoS first, then ping-pong,\n' ...
                           'handovers and QoS tie-breaks.'])];
text(0,0.95,summary,'Units','normalized', ...
     'VerticalAlignment','top','FontSize',10,'Interpreter','none');
sgtitle('Experiment 7: Hysteresis Sensitivity with Fixed Context-Chosen Weights');
saveas(f,fullfile(figDir,'Exp7_Fixed_Weight_Hysteresis_Sensitivity.png'));
savefig(f,fullfile(figDir,'Exp7_Fixed_Weight_Hysteresis_Sensitivity.fig'));

% Compare H=0 and selected H with EXACTLY THE SAME fixed weights.
fCompare = figure('Name','Experiment 7: Zero vs Selected Hysteresis', ...
                  'Position',[100 100 1100 850]);
algs = categorical(methodNames,methodNames);
for panel = 1:numel(fields)
    subplot(3,2,panel);
    bar(algs,[zeroRows(:,panel),best.(fields{panel})],'grouped');
    ylabel(labels{panel});
    title(labels{panel});
    legend({'H = 0','Selected H'},'Location','best');
    grid on;
end
subplot(3,2,6);
axis off;
text(0,0.95, ...
     sprintf(['Both conditions use weights [.3 .3 .2 .1 .1].\n\n' ...
              'SAW selected H: %.2f\nTOPSIS selected H: %.2f\n\n' ...
              'This comparison isolates hysteresis;\n' ...
              'it does not use the equal-weight baseline.'], ...
              best.Hysteresis(1),best.Hysteresis(2)), ...
     'Units','normalized','VerticalAlignment','top','FontSize',10);
sgtitle('Experiment 7: Zero vs Selected Hysteresis at the Same Fixed Weights');
saveas(fCompare,fullfile(figDir,'Exp7_Zero_vs_Selected_Hysteresis.png'));
savefig(fCompare,fullfile(figDir,'Exp7_Zero_vs_Selected_Hysteresis.fig'));
end
