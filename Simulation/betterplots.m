function betterplots(resDir)
%BETTERPLOTS Backward-compatible entry point for the report plotting script.
% Keep this file alongside generate_report_plots.m. It declares betterplots,
% not generate_report_plots, so MATLAB function/file names match.
if nargin < 1
    generate_report_plots();
else
    generate_report_plots(resDir);
end
end
