function cfg = simulation_config()
% Central configuration for NetworkSim2 and the automated experiments.
%
% Selection algorithms supported:
%   SAW
%   TOPSIS
%   Throughput
%   Latency
%   PacketLoss
%   SignalStrength
%
% For the single-criterion methods, cfg.threshold is a minimum/maximum
% acceptable criterion value and cfg.hysteresis is the minimum normalized
% improvement required before switching away from the current network.

cfg.xmlFile = 'trace.xml';

%% Selection algorithm
cfg.algorithm = "SAW";

% Criteria order used throughout the simulation:
% [Latency, PacketLoss, Throughput, SignalQuality, CostPerMB]
% The values below are an initial weighting and can be swept
% automatically in run_experiments.m.
cfg.weights = [0.45, 0.18, 0.045, 0.225, 0.10];
cfg.hysteresis = 0.05;

% Single-criterion thresholds. 
cfg.threshold.throughput_Mbps = 5;
cfg.threshold.latency_ms = 100;
cfg.threshold.packetLoss_percent = 20;
cfg.threshold.signalQuality_dB = -90;
cfg.threshold.cost_R_per_MB = 0.50;

% If no network satisfies a single-criterion threshold, select the network
% with the best value of that criterion rather than returning no network.
cfg.threshold.fallbackToBest = true;

%% Reproducibility
cfg.randomSeed = 16;

%% Plot/console behaviour
cfg.plotResults = true;
cfg.verbose = true;

%% SAW/TOPSIS normalisation bounds
% [min max] for each criterion.
% Latency, packet loss and cost are COST criteria.
% Throughput and signal quality are BENEFIT criteria.
cfg.criteriaBounds = [
      0,   500;    % Latency (ms)
      0,   100;    % Packet loss (%)
      0,   400;    % Throughput (Mbps)
   -120,    40;    % Signal quality (dB)
      0,    13   % Cost (R/MB)
];

%% Propagation models
cfg.use3GPP = true;
cfg.cellScenario = "UMa";
cfg.cellEnvironmentHeight = 1;

% "probabilistic" uses the 38.901 UMa LOS probability.
% "alwaysLOS" and "alwaysNLOS" are useful for sensitivity/debugging.
cfg.losMode = "probabilistic";

%% Cellular RF/link parameters
cfg.vodacom.fc = 3.5e9;
cfg.vodacom.txPower_dBm = 43;
cfg.vodacom.txGain_dBi = 15;
cfg.vodacom.rxGain_dBi = 0;
cfg.vodacom.noiseFigure_dB = 7;
cfg.vodacom.bandwidth_Hz = 100e6;
cfg.vodacom.maxThroughput_Mbps = 300;
cfg.vodacom.spectralEfficiencyFactor = 0.65;
cfg.vodacom.baseLatency_ms = 12;
cfg.vodacom.cost_R_per_MB = 0.5;  

cfg.mtn.fc = 2.1e9;
cfg.mtn.txPower_dBm = 43;
cfg.mtn.txGain_dBi = 15;
cfg.mtn.rxGain_dBi = 0;
cfg.mtn.noiseFigure_dB = 7;
cfg.mtn.bandwidth_Hz = 20e6;
cfg.mtn.maxThroughput_Mbps = 150;
cfg.mtn.spectralEfficiencyFactor = 0.65;
cfg.mtn.baseLatency_ms = 16;
cfg.mtn.cost_R_per_MB = 0.5;       

%% Wi-Fi RF/link parameters
cfg.wifi.apPos = [6186, 1325, 5];
cfg.wifi.radius_m = 300;
cfg.wifi.fc = 5.8e9;
cfg.wifi.txPower_dBm = 20;
cfg.wifi.txGain_dBi = 5;
cfg.wifi.rxGain_dBi = 0;
cfg.wifi.noiseFigure_dB = 6;
cfg.wifi.bandwidth_Hz = 80e6;
cfg.wifi.maxThroughput_Mbps = 200;
cfg.wifi.spectralEfficiencyFactor = 0.55;
cfg.wifi.baseLatency_ms = 4;
cfg.wifi.shadowSigma_dB = 2;
cfg.wifi.cost_R_per_MB = 0.001;      

%% Satellite fallback model
cfg.sat.freq = 12e9;
cfg.sat.bandwidth_Hz = 20e6;
cfg.sat.maxThroughput_Mbps = 100;
cfg.sat.linkEfficiency = 0.65;
cfg.sat.txPower_dBW = 40;
cfg.sat.txGain_dBi = 50;
cfg.sat.rxGain_dBi = 40;
cfg.sat.systemLoss_dB = 2;
cfg.sat.noiseFigure_dB = 5;
cfg.sat.altitude_m = 550e3;
cfg.sat.centerX_m = 6000;
cfg.sat.centerY_m = 3000;
cfg.sat.orbitRadiusX_m = 2500e3;
cfg.sat.orbitRadiusY_m = 2500e3;
cfg.sat.angularRate_rad_s = 2*pi/5730;
cfg.sat.phase_rad = 0;
cfg.sat.processingLatency_ms = 20;
cfg.sat.atmosphericLoss_dB = 2;
cfg.sat.shadowMargin_dB = 2;
cfg.sat.cost_R_per_MB = 13;        

end
