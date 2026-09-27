function [selectedNet, scores, diagnostics] = selection_algorithms(metrics, currentNet, cfg)
% Implements the network-selection methods used by NetworkSim2.
%
% Metrics columns:
%   1 Latency          COST
%   2 Packet loss      COST
%   3 Throughput       BENEFIT
%   4 Signal quality   BENEFIT
%   5 Cost per MB      COST
%
% Methods
%   SAW:            Simple Additive Weighting
%   TOPSIS:         Technique for Order Preference by Similarity to Ideal Solution
%   Throughput:     Single criterion + threshold + hysteresis
%   Latency:        Single criterion + threshold + hysteresis
%   PacketLoss:     Single criterion + threshold + hysteresis
%   SignalStrength: Single criterion + threshold + hysteresis

method = lower(string(cfg.algorithm));
weights = cfg.weights(:);

if numel(weights) ~= 5 || abs(sum(weights)-1) > 1e-10
    error('cfg.weights must contain 5 values summing to 1.');
end

% Cost = true; Benefit = false
isCost = [true; true; false; false; true];

switch method
    case "saw"
        normMatrix = minmax_normalize(metrics, cfg.criteriaBounds, isCost);
        scores = normMatrix * weights;
        [bestScore,bestNet] = max(scores);
        selectedNet = apply_score_hysteresis(bestNet, bestScore, scores, currentNet, cfg.hysteresis);
        if selectedNet < 1 || selectedNet > numel(scores)
            error('apply_score_hysteresis returned invalid network index: %d', selectedNet);
        end
        diagnostics.methodScore = scores;
        diagnostics.normalizedMatrix = normMatrix;
        diagnostics.thresholdPassed = true(size(scores));

    case "topsis"
        [scores, normMatrix] = topsis_scores(metrics, weights, isCost);
        [bestScore, bestNet] = max(scores);
        selectedNet = apply_score_hysteresis(bestNet, bestScore, scores, currentNet, cfg.hysteresis);
        if selectedNet < 1 || selectedNet > numel(scores)
            error('apply_score_hysteresis returned invalid network index: %d', selectedNet);
        end
        diagnostics.methodScore = scores;
        diagnostics.normalizedMatrix = normMatrix;
        diagnostics.thresholdPassed = true(size(scores));

    case {"throughput", "latency", "packetloss", "signalstrength"}
        [criterionIndex, thresholdValue] = single_criterion_config(method, cfg);
        raw = metrics(:,criterionIndex);

        if criterionIndex == 3 || criterionIndex == 4
            passed = raw >= thresholdValue;
            normScores = normalize_single(raw, criterionIndex, cfg.criteriaBounds, false);
        else
            passed = raw <= thresholdValue;
            normScores = normalize_single(raw, criterionIndex, cfg.criteriaBounds, true);
        end

        eligible = find(passed);
        if isempty(eligible)
            if cfg.threshold.fallbackToBest
                [bestScore, bestNet] = max(normScores);
            else
                bestScore = -Inf;
                bestNet = currentNet;
            end
        else
            [bestScoreLocal, idx] = max(normScores(eligible));
            bestNet = eligible(idx);
            bestScore = bestScoreLocal;
        end

        % A network that fails the threshold is not retained merely because
        % of hysteresis. Thresholds therefore act as minimum QoS constraints;
        % hysteresis is applied only when the current network is acceptable.
        if currentNet ~= 0 && ~passed(currentNet) && any(passed)
            selectedNet = bestNet;
        else
            selectedNet = apply_score_hysteresis(bestNet, bestScore, normScores, currentNet, cfg.hysteresis);
        end
        scores = normScores;
        diagnostics.methodScore = scores;
        diagnostics.normalizedMatrix = normScores;
        diagnostics.thresholdPassed = passed;

    otherwise
        error('Unknown selection algorithm: %s', cfg.algorithm);
end

end

function normMatrix = minmax_normalize(metrics, bounds, isCost)
[numNets, numCriteria] = size(metrics);
normMatrix = zeros(numNets,numCriteria);
for j = 1:numCriteria
    lo = bounds(j,1);
    hi = bounds(j,2);
    if hi <= lo
        error('Invalid criterion bounds for column %d.',j);
    end
    x = min(hi,max(lo,metrics(:,j)));
    if isCost(j)
        normMatrix(:,j) = (hi-x)/(hi-lo);
    else
        normMatrix(:,j) = (x-lo)/(hi-lo);
    end
end
end

function normMatrix = vector_normalize(metrics, isCost)
[numNets,numCriteria] = size(metrics);
normMatrix = zeros(numNets,numCriteria);
for j = 1:numCriteria
    x = metrics(:,j);
    denom = sqrt(sum(x.^2));
    if denom < eps
        r = zeros(numNets,1);
    else
        r = x/denom;
    end
    if isCost(j)
        maxR = max(r);
        if maxR > 0
            r = maxR-r;
        end
    end
    normMatrix(:,j) = r;
end
end

% Shift each criterion to a non-negative benefit scale. This keeps the WSM
% weighted sum interpretable while retaining vector normalisation.
%for j = 1:numCriteria
    %col = normMatrix(:,j);
    %cmin = min(col);
    %cmax = max(col);
    %if cmax-cmin < eps
        %normMatrix(:,j) = ones(numNets,1);
    %else
        %normMatrix(:,j) = (col-cmin)/(cmax-cmin);
    %end
%end
%end

function [scores, normMatrix] = topsis_scores(metrics, weights, isCost)
% Standard TOPSIS using vector-normalised decision matrix.
[numNets,numCriteria] = size(metrics);
R = zeros(numNets,numCriteria);
for j = 1:numCriteria
    denom = sqrt(sum(metrics(:,j).^2));
    if denom < eps
        R(:,j) = 0;
    else
        R(:,j) = metrics(:,j)/denom;
    end
end

V = R .* weights';
idealBest = zeros(1,numCriteria);
idealWorst = zeros(1,numCriteria);
for j = 1:numCriteria
    if isCost(j)
        idealBest(j) = min(V(:,j));
        idealWorst(j) = max(V(:,j));
    else
        idealBest(j) = max(V(:,j));
        idealWorst(j) = min(V(:,j));
    end
end

dPlus = sqrt(sum((V-idealBest).^2,2));
dMinus = sqrt(sum((V-idealWorst).^2,2));
scores = dMinus ./ max(dPlus+dMinus,eps);
normMatrix = V;
end

function scores = normalize_single(raw, index, bounds, isCost)
lo = bounds(index,1);
hi = bounds(index,2);
x = min(hi,max(lo,raw));
if isCost
    scores = (hi-x)/(hi-lo);
else
    scores = (x-lo)/(hi-lo);
end
end

function selectedNet = apply_score_hysteresis(bestNet, bestScore, scores, currentNet, hysteresis)
if currentNet == 0
    selectedNet = bestNet;
    return;
end

currentScore = scores(currentNet);
if bestNet ~= currentNet && (bestScore-currentScore) > hysteresis
    selectedNet = bestNet;
else
    selectedNet = currentNet;
end
end

function [criterionIndex, thresholdValue] = single_criterion_config(method,cfg)
switch method
    case "throughput"
        criterionIndex = 3;
        thresholdValue = cfg.threshold.throughput_Mbps;
    case "latency"
        criterionIndex = 1;
        thresholdValue = cfg.threshold.latency_ms;
    case "packetloss"
        criterionIndex = 2;
        thresholdValue = cfg.threshold.packetLoss_percent;
    case "signalstrength"
        criterionIndex = 4;
        thresholdValue = cfg.threshold.signalQuality_dB;
    otherwise
        error('Unsupported single criterion method: %s',method);
end
end
