clear; clc; close all;
addpath('C:\Program Files\MATLAB\R2026a\toolbox\shared\channel');

%% === STEP 1: ROBUST TEXT PARSING OF SUMO TRACE.XML ===
xmlFile = 'trace.xml';
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
        
        if ~isempty(xVal) && ~isempty(yVal)
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
nSteps = 500; %stepIdx;

if nSteps == 0
    error('Parsing failed: 0 timesteps found. Check if trace.xml contains valid <timestep> and <vehicle> nodes.');
end

time = time(1:nSteps);
xPos = xPos(1:nSteps);
yPos = yPos(1:nSteps);

disp(['Successfully parsed ', num2str(nSteps), ' time steps from SUMO trace.']);

%% === STEP 2: SIMULATION & SAW ALGORITHM CONFIGURATION ===
weights = [0.5, 0.20, 0.05, 0.20]; % [Latency, Packet Loss, Throughput, RSSI/SINR]
hysteresis = 0.08; 

selectedLog = zeros(nSteps, 1);
scoresLog   = zeros(nSteps, 4);        
metricsLog  = zeros(nSteps, 4, 4);     

switches    = 0;
currentNet  = 1; 

%% === STEP 3: MAIN EXECUTION LOOP ===
for k = 1:nSteps
    vehPos = [xPos(k), yPos(k), 1.5];
    
    netMetrics = get_network_metrics(vehPos, time(k));
    metricsLog(k, :, :) = netMetrics;
    
    [nextNet, scores] = run_saw_selection(netMetrics, currentNet, weights, hysteresis);
    
    if nextNet ~= currentNet && k > 1
        switches = switches + 1;
    end
    currentNet = nextNet;
    
    selectedLog(k)  = currentNet;
    scoresLog(k, :) = scores';
end

%% === STEP 4: VISUALISATION & METRIC EVALUATION ===
figure('Name', 'Network Selection Evaluation (UCT to V&A Waterfront)', 'Position', [100, 100, 1000, 750]);

subplot(3, 1, 1);
plot(xPos, yPos, 'k-', 'LineWidth', 1.5);
xlabel('X Position (m)'); ylabel('Y Position (m)');
title('SUMO Vehicle Trajectory Trace (UCT -> Mowbray -> Gardens -> Waterfront)');
grid on;

subplot(3, 1, 2);
plot(time, selectedLog, 'LineWidth', 2, 'Color', [0, 0.4470, 0.7410]);
yticks([1 2 3 4]); 
yticklabels({'Wi-Fi', 'Vodacom 5G', 'MTN 5G', 'Satellite'});
ylim([0.5, 4.5]);
xlabel('Time (s)'); ylabel('Selected Network');
title(['Network Selection Decisions over Time (Total Handovers: ', num2str(switches), ')']);
grid on;

subplot(3, 1, 3);
plot(time, scoresLog(:,1), 'r--', 'LineWidth', 1.2); hold on;
plot(time, scoresLog(:,2), 'g-.', 'LineWidth', 1.2);
plot(time, scoresLog(:,3), 'm-',  'LineWidth', 1.2);
plot(time, scoresLog(:,4), 'b:',  'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('SAW Score');
legend('Wi-Fi', 'Vodacom 5G (Mowbray)', 'MTN 5G (Gardens)', 'Satellite (LEO)', 'Location', 'best');
title('SAW Utility Scores Across Candidate Networks');
grid on;

disp('--- SIMULATION COMPLETE ---');
disp(['Total Time Steps Analyzed: ', num2str(nSteps)]);
disp(['Total Handover Count: ', num2str(switches)]);

%% === LOCAL HELPER FUNCTIONS ===

function metrics = get_network_metrics(vehPos, t)
    c = physconst('LightSpeed');
    
    %% 1. WI-FI MODEL
    wifi_ap_pos = [6186, 1325, 5]; 
    wifi_radius = 300;            
    d_wifi = norm(vehPos - wifi_ap_pos);
    d_wifi_eff = max(1.0, d_wifi); 
    fc_wifi = 5.8e9; 
    
    if d_wifi <= wifi_radius
        PL_wifi = fspl(d_wifi_eff, c/fc_wifi) + randn()*2;
        wifi_rssi = 15 - PL_wifi; 
        wifi_tp   = max(0, 200 * (1 - (d_wifi / wifi_radius)^1.5));
        wifi_lat  = 4 + abs(randn()*1.0); 
        wifi_loss = min(100, max(0.05, (d_wifi / wifi_radius)^3 * 100));
    else
        wifi_rssi = -115; 
        wifi_tp   = 0; 
        wifi_lat  = 999; 
        wifi_loss = 100;
    end
    
    %% 2. VODACOM 5G/LTE
    vodacom_tower = [6344, 3504, 30]; 
    d_vodacom = norm(vehPos - vodacom_tower);
    fc_voda = 3.5e9; 
    PL_voda = 13.54 + 39.08*log10(max(10, d_vodacom)) + 20*log10(fc_voda/1e9) + randn()*5;
    voda_sinr = 25 - (PL_voda - 95);
    voda_tp   = max(2, 350 * (1 / (1 + 10^(-voda_sinr/10))));
    voda_lat  = 12 + max(0, randn()*2.5);
    voda_loss = max(0.01, min(100, 10^(-voda_sinr/6)));
    
    %% 3. MTN 5G/LTE
    mtn_tower = [3299, 4081, 35]; 
    d_mtn = norm(vehPos - mtn_tower);
    fc_mtn = 2.1e9; 
    PL_mtn = 13.54 + 39.08*log10(max(10, d_mtn)) + 20*log10(fc_mtn/1e9) + randn()*5;
    mtn_sinr = 25 - (PL_mtn - 95);
    mtn_tp   = max(2, 280 * (1 / (1 + 10^(-mtn_sinr/10))));
    mtn_lat  = 16 + max(0, randn()*3.0);
    mtn_loss = max(0.01, min(100, 10^(-mtn_sinr/6)));
    
    %% 4. SATELLITE MODEL
    %% 4. SATELLITE MODEL (Improved with Toolbox-based link budget)

    % Constants
    c       = physconst('LightSpeed');   % Speed of light
    freq    = 12e9;                      % Ku-band frequency (Hz)
    bw      = 20e6;                      % Channel bandwidth (Hz)
    txPower = 40;                        % Transmit power (dBW)
    txGain  = 50;                        % Tx antenna gain (dBi)
    rxGain  = 40;                        % Rx antenna gain (dBi)
    sysLoss = 2;                         % System losses (dB)
    noiseFig= 5;                         % Receiver noise figure (dB)

    % Satellite position
    satAlt  = 550e3; 
    satPos  = [vehPos(1)+50e3, vehPos(2)+20e3, satAlt]; 
    d_sat   = norm(vehPos - satPos);

    % Propagation delay
    sat_prop_delay = (d_sat / c) * 1000; % ms
    sat_lat        = sat_prop_delay + 20; % add coding/queuing delay

    % Free-space path loss
    fspl = fspl(d_sat, freq); % dB

    % Link budget: received power
    rxPower = txPower + txGain + rxGain - fspl - sysLoss; % dBW

    % Convert to RSSI (dBm)
    sat_rssi = rxPower + 30; % dBm

    % Noise power (dBm)
    noisePower = -174 + 10*log10(bw) + noiseFig; % dBm

    % SNR (dB)
    snr = sat_rssi - noisePower;

    % Throughput using Shannon capacity approximation
    sat_tp = bw * log2(1 + 10^(snr/10)); % bits/s

    % Packet loss modeled as function of SNR (optional)
    sat_loss = max(0, 0.5*exp(-0.1*snr)); % simple exponential model

    
    metrics = [
        wifi_lat,  wifi_loss,  wifi_tp,  wifi_rssi;
        voda_lat,  voda_loss,  voda_tp,  voda_sinr;
        mtn_lat,   mtn_loss,   mtn_tp,   mtn_sinr;
        sat_lat,   sat_loss,   sat_tp,   sat_rssi
    ];
end

function [selectedNet, scores] = run_saw_selection(metrics, currentNet, weights, hysteresis)
    [numNets, numCriteria] = size(metrics);
    normMatrix = zeros(numNets, numCriteria);
    
    bounds = [
        0,   500;   % Latency Cost
        0,   100;   % Packet Loss Cost
        0,   400;   % Throughput Benefit
       -120,  40;   % Signal Quality Benefit
    ];
    
    for j = 1:2
        minVal = bounds(j, 1);
        maxVal = bounds(j, 2);
        clampedVal = min(maxVal, max(minVal, metrics(:,j)));
        normMatrix(:,j) = (maxVal - clampedVal) / (maxVal - minVal);
    end
    
    for j = 3:4
        minVal = bounds(j, 1);
        maxVal = bounds(j, 2);
        clampedVal = min(maxVal, max(minVal, metrics(:,j)));
        normMatrix(:,j) = (clampedVal - minVal) / (maxVal - minVal);
    end
    
    scores = normMatrix * weights';
    
    [maxScore, bestNet] = max(scores);
    if currentNet == 0
        selectedNet = bestNet;
    else
        if (maxScore - scores(currentNet)) > hysteresis
            selectedNet = bestNet;
        else
            selectedNet = currentNet;
        end
    end
end