function generate_report_plots()
%GENERATE_REPORT_PLOTS Report figures aligned with the GA4 investigation.
%
% Main report figures:
%   Fig 1 - Baseline SAW vs TOPSIS handovers
%   Fig 2 - Hysteresis trade-offs and selected optimum
%   Fig 3 - Core QoS at the final tested configuration
%   Fig 4 - Selected solution versus per-metric oracle
%   Fig 5 - Total modelled data cost at the final configuration
%
% Degradation scenarios are exported separately by run_experiments.m.

clc;

resDir = fullfile(pwd,'experiment_results');
figDir = fullfile(resDir,'report_figures');
if ~exist(figDir,'dir'), mkdir(figDir); end

algTab   = readtable(fullfile(resDir,'algorithm_comparison.csv'));
hystTab  = readtable(fullfile(resDir,'final_hysteresis_sensitivity.csv'));
weightTab = readtable(fullfile(resDir,'weight_sensitivity.csv'));
finalTab = readtable(fullfile(resDir,'final_configuration.csv'));
oracleTab = readtable(fullfile(resDir,'final_oracle_comparison.csv'));
costTab  = readtable(fullfile(resDir,'cost_sensitivity.csv'));

idx = ismember(string(algTab.Algorithm),["SAW","TOPSIS"]);
baseline = algTab(idx,:);

% ================================================================
% Figure 1 - Baseline handover behaviour
% ================================================================
f1 = figure('Name','Fig 1: Baseline SAW vs TOPSIS', ...
    'Units','pixels','Position',[100 100 700 430]);

algs = categorical(string(baseline.Algorithm),["SAW","TOPSIS"]);
b = bar(algs,[baseline.Handovers,baseline.PingPongHandovers],'grouped');
ylabel('Count');
xlabel('Selection algorithm');
title('Experiment 1: Baseline Handover Behaviour');
legend({'Total handovers','Ping-pong handovers'},'Location','best');
grid on;

saveas(f1,fullfile(figDir,'Fig1_Exp1_Baseline_Handovers.png'));

% ================================================================
% Figure 2 - Hysteresis trade-offs
% ================================================================
f2 = figure('Name','Fig 2: Hysteresis Optimization', ...
    'Units','pixels','Position',[100 100 1000 700]);

for panel = 1:4
    subplot(2,2,panel);
    idxS = string(hystTab.Algorithm)=="SAW";
    idxT = string(hystTab.Algorithm)=="TOPSIS";

    switch panel
        case 1
            plot(hystTab.Hysteresis(idxS),hystTab.Handovers(idxS),'o-','DisplayName','SAW'); hold on;
            plot(hystTab.Hysteresis(idxT),hystTab.Handovers(idxT),'s--','DisplayName','TOPSIS');
            ylabel('Total handovers');
            title('(a) Handover count');
        case 2
            plot(hystTab.Hysteresis(idxS),hystTab.MeanLatency_ms(idxS),'o-','DisplayName','SAW'); hold on;
            plot(hystTab.Hysteresis(idxT),hystTab.MeanLatency_ms(idxT),'s--','DisplayName','TOPSIS');
            ylabel('Mean latency (ms)');
            title('(b) Latency');
        case 3
            plot(hystTab.Hysteresis(idxS),hystTab.MeanPacketLoss_percent(idxS),'o-','DisplayName','SAW'); hold on;
            plot(hystTab.Hysteresis(idxT),hystTab.MeanPacketLoss_percent(idxT),'s--','DisplayName','TOPSIS');
            ylabel('Mean packet loss (%)');
            title('(c) Packet loss');
        case 4
            plot(hystTab.Hysteresis(idxS),hystTab.MeanThroughput_Mbps(idxS),'o-','DisplayName','SAW'); hold on;
            plot(hystTab.Hysteresis(idxT),hystTab.MeanThroughput_Mbps(idxT),'s--','DisplayName','TOPSIS');
            ylabel('Mean throughput (Mbps)');
            title('(d) Throughput');
    end

    % Mark the selected hysteresis independently for each algorithm.
    hS = finalTab.Hysteresis(string(finalTab.Algorithm)=="SAW");
    hT = finalTab.Hysteresis(string(finalTab.Algorithm)=="TOPSIS");
    xline(hS,':','SAW optimum','HandleVisibility','off');
    xline(hT,'--','TOPSIS optimum','HandleVisibility','off');
    xlabel('Hysteresis margin');
    grid on;
    legend('Location','best');
end

sgtitle('Experiment 2: Hysteresis Trade-offs Used to Select the Final Setting');
saveas(f2,fullfile(figDir,'Fig2_Exp2_Hysteresis_Optimization.png'));

% Weight-profile evidence used to choose the final candidate profile.
f2b = figure('Name','Fig 2B: Weight Profile Selection', ...
    'Units','pixels','Position',[100 100 950 450]);
idxS = string(weightTab.Algorithm)=="SAW";
idxT = string(weightTab.Algorithm)=="TOPSIS";
pS = weightTab(idxS,:);
pT = weightTab(idxT,:);
profiles = categorical(string(pS.Profile));
profiles = reordercats(profiles,unique(string(pS.Profile),'stable'));
bar(profiles,[pS.CoreQoSScore,pT.CoreQoSScore],'grouped');
ylabel('Core QoS evaluation score');
xlabel('Candidate weight profile');
title('Experiment 3: Weight-Profile Sensitivity and Final Profile Selection');
legend({'SAW','TOPSIS'},'Location','best');
xtickangle(20); grid on;
saveas(f2b,fullfile(figDir,'Fig2b_Exp3_Weight_Profile_Selection.png'));

% ================================================================
% Figure 3 - Core QoS at final tested configuration
% ================================================================
f3 = figure('Name','Fig 3: Core QoS', ...
    'Units','pixels','Position',[100 100 1000 380]);

names = {'Latency (ms)','Packet loss (%)','Throughput (Mbps)'};
S = [finalTab.MeanLatency_ms,finalTab.MeanPacketLoss_percent,finalTab.MeanThroughput_Mbps];

for m = 1:3
    subplot(1,3,m);
    bar(categorical(string(finalTab.Algorithm),["SAW","TOPSIS"]),S(:,m));
    ylabel(names{m});
    title(names{m});
    grid on;
end
sgtitle('Experiments 7–11: Core End-to-End QoS at Final Tested Configurations');
saveas(f3,fullfile(figDir,'Fig3_Core_QoS_Final_Configuration.png'));

% ================================================================
% Figure 4 - Selected versus score-oracle
% ================================================================
f4 = figure('Name','Fig 4: Oracle Validation', ...
    'Units','pixels','Position',[100 100 900 380]);

subplot(1,2,1);
bar(categorical(string(oracleTab.Algorithm),["SAW","TOPSIS"]), ...
    [oracleTab.SelectedLatency_ms,oracleTab.MetricOracleLatency_ms],'grouped');
ylabel('Mean latency (ms)');
title('Selected vs Per-Metric Oracle Latency');
legend({'Selected','Score-oracle'},'Location','best'); grid on;

subplot(1,2,2);
bar(categorical(string(oracleTab.Algorithm),["SAW","TOPSIS"]), ...
    [oracleTab.SelectedPacketLoss_percent,oracleTab.MetricOraclePacketLoss_percent],'grouped');
ylabel('Mean packet loss (%)');
title('Selected vs Per-Metric Oracle Packet Loss');
legend({'Selected','Score-oracle'},'Location','best'); grid on;

sgtitle('Experiment 12: Comparison with the Per-Metric Oracle');
saveas(f4,fullfile(figDir,'Fig4_Exp12_Oracle_QoS.png'));

% ================================================================
% Figure 5 - Total modelled data cost
% ================================================================
f5 = figure('Name','Fig 5: Total Data Cost', ...
    'Units','pixels','Position',[100 100 750 420]);

bar(categorical(string(finalTab.Algorithm),["SAW","TOPSIS"]),finalTab.TotalDataCost_R);
ylabel('Total modelled data cost (R)');
xlabel('Selection algorithm');
title('Total Modelled Data Cost at Final Configuration');
grid on;

text(1:height(finalTab),finalTab.TotalDataCost_R, ...
    compose('R %.2f',finalTab.TotalDataCost_R), ...
    'HorizontalAlignment','center','VerticalAlignment','bottom');

saveas(f5,fullfile(figDir,'Fig5_Total_Modelled_Data_Cost.png'));

% ================================================================
% Appendix cost sensitivity: total cost only
% ================================================================
f6 = figure('Name','Appendix: Cost Sensitivity', ...
    'Units','pixels','Position',[100 100 800 450]);
for a = ["SAW","TOPSIS"]
    ii = string(costTab.Algorithm)==a;
    plot(costTab.SatelliteCostFactor(ii),costTab.TotalDataCost_R(ii),'-o', ...
        'DisplayName',char(a)); hold on;
end
xlabel('Satellite tariff multiplier');
ylabel('Total modelled data cost (R)');
title('Appendix: Cost Sensitivity');
legend('Location','best'); grid on;
saveas(f6,fullfile(figDir,'Appendix_Cost_Sensitivity.png'));

% ================================================================
% Appendix - Single-criterion comparison
% ================================================================
appendixAlgs = string(algTab.Algorithm);
f7 = figure('Name','Appendix: Single-Criterion Comparison', ...
    'Units','pixels','Position',[100 100 1000 380]);
for m = 1:3
    subplot(1,3,m);
    switch m
        case 1, y = algTab.MeanLatency_ms; label = 'Mean latency (ms)';
        case 2, y = algTab.MeanPacketLoss_percent; label = 'Mean packet loss (%)';
        case 3, y = algTab.MeanThroughput_Mbps; label = 'Mean throughput (Mbps)';
    end
    bar(categorical(appendixAlgs),y);
    ylabel(label); grid on;
end
sgtitle('Appendix: Multi-Criteria and Single-Criterion Selection Comparison');
saveas(f7,fullfile(figDir,'Appendix_Single_Criterion_Comparison.png'));

fprintf('Report figures generated in: %s\n',figDir);
end
