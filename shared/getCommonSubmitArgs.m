function commonSubmitArgs = getCommonSubmitArgs(cluster)
% Get any additional submit arguments for the PBS qsub command
% that are common to both independent and communicating jobs.

% Copyright 2016-2022 The MathWorks, Inc.

commonSubmitArgs = '';
ap = cluster.AdditionalProperties;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% You may wish to support further cluster.AdditionalProperties fields here
% and modify the submission command arguments accordingly.

% Account name
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'AccountName', 'char', '-A %s');

% Priority
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'Priority', 'double', '-p %d');

% Queue
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'QueueName', 'char', '-q %s');

% Wall time
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'WallTime', 'char', '-l walltime=%s');

% Email notification
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'EmailAddress', 'char', '-M %s -m abe');

% Catch all: directly append anything in the AdditionalSubmitArgs
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'AdditionalSubmitArgs', 'char', '%s');

% Trim any whitespace
commonSubmitArgs = strtrim(commonSubmitArgs);

end

function commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, propName, propType, submitPattern)
arg = validatedPropValue(ap, propName, propType);
if ~isempty(arg) && (~islogical(arg) || arg)
    commonSubmitArgs = sprintf([commonSubmitArgs ' ' submitPattern], arg);
end
end
