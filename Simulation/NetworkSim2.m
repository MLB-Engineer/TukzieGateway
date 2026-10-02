function results = NetworkSim2(cfg, traceData)
% NetworkSim2
% SUMO mobility + network models + multiple network-selection algorithms.
%
% Supported algorithms:
%   SAW, TOPSIS, Throughput, Latency, PacketLoss, SignalStrength
%
% Metrics used by SAW/TOPSIS:
%   [Latency, Packet Loss, Throughput, Signal Quality, Cost per MB]
%

%% === CONFIGURATION ===
if nargin == 0 || isempty(cfg)
    cfg = simulation_config();
    singleRun = true;
else
    singleRun = false;
end
if nargin < 2
    traceData = [];
end
if ~isfield(cfg,'randomSeed') || isempty(cfg.randomSeed)
    cfg.randomSeed = 16;
end
rng(cfg.randomSeed);

% Optional network-degradation experiment settings.
% Defaults keep the original simulation unchanged.
if ~isfield(cfg,'degradation') || isempty(cfg.degradation)
    cfg.degradation.enabled = false;
    cfg.degradation.scenario = "normal";
    cfg.degradation.targetNetworks = 1;
    cfg.degradation.startFraction = 0.35;
    cfg.degradation.endFraction = 0.75;
    cfg.degradation.severity = 0.70;
end

%% === STEP 1: TEXT PARSING OF SUMO TRACE.XML ===
if isempty(traceData)
    xmlFile = cfg.xmlFile;
    if ~exist(xmlFile, 'file')
        error('File %s not found. Run SUMO with --fcd-output trace.xml first.', xmlFile);
    end
    disp('Parsing SUMO trace.xml file via direct stream reader...');

    fid = fopen(xmlFile, 'r');
    if fid == -1
        error('Could not open file %s', xmlFile);
    end

    % Preallocate temporary arrays
    maxCapacity = 20000;
    time = zeros(maxCapacity, 1);
    xPos = zeros(maxCapacity, 1);
    yPos = zeros(maxCapacity, 1);

    stepIdx = 0;
    currentTime = NaN;
    currentX = NaN;
    currentY = NaN;
    hasVehicleInStep = false;
    firstVehicleID = '';
    vehicleLocked = false;

    while ~feof(fid)
        lineStr = fgetl(fid);
        if ~ischar(lineStr), break; end

        % 1. Extract timestep time value
        if contains(lineStr, '<timestep')
            tVal = regexp(lineStr, 'time="([^"]+)"', 'tokens');
            if ~isempty(tVal)
                currentTime = str2double(tVal{1}{1});
            end
            hasVehicleInStep = false;

        % 2. Extract vehicle x and y positions
        elseif contains(lineStr, '<vehicle')
            xVal = regexp(lineStr, 'x="([^"]+)"', 'tokens');
            yVal = regexp(lineStr, 'y="([^"]+)"', 'tokens');
            idVal = regexp(lineStr, 'id="([^"]+)"', 'tokens');

            % Lock onto the first vehicle encountered in the trace file and
            % ignore all other vehicles. This makes the mobility trajectory
            % deterministic when the SUMO trace contains multiple vehicles.
            if ~vehicleLocked && ~isempty(idVal)
                firstVehicleID = idVal{1}{1};
                vehicleLocked = true;
            end

            thisIsTrackedVehicle = false;
            if vehicleLocked
                thisIsTrackedVehicle = ~isempty(idVal) && strcmp(idVal{1}{1},firstVehicleID);
            elseif ~hasVehicleInStep
                % Fallback for a trace without vehicle IDs: first vehicle
                % encountered in each timestep is used.
                thisIsTrackedVehicle = true;
            end

            if thisIsTrackedVehicle && ~isempty(xVal) && ~isempty(yVal)
                currentX = str2double(xVal{1}{1});
                currentY = str2double(yVal{1}{1});
                hasVehicleInStep = true;
            end

        % 3. End of timestep marker -> record snapshot
        elseif contains(lineStr, '</timestep>')
            if ~isnan(currentTime) && hasVehicleInStep
                stepIdx = stepIdx + 1;

                % Expand arrays dynamically if capacity is reached
                if stepIdx > maxCapacity
                    maxCapacity = maxCapacity * 2;
                    time(maxCapacity) = 0;
                    xPos(maxCapacity) = 0;
                    yPos(maxCapacity) = 0;
                end

                time(stepIdx) = currentTime;
                xPos(stepIdx) = currentX;
                yPos(stepIdx) = currentY;
            end
        end
    end
    fclose(fid);

    % Truncate vectors dynamically to actual parsed steps
    nSteps = stepIdx;

    if nSteps == 0
        error('Parsing failed: 0 timesteps found. Check if trace.xml contains valid <timestep> and <vehicle> nodes.');
    end

    time = time(1:nSteps);
    xPos = xPos(1:nSteps);
    yPos = yPos(1:nSteps);

    disp(['Successfully parsed ', num2str(nSteps), ' time steps from SUMO trace.']);
else
    time = traceData.time;
    xPos = traceData.xPos;
    yPos = traceData.yPos;
    nSteps = numel(time);
    if cfg.verbose
        disp(['Using pre-parsed SUMO trace: ', num2str(nSteps), ' time steps.']);
    end
end

%% === STEP 2: MODEL CONFIGURATION ===
weights = cfg.weights;
hysteresis = cfg.hysteresis;
if abs(sum(weights) - 1) > 1e-12
    error('Weights must sum to 1. Current sum = %.12f', sum(weights));
end

selectedLog = zeros(nSteps,1);
scoresLog = zeros(nSteps,4);
metricsLog = zeros(nSteps,4,5);
distanceLog = zeros(nSteps,3);
signalLog = zeros(nSteps,4);
losLog = false(nSteps,2);
thresholdLog = true(nSteps,4);

oracleLog = zeros(nSteps,1);
oracleScoreLog = zeros(nSteps,1);
oracleMetricsLog = zeros(nSteps,5);
metricOracleLog = zeros(nSteps,3);

selectedScoreLog = zeros(nSteps,1);
selectedMetricsLog = zeros(nSteps,5);
degradationLog = ones(nSteps,4);

switches = 0;
% Start with no forced network so the first decision is made by the
% selection algorithm rather than inheriting Wi-Fi by assumption.
currentNet = 0;

%% === STEP 3: MAIN EXECUTION LOOP ===
for k = 1:nSteps
    vehPos = [xPos(k), yPos(k), 1.5];

    netMetrics = get_network_metrics(vehPos, time(k), cfg);

    % Apply controlled degradation AFTER the common network models and
    % BEFORE network selection. This keeps the mobility/channel model
    % identical across algorithms while allowing controlled stress tests.
    [netMetrics, degradationFactors] = apply_network_degradation( ...
        netMetrics, k, nSteps, cfg);

    available = true(4,1);
    if isfield(cfg.wifi,'enforceCoverage') && cfg.wifi.enforceCoverage
        available(1) = norm(vehPos-cfg.wifi.apPos) <= cfg.wifi.radius_m;
    end

    metricsLog(k,:,:) = netMetrics.metrics;
    degradationLog(k,:) = degradationFactors;
    distanceLog(k,:) = netMetrics.distances;
    signalLog(k,:) = netMetrics.signalQuality;
    losLog(k,:) = netMetrics.los;

    [nextNet, scores, diagnostics] = selection_algorithms( ...
        netMetrics.metrics, currentNet, cfg, available);

    [oracleScore, oracleNet] = max(scores);

    if nextNet ~= currentNet && k > 1
        switches = switches + 1;
    end

    currentNet = nextNet;
    selectedLog(k) = currentNet;
    scoresLog(k,:) = scores';
    oracleLog(k) = oracleNet;
    oracleScoreLog(k) = oracleScore;
    oracleMetricsLog(k,:) = netMetrics.metrics(oracleNet,:);
    availableIdx = find(available);
    [~,iiLat] = min(netMetrics.metrics(availableIdx,1));
    [~,iiLoss] = min(netMetrics.metrics(availableIdx,2));
    [~,iiThr] = max(netMetrics.metrics(availableIdx,3));
    metricOracleLog(k,:) = [netMetrics.metrics(availableIdx(iiLat),1), ...
        netMetrics.metrics(availableIdx(iiLoss),2), ...
        netMetrics.metrics(availableIdx(iiThr),3)];
    selectedScoreLog(k) = scores(currentNet);
    selectedMetricsLog(k,:) = netMetrics.metrics(currentNet,:);
    thresholdLog(k,:) = diagnostics.thresholdPassed';
end

%% === STEP 4: METRIC EVALUATION ===
duration = max(time(end)-time(1),eps);
handoverRate = switches/duration;
networkNames = ["Wi-Fi","Vodacom 5G","MTN 5G","Satellite"];
timeOnNetwork = zeros(1,4);
for n = 1:4
    timeOnNetwork(n) = 100*mean(selectedLog == n);
end

results = struct();
results.time = time;
results.xPos = xPos;
results.yPos = yPos;
results.selectedLog = selectedLog;
results.scoresLog = scoresLog;
results.metricsLog = metricsLog;
results.degradationLog = degradationLog;
results.degradationScenario = string(cfg.degradation.scenario);
results.distanceLog = distanceLog;
results.signalLog = signalLog;
results.losLog = losLog;
results.thresholdLog = thresholdLog;
results.oracleLog = oracleLog;
results.oracleScoreLog = oracleScoreLog;
results.oracleMetricsLog = oracleMetricsLog;
results.metricOracleLog = metricOracleLog;
results.selectedScoreLog = selectedScoreLog;
results.selectedMetricsLog = selectedMetricsLog;
results.meanSelectedMetrics = mean(selectedMetricsLog,1);
results.meanMetrics = squeeze(mean(metricsLog,1));
results.meanScores = mean(scoresLog,1);
results.meanSelectedScore = mean(selectedScoreLog);
results.meanOracleScore = mean(oracleScoreLog);
results.oracleMatchRate = 100*mean(selectedLog == oracleLog);
results.switches = switches;
results.handoverRate = handoverRate;
results.timeOnNetwork = timeOnNetwork;
% Modelled data cost assumes the selected throughput is fully utilised.
% Mbps*s is converted to MB using 1 Mbps = 0.125 MB/s.
results.modelledDataCost_R = 0.125*trapz(time, ...
    selectedMetricsLog(:,3).*selectedMetricsLog(:,5));
results.weights = weights;
results.hysteresis = hysteresis;
results.algorithm = string(cfg.algorithm);
results.randomSeed = cfg.randomSeed;
results.networkNames = networkNames;
results.traceData = struct('time',time,'xPos',xPos,'yPos',yPos);

%% === STEP 5: VISUALISATION ===
if cfg.plotResults || singleRun
    plot_results(results, cfg);
end

if cfg.verbose
    disp('--- SIMULATION COMPLETE ---');
    disp(['Algorithm: ', char(cfg.algorithm)]);
    disp(['Total Time Steps Analyzed: ', num2str(nSteps)]);
    disp(['Total Handover Count: ', num2str(switches)]);
    disp(['Handover Rate: ', num2str(handoverRate,'%.4f'), ' handovers/s']);
    disp(['Oracle agreement: ', num2str(results.oracleMatchRate,'%.2f'), '%']);
    disp('Time on each network (%):');
    disp(array2table(timeOnNetwork,'VariableNames', ...
        {'WiFi','Vodacom5G','MTN5G','Satellite'}));
end
end

%% ========================================================================
function out = get_network_metrics(vehPos,t,cfg)

%% 1. WI-FI MODEL
wifi_ap_pos = cfg.wifi.apPos;
wifi_radius = cfg.wifi.radius_m;
d_wifi = norm(vehPos-wifi_ap_pos);
d_wifi_eff = max(1.0,d_wifi);

c = physconst('LightSpeed');
lambda_wifi = c/cfg.wifi.fc;
PL_wifi = fspl(d_wifi_eff,lambda_wifi) + randn()*cfg.wifi.shadowSigma_dB;

rxPower_wifi = cfg.wifi.txPower_dBm + cfg.wifi.txGain_dBi + ...
    cfg.wifi.rxGain_dBi - PL_wifi;
wifi_rssi = rxPower_wifi;

noiseWifi = -174 + 10*log10(cfg.wifi.bandwidth_Hz) + cfg.wifi.noiseFigure_dB;
wifi_snr = wifi_rssi-noiseWifi;
wifi_tp = cfg.wifi.spectralEfficiencyFactor*cfg.wifi.bandwidth_Hz* ...
    log2(1+10^(wifi_snr/10));
wifi_tp = min(cfg.wifi.maxThroughput_Mbps*1e6,max(0,wifi_tp));

wifi_lat = cfg.wifi.baseLatency_ms + 2*abs(randn());
wifi_loss = min(100,max(0.01,(d_wifi/wifi_radius)^3*100));

if isfield(cfg.wifi,'enforceCoverage') && cfg.wifi.enforceCoverage && d_wifi > wifi_radius
    % Outside the configured AP coverage radius, Wi-Fi is unavailable to
    % the selector. The selector also receives an explicit availability mask.
    wifi_tp = 0;
    wifi_loss = 100;
    wifi_lat = 500;
    wifi_rssi = -120;
end

%% 2. VODACOM 5G/LTE
vodacom_tower = [6344,3504,30];
d_vodacom = norm(vehPos-vodacom_tower);
[vodaPathLoss,vodaLOS] = cellular_pathloss(d_vodacom,cfg.vodacom.fc, ...
    vodacom_tower,vehPos,cfg);
voda_shadow = randn()*5;
PL_voda = vodaPathLoss+voda_shadow;
rxPower_voda = cfg.vodacom.txPower_dBm+cfg.vodacom.txGain_dBi+ ...
    cfg.vodacom.rxGain_dBi-PL_voda;
noiseVoda = -174+10*log10(cfg.vodacom.bandwidth_Hz)+cfg.vodacom.noiseFigure_dB;
voda_sinr = rxPower_voda-noiseVoda;
voda_tp = cfg.vodacom.spectralEfficiencyFactor*cfg.vodacom.bandwidth_Hz* ...
    log2(1+10^(voda_sinr/10));
voda_tp = min(cfg.vodacom.maxThroughput_Mbps*1e6,max(0,voda_tp));
voda_lat = cfg.vodacom.baseLatency_ms+max(0,randn()*2.5);
voda_loss = max(0.01,min(100,100/(1+exp(0.65*(voda_sinr-3)))));

%% 3. MTN 5G/LTE
mtn_tower = [3299,4081,35];
d_mtn = norm(vehPos-mtn_tower);
[mtnPathLoss,mtnLOS] = cellular_pathloss(d_mtn,cfg.mtn.fc, ...
    mtn_tower,vehPos,cfg);
mtn_shadow = randn()*5;
PL_mtn = mtnPathLoss+mtn_shadow;
rxPower_mtn = cfg.mtn.txPower_dBm+cfg.mtn.txGain_dBi+ ...
    cfg.mtn.rxGain_dBi-PL_mtn;
noiseMtn = -174+10*log10(cfg.mtn.bandwidth_Hz)+cfg.mtn.noiseFigure_dB;
mtn_sinr = rxPower_mtn-noiseMtn;
mtn_tp = cfg.mtn.spectralEfficiencyFactor*cfg.mtn.bandwidth_Hz* ...
    log2(1+10^(mtn_sinr/10));
mtn_tp = min(cfg.mtn.maxThroughput_Mbps*1e6,max(0,mtn_tp));
mtn_lat = cfg.mtn.baseLatency_ms+max(0,randn()*3.0);
mtn_loss = max(0.01,min(100,100/(1+exp(0.65*(mtn_sinr-3)))));

%% 4. SATELLITE MODEL
c = physconst('LightSpeed');
freq = cfg.sat.freq;
bw = cfg.sat.bandwidth_Hz;
omega = cfg.sat.angularRate_rad_s;
satPos = [ ...
    cfg.sat.centerX_m+cfg.sat.orbitRadiusX_m*cos(omega*t+cfg.sat.phase_rad), ...
    cfg.sat.centerY_m+cfg.sat.orbitRadiusY_m*sin(omega*t+cfg.sat.phase_rad), ...
    cfg.sat.altitude_m];

d_sat = norm(vehPos-satPos);
sat_prop_delay = (d_sat/c)*1000;
sat_lat = sat_prop_delay+cfg.sat.processingLatency_ms;
lambda = c/freq;
fspl_dB = fspl(d_sat,lambda);
rxPower_dBW = cfg.sat.txPower_dBW+cfg.sat.txGain_dBi+cfg.sat.rxGain_dBi- ...
    fspl_dB-cfg.sat.systemLoss_dB-cfg.sat.atmosphericLoss_dB- ...
    cfg.sat.shadowMargin_dB;
sat_rssi = rxPower_dBW+30;
noisePower_dBm = -174+10*log10(bw)+cfg.sat.noiseFigure_dB;
snr = sat_rssi-noisePower_dBm;
sat_tp = cfg.sat.linkEfficiency*bw*log2(1+10^(snr/10));
sat_tp = min(cfg.sat.maxThroughput_Mbps*1e6,max(0,sat_tp));
sat_loss = max(0,min(100,0.5*exp(-0.1*snr)));

%% Return metrics
out.metrics = [ ...
    wifi_lat, wifi_loss, wifi_tp/1e6, wifi_rssi, cfg.wifi.cost_R_per_MB; ...
    voda_lat, voda_loss, voda_tp/1e6, voda_sinr, cfg.vodacom.cost_R_per_MB; ...
    mtn_lat, mtn_loss, mtn_tp/1e6, mtn_sinr, cfg.mtn.cost_R_per_MB; ...
    sat_lat, sat_loss, sat_tp/1e6, sat_rssi, cfg.sat.cost_R_per_MB];
out.distances = [d_wifi,d_vodacom,d_mtn];
out.signalQuality = [wifi_rssi,voda_sinr,mtn_sinr,sat_rssi];
out.los = [vodaLOS,mtnLOS];
end

%% ========================================================================
function [out,factors] = apply_network_degradation(in,k,nSteps,cfg)
% APPLY_NETWORK_DEGRADATION
% Controlled stress model used only for degradation experiments.
%
% Scenario definitions:
%   normal      - no degradation
%   gradual     - linear degradation between startFraction/endFraction
%   abrupt      - full degradation from startFraction onward
%   combined    - gradual degradation applied to Wi-Fi + terrestrial 5G
%
% The degradation magnitudes are simulation assumptions, not measured
% network-failure statistics.

out = in;
factors = ones(1,4);

if ~isfield(cfg,'degradation') || ~cfg.degradation.enabled
    return;
end

scenario = lower(string(cfg.degradation.scenario));
severity = max(0,min(1,cfg.degradation.severity));

if ~isfield(cfg.degradation,'startFraction')
    cfg.degradation.startFraction = 0.35;
end
if ~isfield(cfg.degradation,'endFraction')
    cfg.degradation.endFraction = 0.75;
end
if ~isfield(cfg.degradation,'targetNetworks')
    cfg.degradation.targetNetworks = 1;
end

startFrac = cfg.degradation.startFraction;
endFrac = max(startFrac, cfg.degradation.endFraction);

switch scenario
    case "normal"
        s = 0;

    case "gradual"
        progress = (k-1)/max(nSteps-1,1);
        s = min(max((progress-startFrac)/(endFrac-startFrac),0),1);

    case "abrupt"
        progress = (k-1)/max(nSteps-1,1);
        s = double(progress >= startFrac);

    case "combined"
        progress = (k-1)/max(nSteps-1,1);
        s = min(max((progress-startFrac)/(endFrac-startFrac),0),1);

    otherwise
        error('Unknown degradation scenario: %s',cfg.degradation.scenario);
end

if scenario == "combined"
    targets = [1 2 3];
else
    targets = cfg.degradation.targetNetworks;
end

targets = unique(targets(:).');
targets = targets(targets >= 1 & targets <= size(out.metrics,1));

if isempty(targets) || s <= 0 || severity <= 0
    return;
end

d = severity*s;

for n = targets
    oldLoss = out.metrics(n,2);
    out.metrics(n,1) = out.metrics(n,1) * (1 + 2*d);
    out.metrics(n,2) = min(100, oldLoss + (50-oldLoss)*d);
    out.metrics(n,3) = out.metrics(n,3) * max(0.05,1-d);
    out.metrics(n,4) = out.metrics(n,4) - 20*d;
    factors(n) = 1-d;
end

out.signalQuality = out.metrics(:,4).';

end

%% ========================================================================
function [pathLoss,isLOS] = cellular_pathloss(d,fc,bs,ue,cfg)
if cfg.use3GPP && exist('nrPathLoss','file') == 2 && exist('nrPathLossConfig','file') == 2
    pathlossconf = nrPathLossConfig;
    pathlossconf.Scenario = cfg.cellScenario;
    pathlossconf.EnvironmentHeight = cfg.cellEnvironmentHeight;

    switch lower(string(cfg.losMode))
        case "alwayslos"
            isLOS = true;
        case "alwaysnlos"
            isLOS = false;
        case "probabilistic"
            d2d = max(d,10);
            pLOS = min(18/d2d,1)*(1-exp(-d2d/63))+exp(-d2d/63);
            isLOS = rand()<pLOS;
        otherwise
            error('Unknown cfg.losMode: %s',cfg.losMode);
    end

    [pathLoss,~] = nrPathLoss(pathlossconf,fc,isLOS,bs(:),ue(:));
else
    % Fallback for debugging only if 5G Toolbox is unavailable.
    c = physconst('LightSpeed');
    pathLoss = fspl(max(10,d),c/fc);
    isLOS = true;
end
end

%% ========================================================================
function plot_results(results,cfg)
time = results.time;

figure('Name','Network Selection Evaluation', ...
    'Position',[100,100,1100,950]);

subplot(5,1,1);
plot(results.xPos,results.yPos,'k-','LineWidth',1.5);
xlabel('X Position (m)'); ylabel('Y Position (m)');
title('SUMO Vehicle Trajectory Trace'); grid on;

subplot(5,1,2);
plot(time,results.selectedLog,'LineWidth',2);
yticks([1 2 3 4]);
yticklabels({'Wi-Fi','Vodacom 5G','MTN 5G','Satellite'});
ylim([0.5 4.5]); xlabel('Time (s)'); ylabel('Network');
title(sprintf('%s Selection (Handovers: %d)',char(results.algorithm),results.switches));
grid on;

subplot(5,1,3);
plot(time,results.scoresLog,'LineWidth',1.2);
xlabel('Time (s)'); ylabel('Score');
legend('Wi-Fi','Vodacom 5G','MTN 5G','Satellite','Location','best');
title([char(results.algorithm),' Scores']); grid on;

subplot(5,1,4);
plot(time,results.signalLog,'LineWidth',1.2);
xlabel('Time (s)'); ylabel('Signal Quality (dB)');
legend('Wi-Fi RSSI','Vodacom SINR','MTN SINR','Satellite RSSI', ...
    'Location','best');
title('Time-Varying Signal Quality'); grid on;

subplot(5,1,5);
plot(time,results.selectedMetricsLog(:,5),'LineWidth',1.2);
xlabel('Time (s)'); ylabel('Cost (R/MB)');
title('Cost of Selected Network'); grid on;

if cfg.verbose
    figure('Name','Network Distances');
    plot(time,results.distanceLog,'LineWidth',1.4);
    xlabel('Time (s)'); ylabel('Distance (m)');
    legend('Wi-Fi AP','Vodacom tower','MTN tower','Location','best');
    title('Vehicle Distance from Network Infrastructure'); grid on;
end
end
