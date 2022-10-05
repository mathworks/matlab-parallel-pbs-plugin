function communicatingSubmitFcn(cluster, job, environmentProperties)
%COMMUNICATINGSUBMITFCN Submit a communicating MATLAB job to a PBS cluster
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you submit a communicating job.
%
% See also parallel.cluster.generic.communicatingDecodeFcn.

% Copyright 2010-2022 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericPBS:NotClusterObject', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.communicatingDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericPBS:NotSharedFileSystem', ...
        'The function %s is for use with shared filesystems.', currFilename)
end

if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericPBS:UnsupportedOS', ...
        'The function %s only supports clusters with unix OS.', currFilename)
end

remoteConnection = getRemoteConnection(cluster);

% Determine the debug setting. Setting to true makes the MATLAB workers
% output additional logging. If EnableDebug is set in the cluster object's
% AdditionalProperties, that takes precedence. Otherwise, look for the
% PARALLEL_SERVER_DEBUG and MDCE_DEBUG environment variables in that order.
% If nothing is set, debug is false.
enableDebug = 'false';
if isprop(cluster.AdditionalProperties, 'EnableDebug')
    % Use AdditionalProperties.EnableDebug, if it is set
    enableDebug = char(string(cluster.AdditionalProperties.EnableDebug));
else
    % Otherwise check the environment variables set locally on the client
    environmentVariablesToCheck = {'PARALLEL_SERVER_DEBUG', 'MDCE_DEBUG'};
    for idx = 1:numel(environmentVariablesToCheck)
        debugValue = getenv(environmentVariablesToCheck{idx});
        if ~isempty(debugValue)
            enableDebug = debugValue;
            break
        end
    end
end

% Get the correct quote and file separator for the Cluster OS.
% This check is unnecessary in this file because we explicitly
% checked that the ClusterOsType is unix.  This code is an example
% of how to deal with clusters that can be unix or pc.
if strcmpi(cluster.OperatingSystem, 'unix')
    quote = '''';
    fileSeparator = '/';
else
    quote = '"';
    fileSeparator = '\';
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(environmentProperties.MatlabArguments);

variables = {'PARALLEL_SERVER_DECODE_FUNCTION', decodeFunction; ...
    'PARALLEL_SERVER_STORAGE_CONSTRUCTOR', environmentProperties.StorageConstructor; ...
    'PARALLEL_SERVER_JOB_LOCATION', environmentProperties.JobLocation; ...
    'PARALLEL_SERVER_MATLAB_EXE', environmentProperties.MatlabExecutable; ...
    'PARALLEL_SERVER_MATLAB_ARGS', matlabArguments; ...
    'PARALLEL_SERVER_DEBUG', enableDebug; ...
    'MLM_WEB_LICENSE', environmentProperties.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', environmentProperties.UserToken; ...
    'MLM_WEB_ID', environmentProperties.LicenseWebID; ...
    'PARALLEL_SERVER_LICENSE_NUMBER', environmentProperties.LicenseNumber; ...
    'PARALLEL_SERVER_STORAGE_LOCATION', environmentProperties.StorageLocation; ...
    'PARALLEL_SERVER_CMR', strip(cluster.ClusterMatlabRoot, 'right', '/'); ...
    'PARALLEL_SERVER_TOTAL_TASKS', num2str(environmentProperties.NumberOfTasks); ...
    'PARALLEL_SERVER_NUM_THREADS', num2str(cluster.NumThreads)};
% Environment variable names different prior to 19b
if verLessThan('matlab', '9.7')
    variables(:,1) = replace(variables(:,1), 'PARALLEL_SERVER_', 'MDCE_');
end
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);

% The local job directory
localJobDirectory = cluster.getJobFolder(job);
% Find out how we should refer to the job storage location on the cluster.
remoteJobDirectory = cluster.getJobFolderOnCluster(job);
% Specify the job wrapper script to use.
% Prior to R2019a, only the SMPD process manager is supported.
if verLessThan('matlab', '9.6') || ...
        validatedPropValue(cluster.AdditionalProperties, 'UseSmpd', 'logical', false)
    scriptName = 'communicatingJobWrapperSmpd.sh';
else
    scriptName = 'communicatingJobWrapper.sh';
end
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
localScript = fullfile(dirpart, scriptName);
% Copy the local wrapper script to the job directory
copyfile(localScript, localJobDirectory);

% The command that will be executed on the remote host to run the job.
remoteScriptName = sprintf('%s%s%s', remoteJobDirectory, fileSeparator, scriptName);
quotedScriptName = sprintf('%s%s%s', quote, remoteScriptName, quote);

% Choose a file for the output. Please note that currently, JobStorageLocation refers
% to a directory on disk, but this may change in the future.
logFile = sprintf('%s%s%s', remoteJobDirectory, fileSeparator, sprintf('Job%d.log', job.ID));
quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
dctSchedulerMessage(5, '%s: Using %s as log file', currFilename, quotedLogFile);

jobName = sprintf('Job%d', job.ID);

% PBS jobs names must not exceed 15 characters
maxJobNameLength = 15;
if length(jobName) > maxJobNameLength
    jobName = jobName(1:maxJobNameLength);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if iCanUseSelect(cluster)
    additionalSubmitArgs = sprintf('-l select=%d:ncpus=%d', ...
        environmentProperties.NumberOfTasks, cluster.NumThreads);
    dctSchedulerMessage(4, '%s: Requesting %d chunks with %d processors per chunk', currFilename, ...
        environmentProperties.NumberOfTasks, cluster.NumThreads);
else
    % Choose a number of processors per node to use. Use the value in
    % AdditionalProperties if specified, or default to 2. You may wish to
    % customize the default value to match your cluster.
    procsPerNode = validatedPropValue(cluster.AdditionalProperties, ...
        'ProcsPerNode', 'numeric', 2);
    if isnan(procsPerNode) || procsPerNode < 1 || mod(procsPerNode, 1) ~= 0
        error('parallelexamples:GenericPBS:IncorrectArguments', ...
            'ProcsPerNode must be a positive integer');
    end
    tasksPerNode = max([floor(procsPerNode/cluster.NumThreads) 1]);
    numberOfNodes = ceil(environmentProperties.NumberOfTasks/tasksPerNode);
    additionalSubmitArgs = sprintf('-l nodes=%d:ppn=%d', numberOfNodes, procsPerNode);
    dctSchedulerMessage(4, '%s: Requesting %d nodes with %d processors per node', currFilename, ...
        numberOfNodes, procsPerNode);
end

commonSubmitArgs = getCommonSubmitArgs(cluster);
additionalSubmitArgs = strtrim(sprintf('%s %s', additionalSubmitArgs, commonSubmitArgs));

% Create a script to submit a PBS job - this will be created in the job directory
dctSchedulerMessage(5, '%s: Generating script for job.', currFilename);
localScriptName = tempname(localJobDirectory);
[~, scriptName] = fileparts(localScriptName);
remoteScriptLocation = sprintf('%s%s%s%s%s', quote, remoteJobDirectory, fileSeparator, scriptName, quote);
createSubmitScript(localScriptName, jobName, quotedLogFile, quotedScriptName, ...
    variables, additionalSubmitArgs);
% Create the command to run on the remote host.
commandToRun = sprintf('sh %s', remoteScriptLocation);

% Add execute permissions to shell scripts
remoteConnection.runCommand(sprintf( ...
    'chmod u+x %s%s*.sh', remoteJobDirectory, fileSeparator));

% Now ask the cluster to run the submission command
dctSchedulerMessage(4, '%s: Submitting job using command:\n\t%s', currFilename, commandToRun);
% Execute the command on the remote host.
[cmdFailed, cmdOut] = remoteConnection.runCommand(commandToRun);
if cmdFailed
    error('parallelexamples:GenericPBS:FailedToSubmitJob', ...
        'Failed to submit job to PBS using command:\n\t%s.\nReason: %s', ...
        commandToRun, cmdOut);
end

% Calculate the schedulerIDs
jobIDs = extractJobId(cmdOut);
if isempty(jobIDs)
    error('parallelexamples:GenericPBS:FailedToParseSubmissionOutput', ...
        'Failed to parse the job identifier from the submission output: "%s"', ...
        cmdOut);
end
% jobIDs must be a cell array
if ~iscell(jobIDs)
    jobIDs = {jobIDs};
end

% Store the scheduler ID for each task and the job cluster data
% Set the cluster host on the job cluster data
jobData = struct('type', 'generic', ...
    'RemoteHost',  remoteConnection.Hostname);
if verLessThan('matlab', '9.7') % schedulerID stored in job data
    jobData.ClusterJobIDs = jobIDs;
else % schedulerID on task since 19b
    if numel(job.Tasks) == 1
        schedulerIDs = jobIDs{1};
    else
        schedulerIDs = repmat(jobIDs, size(job.Tasks));
    end
    set(job.Tasks, 'SchedulerID', schedulerIDs);
end
cluster.setJobClusterData(job, jobData);

end

function useSelect = iCanUseSelect(cluster)
% Determine if we can use the select syntax for acquiring resources or need
% to use the nodes and ppn syntax.

% Use the value in AdditionalProperties if set
useSelect = validatedPropValue(cluster.AdditionalProperties, 'UseSelect', 'logical');
if ~isempty(useSelect)
    return
end

% Otherwise check the cluster's UserData
if isfield(cluster.UserData, 'UseSelect')
    useSelect = cluster.UserData.UseSelect;
    return
end

% Otherwise we'll use select on OpenPBS/PBS Pro but not Torque
useSelect = ~isTorque(cluster);
cluster.UserData.UseSelect = useSelect;
end
