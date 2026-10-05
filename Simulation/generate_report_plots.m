function generate_report_plots(resDir)
%GENERATE_REPORT_PLOTS Figures for the investigator-selected configuration.
% Run after run_experiments. All final figures use w=[.3 .3 .2 .1 .1], M=.08.
% Baseline and sensitivity figures explicitly identify their exceptions.
% Joint-search winners are not inputs to this plotting function.
if nargin < 1 || isempty(resDir)
    resDir = fullfile(pwd,'experiment_results');
end
resDir = char(resDir);
required = {'experiment_metadata.csv','algorithm_comparison.csv', ...
    'final_configuration.csv','final_policy_comparison.csv', ...
    'baseline_vs_final.csv','fixed_weight_hysteresis_sensitivity.csv', ...
    'fixed_weight_selected_hysteresis.csv','final_oracle_comparison.csv', ...
    'degradation_scenarios_summary.csv','random_seed_summary.csv', ...
    'random_weight_sensitivity.csv','single_criterion_threshold_sensitivity.csv'};
for i=1:numel(required)
    assert(isfile(fullfile(resDir,required{i})), ...
        'Missing %s. Run the updated run_experiments first.',required{i});
end
meta = readtable(fullfile(resDir,'experiment_metadata.csv'));
finalTab = ordered(readtable(fullfile(resDir,'final_configuration.csv')), ["SAW","TOPSIS"]);
weightCols = {'WeightLatency','WeightPacketLoss','WeightThroughput','WeightSignal','WeightCost'};
expectedWeights = [.30 .30 .20 .10 .10];
assert(height(meta)==1 && string(meta.ConfigurationFamily)=="chosen_fixed_weights_v1", ...
    'These outputs are not from the updated chosen-configuration experiments.');
assert(all(abs(finalTab{:,weightCols}-expectedWeights)<1e-10,'all') && ...
    all(abs(finalTab.Hysteresis-.08)<1e-10) && ...
    abs(meta.Hysteresis-.08)<1e-10 && ...
    all(abs(meta{1,weightCols}-expectedWeights)<1e-10), ...
    'Final CSV settings do not match the chosen weights and M=0.08. Rerun experiments.');
base = ordered(readtable(fullfile(resDir,'algorithm_comparison.csv')), ["SAW","TOPSIS"]);
fixed = readtable(fullfile(resDir,'fixed_weight_hysteresis_sensitivity.csv'));
selected = ordered(readtable(fullfile(resDir,'fixed_weight_selected_hysteresis.csv')), ["SAW","TOPSIS"]);
oracle = ordered(readtable(fullfile(resDir,'final_oracle_comparison.csv')), ["SAW","TOPSIS"]);
seed = ordered(readtable(fullfile(resDir,'random_seed_summary.csv')), ["SAW","TOPSIS"]);
policy = ordered(readtable(fullfile(resDir,'final_policy_comparison.csv')), ...
    ["SAW","TOPSIS","Throughput","Latency","PacketLoss","SignalStrength"]);
scenarios = readtable(fullfile(resDir,'degradation_scenarios_summary.csv'));
randomWeights = readtable(fullfile(resDir,'random_weight_sensitivity.csv'));
threshold = readtable(fullfile(resDir,'single_criterion_threshold_sensitivity.csv'));
assert(all(abs(oracle.SelectedLatency_ms-finalTab.MeanLatency_ms)<1e-9) && ...
    all(abs(oracle.SelectedPacketLoss_percent-finalTab.MeanPacketLoss_percent)<1e-9), ...
    'Oracle and final-performance CSVs are inconsistent. Rerun experiments.');
for t = {oracle,seed,scenarios,randomWeights,threshold,policy}
    assert(all(abs(t{1}.Hysteresis-.08)<1e-10), ...
        'A downstream experiment does not use the chosen margin.');
end
assert(all(abs(selected.Hysteresis-.08)<1e-10), ...
    'Experiment 7 selected points must have M=0.08.');
figDir = fullfile(resDir,'report_figures','chosen_M008');
appDir = fullfile(figDir,'appendix');
if ~exist(figDir,'dir'), mkdir(figDir); end
if ~exist(appDir,'dir'), mkdir(appDir); end
methods = {'SAW','TOPSIS'};
colors = [0.10 0.35 0.72; 0.87 0.40 0.12];
configTitle = 'Chosen weights [0.30 0.30 0.20 0.10 0.10], M = 0.08';

%% Main Figure 1: untuned baseline
f = report_figure('Baseline',850,420);
bar([base.Handovers base.PingPongHandovers],'grouped');
set(gca,'XTick',1:2,'XTickLabel',methods); ylabel('Count'); grid on;
legend({'Handovers','Ping-pong returns'},'Location','best');
title('Baseline: equal weights, M = 0');
save_figure(f,figDir,'Fig1_Baseline_Handovers');

%% Main Figure 2 / Experiment 7: investigator-selected margin, NOT optimum
f = report_figure('Fixed-weight hysteresis sensitivity',1050,720);
fields = {'Handovers','PingPongHandovers','MeanLatency_ms','MeanPacketLoss_percent'};
labels = {'Total handovers','Ping-pong returns','Mean latency (ms)','Mean modelled loss (%)'};
for m=1:4
    subplot(2,2,m); hold on;
    for a=1:2
        t = sortrows(fixed(string(fixed.Algorithm)==string(methods{a}),:),'Hysteresis');
        idx = abs(t.Hysteresis-meta.Hysteresis)<1e-10;
        assert(nnz(idx)==1,'One chosen margin is required per algorithm.');
        styles = {'o-','s--'};
        plot(t.Hysteresis,t.(fields{m}),styles{a},'Color',colors(a,:), ...
            'LineWidth',1.3,'DisplayName',methods{a});
        plot(t.Hysteresis(idx),t.(fields{m})(idx),'p','MarkerSize',12, ...
            'MarkerFaceColor',colors(a,:),'MarkerEdgeColor','k','HandleVisibility','off');
    end
    xline(meta.Hysteresis,':k','Chosen M = 0.08','HandleVisibility','off');
    xlabel('Hysteresis margin M'); ylabel(labels{m}); grid on;
    legend('Location','best');
end
sgtitle({'Experiment 7: fixed-weight hysteresis sensitivity', ...
    'Weights [0.30 0.30 0.20 0.10 0.10]; stars mark investigator-selected M = 0.08'});
save_figure(f,figDir,'Exp7_Fixed_Weight_Hysteresis_Sensitivity');
% Capacity sweep is supporting evidence, with the same chosen marker.
f = report_figure('Experiment 7 capacity',800,410); hold on;
for a=1:2
    t = sortrows(fixed(string(fixed.Algorithm)==string(methods{a}),:),'Hysteresis');
    plot(t.Hysteresis,t.MeanThroughput_Mbps,'o-','Color',colors(a,:), ...
        'LineWidth',1.3,'DisplayName',methods{a});
end
xline(.08,':k','Chosen M = 0.08','HandleVisibility','off');
xlabel('Hysteresis margin M'); ylabel('Mean estimated capacity (Mb/s)');
legend('Location','best'); grid on; title('Experiment 7: capacity sensitivity at fixed weights');
save_figure(f,appDir,'Appendix_Exp7_Capacity_Sensitivity');

%% Main Figure 3: final QoS under the CHOSEN configuration
f = report_figure('Final core QoS',1100,390);
fields = {'MeanLatency_ms','MeanPacketLoss_percent','MeanThroughput_Mbps'};
metricLabels = {'Mean latency (ms)','Mean modelled loss (%)','Mean estimated capacity (Mb/s)'};
for m=1:3
    subplot(1,3,m); method_bars(finalTab.(fields{m}),methods,colors);
    ylabel(metricLabels{m}); grid on;
end
sgtitle({'Final SAW versus TOPSIS',configTitle});
save_figure(f,figDir,'Fig4_Final_Core_QoS');

%% Main Figure 4: chosen settings versus independent latency/loss references
f = report_figure('Final metric references',1000,400);
subplot(1,2,1); bar([oracle.SelectedLatency_ms oracle.MetricOracleLatency_ms],'grouped');
set(gca,'XTick',1:2,'XTickLabel',methods); ylabel('Mean latency (ms)'); grid on;
legend({'Selected','Independent metric reference'},'Location','best');
subplot(1,2,2); bar([oracle.SelectedPacketLoss_percent oracle.MetricOraclePacketLoss_percent],'grouped');
set(gca,'XTick',1:2,'XTickLabel',methods); ylabel('Mean modelled loss (%)'); grid on;
legend({'Selected','Independent metric reference'},'Location','best');
sgtitle({'Final configurations versus independent metric bounds',configTitle});
save_figure(f,figDir,'Fig5_Final_Oracle_Comparison');

%% Supporting comparison: baseline to CHOSEN final switching
f = report_figure('Baseline to chosen final',950,410);
subplot(1,2,1); bar([base.Handovers finalTab.Handovers],'grouped'); ylabel('Handovers');
set(gca,'XTick',1:2,'XTickLabel',methods); grid on;
legend({'Equal weights, M=0','Chosen weights, M=0.08'},'Location','best');
subplot(1,2,2); bar([base.PingPongHandovers finalTab.PingPongHandovers],'grouped');
ylabel('Ping-pong returns'); set(gca,'XTick',1:2,'XTickLabel',methods); grid on;
legend({'Equal weights, M=0','Chosen weights, M=0.08'},'Location','best');
sgtitle('Baseline versus investigator-selected configuration');
save_figure(f,figDir,'Supporting_Baseline_vs_Final_Switching');

%% Normal and degradation traces: chosen settings throughout
for scenario = ["normal","gradual","abrupt","combined"]
    file = fullfile(resDir,sprintf('SAW_vs_TOPSIS_timeseries_%s.csv',char(scenario)));
    assert(isfile(file),'Missing trace: %s',file);
    t = readtable(file);
    f = report_figure(['Time series: ' char(scenario)],1050,900);
    suffixes = {'Latency_ms','PacketLoss_percent','Throughput_Mbps','Network'};
    traceLabels = {'Latency (ms)','Modelled loss (%)','Estimated capacity (Mb/s)','Selected interface'};
    for m=1:4
        subplot(4,1,m); hold on;
        for a=1:2
            field = [methods{a} '_' suffixes{m}];
            if m==4
                stairs(t.Time_s,t.(field),'Color',colors(a,:),'LineWidth',1.2, ...
                    'DisplayName',methods{a});
            else
                plot(t.Time_s,t.(field),'Color',colors(a,:),'LineWidth',1.2, ...
                    'DisplayName',methods{a});
            end
        end
        if scenario~="normal"
            progress = (0:height(t)-1)'/max(height(t)-1,1);
            if scenario=="abrupt"
                first = find(progress>=meta.DegradationStartFraction,1);
            else
                first = find(progress>meta.DegradationStartFraction,1);
            end
            if ~isempty(first)
                xline(t.Time_s(first),':k','Stress onset','HandleVisibility','off');
            end
            if scenario~="abrupt"
                full = find(progress>=meta.DegradationEndFraction,1);
                if ~isempty(full)
                    xline(t.Time_s(full),'--k','Ramp end','HandleVisibility','off');
                end
            end
        end
        if m==4
            yticks(1:4); yticklabels({'Wi-Fi','Cellular 1','Cellular 2','Satellite'});
            ylim([.8 4.2]);
        end
        ylabel(traceLabels{m}); grid on; legend('Location','best');
        if m==4, xlabel('Time (s)'); end
    end
    sgtitle({['Selected-link response: ' char(scenario)],configTitle});
    if scenario=="combined"
        save_figure(f,figDir,'Degradation_combined');
    else
        save_figure(f,appDir,['Degradation_' char(scenario)]);
    end
end

%% Seed robustness: ten run means, mean +/- SAMPLE SD
f = report_figure('Seed robustness',1050,700);
means = {'Handovers_Mean','PingPong_Mean','Latency_Mean_ms', ...
    'PacketLoss_Mean_percent','Throughput_Mean_Mbps'};
sds = {'Handovers_SD','PingPong_SD','Latency_SD_ms', ...
    'PacketLoss_SD_percent','Throughput_SD_Mbps'};
labels = {'Handovers','Ping-pong returns','Latency (ms)','Modelled loss (%)','Capacity (Mb/s)'};
for m=1:5
    subplot(2,3,m); method_bars(seed.(means{m}),methods,colors); hold on;
    errorbar(1:2,seed.(means{m}),seed.(sds{m}),'k.','LineWidth',1.2);
    ylabel(labels{m}); grid on;
end
subplot(2,3,6); axis off;
text(0,.9,{'Seeds 1--10; normal scenario','Bars: means of ten run means', ...
    'Error bars: sample SD across runs','Not packet-level variation or a confidence interval'}, ...
    'Units','normalized','VerticalAlignment','top','FontSize',10);
sgtitle({'Random-seed robustness of chosen settings',configTitle});
save_figure(f,figDir,'Random_Seed_Robustness');

%% Single-criterion references at the SAME M=0.08, thresholds unchanged
f = report_figure('Single-criterion comparison',1200,470);
referenceLabels = {'SAW','TOPSIS','Max capacity','Min latency','Min loss','Max signal'};
for m=1:3
    subplot(1,3,m); bar(policy.(fields{m}));
    set(gca,'XTick',1:6,'XTickLabel',referenceLabels); xtickangle(35);
    ylabel(metricLabels{m});
    grid on;
end
sgtitle({'Multi-criteria versus single-criterion references; common margin M = 0.08', ...
    'Weights apply to SAW/TOPSIS; references rank only their designated criterion'});
save_figure(f,appDir,'Appendix_Single_Criterion_Comparison');

%% Cost and mixed signal criterion: supporting outputs only
f = report_figure('Supporting metrics',1100,390);
subplot(1,3,1); method_bars(finalTab.MeanCost_R_per_MB,methods,colors); ylabel('Mean tariff (R/MB)'); grid on;
subplot(1,3,2); method_bars(finalTab.TotalDataCost_R,methods,colors); ylabel('Modelled total cost (R)'); grid on;
subplot(1,3,3); method_bars(finalTab.MeanSignalQuality_dB,methods,colors); ylabel('Mixed signal criterion (dBm/dB)'); grid on;
sgtitle({'Supporting model outputs at chosen settings', ...
    'Total cost assumes capacity-based traffic; cross-technology signal units differ'});
save_figure(f,appDir,'Appendix_Cost_and_Signal');

%% Occupancy across scenarios
f = report_figure('Scenario occupancy',1100,650);
scenarioOrder = ["normal","gradual","abrupt","combined"];
occupancyFields = {'TimeWiFi_percent','TimeVodacom_percent','TimeMTN_percent','TimeSatellite_percent'};
for a=1:2
    subplot(2,1,a);
    t = scenarios(string(scenarios.Algorithm)==string(methods{a}),:);
    [found,idx] = ismember(scenarioOrder,string(t.Scenario));
    assert(all(found),'Missing scenario occupancy rows.');
    bar(t{idx,occupancyFields},'stacked');
    set(gca,'XTick',1:4,'XTickLabel',cellstr(scenarioOrder));
    ylabel('Samples on interface (%)'); title(methods{a}); ylim([0 100]); grid on;
    legend({'Wi-Fi','Cellular 1','Cellular 2','Satellite'},'Location','eastoutside');
end
sgtitle({'Selected-interface occupancy',configTitle});
save_figure(f,appDir,'Appendix_Degradation_Occupancy');

%% Random weights: exception varies weights, retains CHOSEN margin .08
f = report_figure('Priority sensitivity',1100,400);
for m=1:3
    subplot(1,3,m);
    boxchart(categorical(string(randomWeights.Algorithm)),randomWeights.(fields{m}));
    ylabel(metricLabels{m}); grid on;
end
sgtitle('Priority sensitivity: 100 shared random weight vectors, M = 0.08');
save_figure(f,appDir,'Appendix_Random_Weight_Sensitivity');

%% Thresholds: separate units/axes for each criterion
f = report_figure('Threshold sensitivity',1050,700);
criteria = ["Throughput","Latency","PacketLoss","SignalStrength"];
xlabels = {'Minimum capacity (Mb/s)','Maximum latency (ms)','Maximum modelled loss (%)','Minimum mixed signal criterion'};
for a=1:4
    subplot(2,2,a); t = sortrows(threshold(string(threshold.Criterion)==criteria(a),:),'Threshold');
    yyaxis left; plot(t.Threshold,t.Handovers,'o-','LineWidth',1.2); ylabel('Handovers');
    yyaxis right; plot(t.Threshold,t.MeanPacketLoss_percent,'s--','LineWidth',1.2); ylabel('Mean modelled loss (%)');
    xlabel(xlabels{a}); title(char(criteria(a))); grid on;
end
sgtitle('Single-criterion threshold sensitivity; fixed M = 0.08');
save_figure(f,appDir,'Appendix_Threshold_Sensitivity');

%% Full five-criterion references and own score-oracle agreement
f = report_figure('Full metric references',1100,720);
selectedFields = {'SelectedLatency_ms','SelectedPacketLoss_percent', ...
    'SelectedThroughput_Mbps','SelectedSignalQuality_dB','SelectedCost_R_per_MB'};
referenceFields = {'MetricOracleLatency_ms','MetricOraclePacketLoss_percent', ...
    'MetricOracleThroughput_Mbps','MetricOracleSignalQuality_dB','MetricOracleCost_R_per_MB'};
referenceLabels = {'Latency (ms)','Modelled loss (%)','Capacity (Mb/s)', ...
    'Mixed signal criterion (dBm/dB)','Tariff (R/MB)'};
for m=1:5
    subplot(2,3,m);
    bar([oracle.(selectedFields{m}) oracle.(referenceFields{m})],'grouped');
    set(gca,'XTick',1:2,'XTickLabel',methods); ylabel(referenceLabels{m}); grid on;
    legend({'Selected','Per-metric reference'},'Location','best');
end
subplot(2,3,6); method_bars(oracle.ScoreOracleAgreement_percent,methods,colors);
ylabel('Agreement with own score oracle (%)'); ylim([0 100]); grid on;
sgtitle({'Supporting oracle evidence at chosen settings', ...
    'References are independent; signal units differ; own-score agreement does not rank QoS'});
save_figure(f,appDir,'Appendix_Full_Oracle_Comparison');
fprintf('Report figures (PNG + vector PDF) saved in:\n%s\n',figDir);
end

function t = ordered(t,names)
[found,idx] = ismember(names,string(t.Algorithm));
assert(all(found),'Missing one or more required policies in a results table.');
t = t(idx,:);
end

function f = report_figure(name,w,h)
f = figure('Name',name,'Color','w','Visible','off','Position',[80 80 w h]);
end

function method_bars(y,names,colors)
b = bar(y); b.FaceColor = 'flat'; b.CData = colors;
set(gca,'XTick',1:numel(names),'XTickLabel',names);
end

function save_figure(f,folder,name)
% Export off-screen figures through print, avoiding exportgraphics' figure
% handling. Size the PDF page to the figure, including all subplots/titles.
assert(isgraphics(f,'figure'),'Cannot save %s: figure is no longer valid.',name);
if ~exist(folder,'dir'), mkdir(folder); end
% Force readable text regardless of MATLAB's light/dark theme defaults.
set(f,'Color','w','InvertHardcopy','off');
textObjects = findall(f,'Type','text');
set(textObjects,'Color','k');
axesObjects = findall(f,'Type','axes');
for i = 1:numel(axesObjects)
    ax = axesObjects(i);
    set(ax,'Color','w','XColor','k','YColor','k','ZColor','k');
    % yyaxis has two independent rulers; make both sets of ticks black.
    for j = 1:numel(ax.YAxis)
        ax.YAxis(j).Color = 'k';
    end
end
legendObjects = findall(f,'Type','legend');
set(legendObjects,'TextColor','k','Color','w','EdgeColor','k');
originalUnits = get(f,'Units');
set(f,'Units','inches');
position = get(f,'Position');
set(f,'Units',originalUnits);
set(f,'PaperUnits','inches','PaperSize',position(3:4), ...
    'PaperPosition',[0 0 position(3:4)],'PaperPositionMode','manual');
drawnow;
print(f,fullfile(folder,[name '.png']),'-dpng','-r300');
print(f,fullfile(folder,[name '.pdf']),'-dpdf','-vector');
close(f);
end
