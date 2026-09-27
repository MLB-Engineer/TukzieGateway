clear; clc; close all;
%% === STEP 1: PARSE SUMO TRACE.XML ===
xmlFile = 'trace.xml';
if ~exist(xmlFile, 'file')
    error('File %s not found. Run SUMO with --fcd-output trace.xml first.', xmlFile);
end
disp('Parsing SUMO trace.xml file...');
docNode = xmlread(xmlFile);
% Get all timestep nodes
timesteps = docNode.getElementsByTagName('timestep');
nSteps = timesteps.getLength;
% Preallocate arrays
time = zeros(nSteps, 1);
xPos = zeros(nSteps, 1);
yPos = zeros(nSteps, 1);
for k = 0:nSteps-1
    tsNode = timesteps.item(k);
    time(k+1) = str2double(char(tsNode.getAttribute('time')));
    
    vehNodes = tsNode.getElementsByTagName('vehicle');
    if vehNodes.getLength > 0
        vehNode = vehNodes.item(0); % Parse primary target vehicle
        xPos(k+1) = str2double(char(vehNode.getAttribute('x')));
        yPos(k+1) = str2double(char(vehNode.getAttribute('y')));
    else
        % Retain last known position if vehicle temporarily leaves domain
        if k > 0
            xPos(k+1) = xPos(k);
            yPos(k+1) = yPos(k);
        end
    end
end
disp(['Successfully parsed ', num2str(nSteps), ' time steps from SUMO trace.']);
%% === STEP 2: SIMULATION & SAW ALGORITHM CONFIGURATION ===
% SAW Weights: [Latency, Packet Loss, Throughput, RSSI]
weights = [0.35, 0.35, 0.15, 0.15]; 
hysteresis = 0.08; % Handover margin threshold
% Preallocate Data Logging Structures
selectedLog = zeros(nSteps, 1);
scoresLog  = zeros(nSteps, 4);        % 4 Networks
metricsLog = zeros(nSteps, 4, 4);     % nSteps x 4 Networks x 4 Criteria
% SAW Weights: [Latency, Packet Loss, Throughput, RSSI]
weights = [0.35, 0.35, 0.15, 0.15]; 
hysteresis = 0.08;
% Plot labels update
subplot(3, 1, 2);
plot(time, selectedLog, 'LineWidth', 2);
yticks([1 2 3 4]); 
yticklabels({'Wi-Fi', 'Vodacom 5G', 'MTN 5G', 'Satellite'});
switches    = 0;
currentNet  = 1; % Start on Wi-Fi (Index 1)
%% === STEP 3: MAIN EXECUTION LOOP OVER PARSED TRACE ===
for k = 1:nSteps
    vehPos = [xPos(k), yPos(k), 1.5]; % Vehicle [X, Y, Z] position in meters
    
    % 1. Calculate dynamic network metrics using MATLAB toolbox channel models
    netMetrics = get_network_metrics(vehPos, time(k));
    metricsLog(k, :, :) = netMetrics;
    % 2. Run SAW Multi-Criteria Decision Engine with Hysteresis
    [nextNet, scores] = run_saw_selection(netMetrics, currentNet, weights, hysteresis);
    
    % 3. Track network switches
    if nextNet ~= currentNet && k > 1
        switches = switches + 1;
    end
    currentNet = nextNet;
    
    % Log decisions and utility scores
    selectedLog(k)  = currentNet;
    scoresLog(k, :) = scores';
end
%% === STEP 4: VISUALISATION & METRIC EVALUATION ===
figure('Name', 'Network Selection Evaluation', 'Position', [100, 100, 1000, 700]);
% Subplot 1: Vehicle Trajectory
subplot(3, 1, 1);
plot(xPos, yPos, 'k-', 'LineWidth', 1.5);
xlabel('X Position (m)'); ylabel('Y Position (m)');
title('SUMO Vehicle Trajectory Trace');
grid on;
% Subplot 2: Network Selection Decisions
subplot(3, 1, 2);
plot(time, selectedLog, 'LineWidth', 2, 'Color', [0, 0.4470, 0.7410]);
yticks([1 2 3]); yticklabels({'Wi-Fi', '5G/LTE', 'Satellite'});
xlabel('Time (s)'); ylabel('Selected Network');
title(['Network Selection Decisions over Time (Total Switches: ', num2str(switches), ')']);
grid on;
% Subplot 3: Utility Scores
subplot(3, 1, 3);
plot(time, scoresLog(:,1), 'r--', 'LineWidth', 1.2); hold on;
plot(time, scoresLog(:,2), 'g-.', 'LineWidth', 1.2);
plot(time, scoresLog(:,3), 'b:',  'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('SAW Score');
legend('Wi-Fi Score', '5G/LTE Score', 'Satellite Score', 'Location', 'best');
title('SAW Utility Scores Across Candidate Networks');
grid on;
disp('--- SIMULATION COMPLETE ---');
disp(['Total Time Steps Analyzed: ', num2str(nSteps)]);
disp(['Total Handover Count: ', num2str(switches)]);
function metrics = get_network_metrics(vehPos, t)
% vehPos: [x, y, z] in meters (relative coordinates along UCT -> V&A route)
% t: current simulation time step in seconds
c = physconst('LightSpeed');
%% 1. WI-FI MODEL (Local Hotspot / RSU at UCT Upper Campus [x=100, y=100])
wifi_ap_pos = [100, 100, 5];
d_wifi = norm(vehPos - wifi_ap_pos);
fc_wifi = 5.8e9; % 5.8 GHz Wi-Fi 6
if d_wifi < 150
    PL_wifi = fspl(d_wifi, c/fc_wifi) + randn()*2;
    wifi_rssi = 15 - PL_wifi; 
    wifi_tp   = max(0, 200 * (1 - (d_wifi/150)^1.5)); % Mbps
    wifi_lat  = 4 + randn()*1.0; % ms
    wifi_loss = min(100, max(0.05, (d_wifi/150)^3 * 100)); % %
else
    wifi_rssi = -115; wifi_tp = 0; wifi_lat = 999; wifi_loss = 100;
end
%% 2. VODACOM 5G/LTE (Single Tower near Mowbray Police Station)
vodacom_tower = [1200, 800, 30]; % Tower position [X, Y, Z]
d_vodacom = norm(vehPos - vodacom_tower);
fc_voda = 3.5e9; % 3.5 GHz Sub-6 5G
% 3GPP TR 38.901 Urban Macro NLOS Pathloss
PL_voda = 13.54 + 39.08*log10(max(10, d_vodacom)) + 20*log10(fc_voda/1e9) + randn()*5;
voda_sinr = 25 - (PL_voda - 95);
voda_tp   = max(2, 350 * (1 / (1 + 10^(-voda_sinr/10)))); % Mbps
voda_lat  = 12 + max(0, randn()*2.5); % ms
voda_loss = max(0.01, min(100, 10^(-voda_sinr/6)));
%% 3. MTN 5G/LTE (Single Tower at Gardens Centre)
mtn_tower = [4500, 3200, 35]; % Tower position [X, Y, Z]
d_mtn = norm(vehPos - mtn_tower);
fc_mtn = 2.1e9; % 2.1 GHz LTE-A / 5G spectrum
% 3GPP TR 38.901 Urban Macro NLOS Pathloss
PL_mtn = 13.54 + 39.08*log10(max(10, d_mtn)) + 20*log10(fc_mtn/1e9) + randn()*5;
mtn_sinr = 25 - (PL_mtn - 95);
mtn_tp   = max(2, 280 * (1 / (1 + 10^(-mtn_sinr/10)))); % Mbps
mtn_lat  = 16 + max(0, randn()*3.0); % ms
mtn_loss = max(0.01, min(100, 10^(-mtn_sinr/6)));
%% 4. SATELLITE MODEL (LEO Constellation)
satAlt = 550e3; % 550 km Starlink-like LEO orbit
satPos = [vehPos(1)+50e3, vehPos(2)+20e3, satAlt]; 
d_sat  = norm(vehPos - satPos);
sat_prop_delay = (d_sat / c) * 1000; % ms (slant-range delay)
sat_lat  = (sat_prop_delay * 2) + 20; % RTT + Ground Gateway delay (~35-45ms)
sat_tp   = 120 + randn()*8; % Mbps
sat_loss = 0.4 + max(0, randn()*0.15); % Clear sky loss
sat_rssi = -82 + randn()*2;
%% METRICS MATRIX COMPILATION
% Rows: 1=Wi-Fi, 2=Vodacom 5G, 3=MTN 5G, 4=Satellite
% Cols: [Latency(ms), PacketLoss(%), Throughput(Mbps), RSSI/SINR(dB)]
metrics = [
    wifi_lat,  wifi_loss,  wifi_tp,  wifi_rssi;
    voda_lat,  voda_loss,  voda_tp,  voda_sinr;
    mtn_lat,   mtn_loss,   mtn_tp,   mtn_sinr;
    sat_lat,   sat_loss,   sat_tp,   sat_rssi
    ];
end
function [selectedNet, scores] = run_saw_selection(metrics, currentNet, weights, hysteresis)
% metrics: [3x4] matrix [Latency, Loss, Throughput, RSSI]
% weights: [1x4] vector summing to 1.0 (e.g., [0.3, 0.3, 0.2, 0.2])
% hysteresis: Threshold score advantage required to trigger a handover (e.g., 0.08)
[numNets, numCriteria] = size(metrics);
normMatrix = zeros(numNets, numCriteria);
%% 1. MIN-MAX NORMALISATION
% Criteria 1 & 2: Cost (Lower is better: Latency, Loss)
for j = 1:2
    minVal = min(metrics(:,j));
    maxVal = max(metrics(:,j));
    if maxVal == minVal
        normMatrix(:,j) = 1.0;
    else
        normMatrix(:,j) = (maxVal - metrics(:,j)) / (maxVal - minVal);
    end
end
% Criteria 3 & 4: Benefit (Higher is better: Throughput, Signal Quality)
for j = 3:4
    minVal = min(metrics(:,j));
    maxVal = max(metrics(:,j));
    if maxVal == minVal
        normMatrix(:,j) = 1.0;
    else
        normMatrix(:,j) = (metrics(:,j) - minVal) / (maxVal - minVal);
    end
end
%% 2. SAW SCORE CALCULATION
scores = normMatrix * weights';
%% 3. HYSTERESIS SWITCHING LOGIC
[maxScore, bestNet] = max(scores);
if currentNet == 0
    selectedNet = bestNet; % Initial state initialization
else
    % Switch only if candidate score exceeds current score + hysteresis
    if (maxScore - scores(currentNet)) > hysteresis
        selectedNet = bestNet;
    else
        selectedNet = currentNet; % Retain current network
    end
end
end