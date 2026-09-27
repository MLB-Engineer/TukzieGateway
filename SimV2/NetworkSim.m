clear; clc; close all;

%% === STEP 1: FAST TEXT PARSING OF SUMO TRACE.XML (NO JAVA HEAP ERROR) ===
xmlFile = 'trace.xml';
if ~exist(xmlFile, 'file')
    error('File %s not found. Run SUMO with --fcd-output trace.xml first.', xmlFile);
end

disp('Parsing SUMO trace.xml file via direct stream reader...');

fid = fopen(xmlFile, 'r');
if fid == -1
    error('Could not open file %s', xmlFile);
end

% Allocate temporary storage for trajectory data
maxCapacity = 10000; % Will auto-expand if trace is longer
time = zeros(maxCapacity, 1);
xPos = zeros(maxCapacity, 1);
yPos = zeros(maxCapacity, 1);

stepIdx = 0;
currentTime = 0;
currentX = 0;
currentY = 0;

while ~feof(fid)
    lineStr = strtrim(fgetl(fid));
    if ~ischar(lineStr), break; end
    
    % Match <timestep time="...">
    if startsWith(lineStr, '<timestep')
        tVal = regexp(lineStr, 'time="([^"]+)"', 'tokens');
        if ~isempty(tVal)
            currentTime = str2double(tVal{1}{1});
        end
        
    % Match <vehicle ... x="..." y="..."/> (grabs first vehicle in timestep)
    elseif startsWith(lineStr, '<vehicle')
        xVal = regexp(lineStr, 'x="([^"]+)"', 'tokens');
        yVal = regexp(lineStr, 'y="([^"]+)"', 'tokens');
        
        if ~isempty(xVal) && ~isempty(yVal)
            currentX = str2double(xVal{1}{1});
            currentY = str2double(yVal{1}{1});
        end
        
    % Match </timestep> -> record snapshot
    elseif startsWith(lineStr, '</timestep>')
        stepIdx = stepIdx + 1;
        
        % Dynamic array expansion if file exceeds preallocated length
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
fclose(fid);

% Truncate vectors to actual number of parsed steps
nSteps = 500;%stepIdx;
time = time(1:nSteps);
xPos = xPos(1:nSteps);
yPos = yPos(1:nSteps);

disp(['Successfully parsed ', num2str(nSteps), ' time steps from SUMO trace.']);

%% === STEP 2: SIMULATION & SAW ALGORITHM CONFIGURATION ===
% SAW Weights: [Latency, Packet Loss, Throughput, RSSI/SINR]
weights = [0.35, 0.35, 0.15, 0.15]; 
hysteresis = 0.08; % Handover margin threshold

% Preallocate Data Logging Structures (4 Networks)
selectedLog = zeros(nSteps, 1);
scoresLog   = zeros(nSteps, 4);        % 4 Networks
metricsLog  = zeros(nSteps, 4, 4);     % nSteps x 4 Networks x 4 Criteria

switches    = 0;
currentNet  = 1; % Start on Wi-Fi (Index 1)

%% === STEP 3: MAIN EXECUTION LOOP OVER PARSED TRACE ===
for k = 1:nSteps
    vehPos = [xPos(k), yPos(k), 1.5]; % Vehicle [X, Y, Z] position in meters
    
    % 1. Calculate dynamic network metrics using channel models
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
figure('Name', 'Network Selection Evaluation (UCT to V&A Waterfront)', 'Position', [100, 100, 1000, 750]);

% Subplot 1: Vehicle Trajectory
subplot(3, 1, 1);
plot(xPos, yPos, 'k-', 'LineWidth', 1.5);
xlabel('X Position (m)'); ylabel('Y Position (m)');
title('SUMO Vehicle Trajectory Trace (UCT -> Mowbray -> Gardens -> Waterfront)');
grid on;

% Subplot 2: Network Selection Decisions (4 NETWORKS)
subplot(3, 1, 2);
plot(time, selectedLog, 'LineWidth', 2, 'Color', [0, 0.4470, 0.7410]);
yticks([1 2 3 4]); 
yticklabels({'Wi-Fi', 'Vodacom 5G', 'MTN 5G', 'Satellite'});
ylim([0.5, 4.5]);
xlabel('Time (s)'); ylabel('Selected Network');
title(['Network Selection Decisions over Time (Total Handovers: ', num2str(switches), ')']);
grid on;

% Subplot 3: SAW Utility Scores Across All 4 Networks
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
    
    %% 1. WI-FI MODEL (Local Hotspot / RSU at UCT Upper Campus)
    % Option A: Align AP position with actual start area (6186, 1325)
    % Option B: Increase radius to cover 202m distance (e.g., 250m - 300m for outdoor RSU)

    wifi_ap_pos = [6186, 1325, 5]; % Updated to match car start coordinate
    wifi_radius = 250;            % Expanded for realistic outdoor 5.8 GHz RSU range

    % Calculate 3D Euclidean distance
    d_wifi = norm(vehPos - wifi_ap_pos);

    % Clamp minimum distance to 1m to prevent FSPL log(0) distortion
    d_wifi_eff = max(1.0, d_wifi); 

    fc_wifi = 5.8e9; % 5.8 GHz Wi-Fi 6
    c = 3e8;

    if d_wifi <= wifi_radius
        % Free Space Path Loss (FSPL) with shadow fading
        PL_wifi = fspl(d_wifi_eff, c/fc_wifi) + randn()*2;

        wifi_rssi = 15 - PL_wifi; 
        wifi_tp   = max(0, 200 * (1 - (d_wifi / wifi_radius)^1.5));
        wifi_lat  = 4 + abs(randn()*1.0); % Ensure positive jitter
        wifi_loss = min(100, max(0.05, (d_wifi / wifi_radius)^3 * 100));
    else
        % Out of Range
        wifi_rssi = -115; 
        wifi_tp   = 0; 
        wifi_lat  = 999; 
        wifi_loss = 100;
    end
    
    %% 2. VODACOM 5G/LTE (Single Tower near Mowbray Police Station)
    vodacom_tower = [6344, 3504, 30]; 
    d_vodacom = norm(vehPos - vodacom_tower);
    fc_voda = 3.5e9; % 3.5 GHz Sub-6 5G
    PL_voda = 13.54 + 39.08*log10(max(10, d_vodacom)) + 20*log10(fc_voda/1e9) + randn()*5;
    voda_sinr = 25 - (PL_voda - 95);
    voda_tp   = max(2, 350 * (1 / (1 + 10^(-voda_sinr/10))));
    voda_lat  = 12 + max(0, randn()*2.5);
    voda_loss = max(0.01, min(100, 10^(-voda_sinr/6)));
    
    %% 3. MTN 5G/LTE (Single Tower at Gardens Centre)
    mtn_tower = [3299, 4081, 35]; 
    d_mtn = norm(vehPos - mtn_tower);
    fc_mtn = 2.1e9; % 2.1 GHz spectrum
    PL_mtn = 13.54 + 39.08*log10(max(10, d_mtn)) + 20*log10(fc_mtn/1e9) + randn()*5;
    mtn_sinr = 25 - (PL_mtn - 95);
    mtn_tp   = max(2, 280 * (1 / (1 + 10^(-mtn_sinr/10))));
    mtn_lat  = 16 + max(0, randn()*3.0);
    mtn_loss = max(0.01, min(100, 10^(-mtn_sinr/6)));
    
    %% 4. SATELLITE MODEL (LEO Constellation)
    satAlt = 550e3; % 550 km LEO
    satPos = [vehPos(1)+50e3, vehPos(2)+20e3, satAlt]; 
    d_sat  = norm(vehPos - satPos);
    sat_prop_delay = (d_sat / c) * 1000;
    sat_lat  = (sat_prop_delay * 2) + 20;
    sat_tp   = 120 + randn()*8;
    sat_loss = 0.4 + max(0, randn()*0.15);
    sat_rssi = -82 + randn()*2;
    
    %% METRICS MATRIX COMPILATION
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
    
    %% 1. MIN-MAX NORMALISATION
    for j = 1:2
        minVal = min(metrics(:,j));
        maxVal = max(metrics(:,j));
        if maxVal == minVal
            normMatrix(:,j) = 1.0;
        else
            normMatrix(:,j) = (maxVal - metrics(:,j)) / (maxVal - minVal);
        end
    end
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
        selectedNet = bestNet;
    else
        if (maxScore - scores(currentNet)) > hysteresis
            selectedNet = bestNet;
        else
            selectedNet = currentNet;
        end
    end
end