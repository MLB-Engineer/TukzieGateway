function animate_simulation_map(speedFactor, netFile)
% ANIMATE_SIMULATION_MAP
% Visualise the FIRST SUMO vehicle on the original full SUMO map.
%
% Both SAW and TOPSIS are ALWAYS simulated and displayed together.
%
% Usage:
%   animate_simulation_map
%   animate_simulation_map(0.03)
%   animate_simulation_map(0.03,"uct_cbd.net.xml")
%
% speedFactor: pause between frames in seconds.

if nargin < 1 || isempty(speedFactor), speedFactor = 0.1; end
if nargin < 2 || isempty(netFile), netFile = 'uct_cbd.net.xml'; end

if ~isfile(netFile)
    error('SUMO network file not found: %s',netFile);
end

%% Configuration
cfg = simulation_config();
cfg.plotResults = false;
cfg.verbose = false;
cfg.randomSeed = 16;

wifiPos = [cfg.wifi.apPos(1), cfg.wifi.apPos(2)];
wifiRadius = cfg.wifi.radius_m;
vodaPos = [6344,3504];
mtnPos = [3299,4081];

networkNames = {'Wi-Fi','Vodacom 5G','MTN 5G','Satellite'};
networkColors = lines(4);

%% Read FIRST vehicle only
xmlFile = cfg.xmlFile;
if ~isfile(xmlFile)
    error('Trace file not found: %s',xmlFile);
end

fprintf('Reading FIRST vehicle from %s...\n',xmlFile);
traceData = read_first_vehicle_trace(xmlFile);
fprintf('Animating first vehicle: %s (%d timesteps)\n', ...
    traceData.vehicleID,numel(traceData.time));

%% Run BOTH algorithms on exactly the same trajectory
cfgSAW = cfg;
cfgSAW.algorithm = "SAW";
rSAW = NetworkSim2(cfgSAW,traceData);

cfgTOPSIS = cfg;
cfgTOPSIS.algorithm = "TOPSIS";
rTOPSIS = NetworkSim2(cfgTOPSIS,traceData);

%% Read the FULL SUMO road map
fprintf('Reading SUMO road network...\n');
roadMap = read_sumo_road_map(netFile);
fprintf('Road network loaded.\n');

%% Figure
fig = figure('Name','Smart Tuk-Tuk - SUMO Map Animation', ...
    'Color','w','Position',[40 40 1500 850]);

% Dark green map background.
mapBG = [0.035 0.14 0.075];
roadColour = [0.72 0.78 0.74];

%% MAP
axMap = axes('Parent',fig,'Position',[0.045 0.15 0.62 0.80], ...
    'Color',mapBG,'XColor','w','YColor','w');
hold(axMap,'on'); box(axMap,'on');

plot(axMap,roadMap.x,roadMap.y,'-','Color',roadColour, ...
    'LineWidth',0.45,'HandleVisibility','off');

% Full path of the ONE selected vehicle.
plot(axMap,rSAW.xPos,rSAW.yPos,'k-','LineWidth',1.8, ...
    'DisplayName','Vehicle path');
plot(axMap,rSAW.xPos(1),rSAW.yPos(1),'go','MarkerFaceColor','g', ...
    'MarkerSize',8,'DisplayName','Start');
plot(axMap,rSAW.xPos(end),rSAW.yPos(end),'mo','MarkerFaceColor','m', ...
    'MarkerSize',8,'DisplayName','End');

% Wi-Fi coverage.
th = linspace(0,2*pi,250);
plot(axMap,wifiPos(1)+wifiRadius*cos(th), ...
    wifiPos(2)+wifiRadius*sin(th),'b--','LineWidth',1.2, ...
    'DisplayName','Wi-Fi coverage');

% Network infrastructure.
plot(axMap,wifiPos(1),wifiPos(2),'bs','MarkerFaceColor','b', ...
    'MarkerSize',12,'DisplayName','Wi-Fi AP');
plot(axMap,vodaPos(1),vodaPos(2),'r^','MarkerFaceColor','r', ...
    'MarkerSize',15,'DisplayName','Vodacom tower');
plot(axMap,mtnPos(1),mtnPos(2),'ms','MarkerFaceColor',[1 0.85 0.1], ...
    'MarkerEdgeColor',[1 0.85 0.1],'MarkerSize',15,'DisplayName','MTN tower');

% Animated vehicle.
hVehicle = plot(axMap,rSAW.xPos(1),rSAW.yPos(1),'ko', ...
    'MarkerFaceColor',networkColors(1,:), ...
    'MarkerEdgeColor','w','MarkerSize',12,'DisplayName','Vehicle');

% Trail already travelled.
hTrail = plot(axMap,rSAW.xPos(1),rSAW.yPos(1),'-','LineWidth',2.5, ...
    'Color',[1 0 1],'HandleVisibility','off');

xlabel(axMap,'SUMO X (m)');
ylabel(axMap,'SUMO Y (m)');
title(axMap,sprintf('SUMO Vehicle %s | SAW + TOPSIS',traceData.vehicleID), ...
    'Color','w');

lg = legend(axMap,'Location','best');
lg.TextColor = 'w';
lg.Color = mapBG;
lg.EdgeColor = [0.7 0.7 0.7];

axis(axMap,'equal');

% Start with a useful fixed view instead of the complete network extent.
% The network reaches roughly Y=5800 m, so Y=8000 m itself is above the
% mapped road network. The limits below keep the upper/right SUMO region
% visible while still showing the complete UCT-to-Town trajectory.
xlim(axMap,[2500 8500]);
ylim(axMap,[1000 8000]);

statusText = text(axMap,0.02,0.97,'','Units','normalized', ...
    'VerticalAlignment','top','FontSize',11,'FontWeight','bold', ...
    'Color','w','BackgroundColor',mapBG,'Margin',6);

%% LIVE STATUS PANEL
panel = uipanel('Parent',fig,'Title','Live Network Status', ...
    'FontWeight','bold','Position',[0.70 0.54 0.27 0.41],'ForegroundColor','k', ...
    'BackgroundColor',[0.94 0.94 0.94]);

statusBox = uicontrol(panel,'Style','text','Units','normalized', ...
    'Position',[0.05 0.28 0.90 0.68], ...
    'HorizontalAlignment','left','FontSize',9.5,'BackgroundColor','w','ForegroundColor','k');

handoverBox = uicontrol(panel,'Style','text','Units','normalized', ...
    'Position',[0.05 0.04 0.90 0.20], ...
    'HorizontalAlignment','left','FontSize',10,'FontWeight','bold', ...
    'BackgroundColor','w','ForegroundColor','k', ...
    'String','SAW handovers: --\nTOPSIS handovers: --');

%% SAW DECISION SCORES
axSAW = axes('Parent',fig,'Position',[0.70 0.29 0.27 0.20], ...
    'Color',mapBG,'XColor','w','YColor','w');
hold(axSAW,'on'); grid(axSAW,'on'); box(axSAW,'on');
scoreSAW = gobjects(4,1);
for n = 1:4
    scoreSAW(n) = plot(axSAW,nan,nan,'LineWidth',1.25, ...
        'Color',networkColors(n,:));
end
xlabel(axSAW,'Time (s)');
ylabel(axSAW,'Score');
title(axSAW,'SAW decision scores','Color','k');
lg1 = legend(axSAW,networkNames,'Location','best');
lg1.TextColor = 'w'; lg1.Color = mapBG; lg1.EdgeColor = [0.7 0.7 0.7];

%% TOPSIS DECISION SCORES
axTOPSIS = axes('Parent',fig,'Position',[0.70 0.045 0.27 0.20], ...
    'Color',mapBG,'XColor','w','YColor','w');
hold(axTOPSIS,'on'); grid(axTOPSIS,'on'); box(axTOPSIS,'on');
scoreTOPSIS = gobjects(4,1);
for n = 1:4
    scoreTOPSIS(n) = plot(axTOPSIS,nan,nan,'LineWidth',1.25, ...
        'Color',networkColors(n,:));
end
xlabel(axTOPSIS,'Time (s)');
ylabel(axTOPSIS,'Score');
title(axTOPSIS,'TOPSIS decision scores','Color','k');
lg2 = legend(axTOPSIS,networkNames,'Location','best');
lg2.TextColor = 'w'; lg2.Color = mapBG; lg2.EdgeColor = [0.7 0.7 0.7];

%% ANIMATION
N = min([numel(rSAW.time),numel(rTOPSIS.time)]);
prevSAW = rSAW.selectedLog(1);
prevTOPSIS = rTOPSIS.selectedLog(1);

for k = 1:N
    if ~ishandle(fig), return; end

    t = rSAW.time(k);
    sawNet = rSAW.selectedLog(k);
    topsisNet = rTOPSIS.selectedLog(k);

    sawMetrics = rSAW.selectedMetricsLog(k,:);
    topsisMetrics = rTOPSIS.selectedMetricsLog(k,:);

    % Move the ONE vehicle using the shared trajectory.
    set(hVehicle,'XData',rSAW.xPos(k),'YData',rSAW.yPos(k));
    set(hTrail,'XData',rSAW.xPos(1:k),'YData',rSAW.yPos(1:k));

    sawHandovers = sum(diff(rSAW.selectedLog(1:k))~=0);
    topsisHandovers = sum(diff(rTOPSIS.selectedLog(1:k))~=0);

    % Both algorithms' live metrics.
    statusString = sprintf([ ...
        'TIME: %.2f s\n\n' ...
        'SAW: %s\n' ...
        '  Latency:       %8.2f ms\n' ...
        '  Packet loss:   %8.2f %%\n' ...
        '  Throughput:    %8.2f Mbps\n' ...
        '  Signal:        %8.2f dB\n' ...
        '\n' ...   % <-- replaces Cost line with a blank line
        'TOPSIS: %s\n' ...
        '  Latency:       %8.2f ms\n' ...
        '  Packet loss:   %8.2f %%\n' ...
        '  Throughput:    %8.2f Mbps\n' ...
        '  Signal:        %8.2f dB\n' ...
        '\n'], ... % <-- replaces Cost line with a blank line
        t,networkNames{sawNet}, ...
        sawMetrics(1),sawMetrics(2),sawMetrics(3),sawMetrics(4), ...
        networkNames{topsisNet}, ...
        topsisMetrics(1),topsisMetrics(2),topsisMetrics(3),topsisMetrics(4));
    set(statusBox,'String',statusString);


    % Live handover count. Final counts are displayed here after completion.
    if k > 1 && sawNet ~= prevSAW
        sawEvent = sprintf('SAW: %s -> %s',networkNames{prevSAW},networkNames{sawNet});
    else
        sawEvent = sprintf('SAW handovers: %d',sawHandovers);
    end

    if k > 1 && topsisNet ~= prevTOPSIS
        topsisEvent = sprintf('TOPSIS: %s -> %s',networkNames{prevTOPSIS},networkNames{topsisNet});
    else
        topsisEvent = sprintf('TOPSIS handovers: %d',topsisHandovers);
    end

    set(handoverBox,'String',sprintf('%s\n%s',sawEvent,topsisEvent));

    set(statusText,'String',sprintf('SAW: %s   |   TOPSIS: %s', ...
        networkNames{sawNet},networkNames{topsisNet}));

    % SAW score graph.
    for n = 1:4
        set(scoreSAW(n),'XData',rSAW.time(1:k),'YData',rSAW.scoresLog(1:k,n));
        set(scoreTOPSIS(n),'XData',rTOPSIS.time(1:k),'YData',rTOPSIS.scoresLog(1:k,n));
    end

    drawnow;
    pause(max(0,speedFactor));

    prevSAW = sawNet;
    prevTOPSIS = topsisNet;
end

% Final handover summary.
set(handoverBox,'String',sprintf( ...
    'SIMULATION COMPLETE\nSAW handovers: %d\nTOPSIS handovers: %d', ...
    rSAW.switches,rTOPSIS.switches), ...
    'ForegroundColor','k');

drawnow;

end

%% ========================================================================
function traceData = read_first_vehicle_trace(xmlFile)
% Select the FIRST vehicle ID encountered in trace.xml and then follow ONLY
% that vehicle. No distance-to-UCT logic and no vehicle ranking is used.

fid = fopen(xmlFile,'r');
if fid < 0, error('Could not open trace file: %s',xmlFile); end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

currentTime = NaN;
selectedID = '';
records = struct('time',{},'x',{},'y',{});

while true
    line = fgetl(fid);
    if ~ischar(line), break; end
    s = strtrim(line);

    if startsWith(s,'<timestep')
        tok = regexp(s,'time="([^"]+)"','tokens','once');
        if ~isempty(tok)
            currentTime = str2double(tok{1});
        end
        continue;
    end

    if contains(s,'<vehicle')
        idTok = regexp(s,'id="([^"]+)"','tokens','once');
        xTok  = regexp(s,'x="([^"]+)"','tokens','once');
        yTok  = regexp(s,'y="([^"]+)"','tokens','once');

        if isempty(idTok) || isempty(xTok) || isempty(yTok) || ~isfinite(currentTime)
            continue;
        end

        thisID = idTok{1};

        if isempty(selectedID)
            selectedID = thisID;
            fprintf('First vehicle found: %s\n',selectedID);
        end

        if strcmp(thisID,selectedID)
            q.time = currentTime;
            q.x = str2double(xTok{1});
            q.y = str2double(yTok{1});
            records(end+1) = q; %#ok<AGROW>
        end
    end
end

if isempty(records)
    error('No vehicle observations were found in %s.',xmlFile);
end

[tt,order] = sort([records.time]);
xx = [records(order).x]';
yy = [records(order).y]';

[tt,ia] = unique(tt,'stable');
xx = xx(ia);
yy = yy(ia);

N = min(500,numel(tt));
tt = tt(1:N);
xx = xx(1:N);
yy = yy(1:N);

d = hypot(diff(xx),diff(yy));
if any(d > 300)
    warning(['Vehicle %s contains %d position jumps greater than 300 m. ' ...
             'The animation will show the trajectory exactly as supplied.'], ...
             selectedID,sum(d>300));
end

traceData.time = tt;
traceData.xPos = xx;
traceData.yPos = yy;
traceData.vehicleID = selectedID;
end

%% ========================================================================
function roadMap = read_sumo_road_map(netFile)
% Simple full-network reader. No route cropping or spatial search.
% Only the first lane shape for each non-internal edge is drawn.

fid = fopen(netFile,'r');
if fid < 0, error('Could not open SUMO network file: %s',netFile); end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

xAll = [];
yAll = [];
insideEdge = false;
skipEdge = false;
laneRead = false;

while true
    line = fgetl(fid);
    if ~ischar(line), break; end
    s = strtrim(line);

    if startsWith(s,'<edge ')
        insideEdge = true;
        skipEdge = contains(s,'function="internal"') || contains(s,'function=''internal''');
        laneRead = false;
        continue;
    end

    if insideEdge && startsWith(s,'<lane ') && ~skipEdge && ~laneRead
        tok = regexp(s,'shape="([^"]+)"','tokens','once');
        if ~isempty(tok)
            pairs = regexp(tok{1},'(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)','tokens');
            if ~isempty(pairs)
                xx = zeros(numel(pairs),1);
                yy = zeros(numel(pairs),1);
                for p = 1:numel(pairs)
                    xx(p) = str2double(pairs{p}{1});
                    yy(p) = str2double(pairs{p}{2});
                end
                xAll = [xAll;xx;NaN]; %#ok<AGROW>
                yAll = [yAll;yy;NaN]; %#ok<AGROW>
                laneRead = true;
            end
        end
    end

    if startsWith(s,'</edge>')
        insideEdge = false;
        skipEdge = false;
        laneRead = false;
    end
end

roadMap.x = xAll;
roadMap.y = yAll;
end
