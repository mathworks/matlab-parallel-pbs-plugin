function independentSubmitFcn(cluster, job, environmentProperties)
%INDEPENDENTSUBMITFCN Submit a MATLAB job to a PBS cluster
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you submit an independent job.
%
% See also parallel.cluster.generic.independentDecodeFcn.

% Copyright 2010-2022 The MathWorks, Inc.

% Store the current filename for the errors, warnings and
% dctSchedulerMessages.
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericPBS:NotClusterObject', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.independentDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericPBS:NotSharedFileSystem', ...
        'The function %s is for use with shared filesystems.', currFilename)
end

if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericPBS:UnsupportedOS', ...
        'The function %s only supports clusters with unix OS.', currFilename)
end

[useJobArrays, maxJobArraySize] = iGetJobArrayProps(cluster);
% Store data for future reference
cluster.UserData.UseJobArrays = useJobArrays;
if useJobArrays
    cluster.UserData.MaxJobArraySize = maxJobArraySize;
end

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

% Deduce the correct quote to use based on the OS of the current machine
if ispc
    quote = '"';
else
    quote = '''';
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
    'PARALLEL_SERVER_STORAGE_LOCATION', environmentProperties.StorageLocation};
% Environment variable names different prior to 19b
if verLessThan('matlab', '9.7')
    variables(:,1) = replace(variables(:,1), 'PARALLEL_SERVER_', 'MDCE_');
end
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);

% The local job directory
localJobDirectory = cluster.getJobFolder(job);

% The script name is independentJobWrapper.sh
scriptName = 'independentJobWrapper.sh';
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
quotedScriptName = sprintf('%s%s%s', quote, fullfile(dirpart, scriptName), quote);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if iCanUseSelect(cluster)
    additionalSubmitArgs = sprintf('-l select=1:ncpus=%d', cluster.NumThreads);
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
    numberOfProcs = min(procsPerNode, cluster.NumThreads);
    additionalSubmitArgs = sprintf('-l nodes=1:ppn=%d', numberOfProcs);
end

commonSubmitArgs = getCommonSubmitArgs(cluster);
additionalSubmitArgs = strtrim(sprintf('%s %s', additionalSubmitArgs, commonSubmitArgs));

% Only keep and submit tasks that are not cancelled. Cancelled tasks
% will have errors.
isPendingTask = cellfun(@isempty, get(job.Tasks, {'Error'}));
tasks = job.Tasks(isPendingTask);
taskIDs = cell2mat(get(tasks, {'ID'}));
numberOfTasks = numel(tasks);

% Only use job arrays when you can get enough use out of them.
if numberOfTasks < 2 || maxJobArraySize <= 0
    useJobArrays = false;
end

if useJobArrays
    % PBS Pro places a limit on the number of jobs that may be submitted as
    % a single job array. The default value is 10,000 jobs. If there are
    % more tasks in this job than will fit in a single job array, submit
    % the tasks as several smaller job arrays. PBS Pro accepts job arrays
    % with indices greater than maxArraySize, providing the number of
    % indices is less than maxJobArraySize. For example, if maxJobArraySize
    % is 10000, then indices [10001-20000] would be valid.
    taskIDGroupsForJobArrays = iCalculateTaskIDGroupsForJobArrays(taskIDs, maxJobArraySize);
    
    jobName = sprintf('Job%d',job.ID);
    % PBS jobs names must not exceed 15 characters
    maxJobNameLength = 15;
    if length(jobName) > maxJobNameLength
        jobName = jobName(1:maxJobNameLength);
    end
    numJobArrays = numel(taskIDGroupsForJobArrays);
    commandsToRun = cell(numJobArrays, 1);
    jobIDs = cell(numJobArrays, 1);
    schedulerJobArrayIndices = cell(numJobArrays, 1);
    for ii = 1:numJobArrays
        schedulerJobArrayIndices{ii} = taskIDGroupsForJobArrays{ii};
        
        % Create a character vector with the ranges of IDs to submit.
        jobArrayString = iCreateJobArrayString(schedulerJobArrayIndices{ii});
        
        logFileName = 'Task^array_index^.log';
        % Choose a file for the output. Please note that currently,
        % JobStorageLocation refers to a directory on disk, but this may
        % change in the future.
        logFile = fullfile(localJobDirectory, logFileName);
        quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
        dctSchedulerMessage(5, '%s: Using %s as log file', currFilename, quotedLogFile);
        
        environmentVariables = variables;
        % Create a script to submit a PBS job - this
        % will be created in the job directory
        dctSchedulerMessage(5, '%s: Generating script for job array %i', currFilename, ii);
        commandsToRun{ii} = iGetCommandToRun(localJobDirectory, jobName, quote, ...
            quotedLogFile, quotedScriptName, environmentVariables, additionalSubmitArgs, jobArrayString);
    end
else
    % Do not use job arrays and submit each task individually.
    taskLocations = environmentProperties.TaskLocations(isPendingTask);
    jobIDs = cell(1, numberOfTasks);
    commandsToRun = cell(numberOfTasks, 1);
    % Loop over every task we have been asked to submit
    for ii = 1:numberOfTasks
        taskLocation = taskLocations{ii};
        % Add the task location to the environment variables
        if verLessThan('matlab', '9.7') % variable name changed in 19b
            environmentVariables = [variables; ...
                {'MDCE_TASK_LOCATION', taskLocation}];
        else
            environmentVariables = [variables; ...
                {'PARALLEL_SERVER_TASK_LOCATION', taskLocation}];
        end
        
        % Choose a file for the output. Please note that currently,
        % JobStorageLocation refers to a directory on disk, but this may
        % change in the future.
        logFile = cluster.getLogLocation(tasks(ii));
        quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
        dctSchedulerMessage(5, '%s: Using %s as log file', currFilename, quotedLogFile);
        
        % Submit one task at a time
        jobName = sprintf('Job%d.%d', job.ID, taskIDs(ii));
        % PBS jobs names must not exceed 15 characters
        maxJobNameLength = 15;
        if length(jobName) > maxJobNameLength
            jobName = jobName(1:maxJobNameLength);
        end
        
        % Create a script to submit a PBS job - this will be created in
        % the job directory
        dctSchedulerMessage(5, '%s: Generating script for task %i', currFilename, ii);
        commandsToRun{ii} = iGetCommandToRun(localJobDirectory, jobName, quote, ...
            quotedLogFile, quotedScriptName, environmentVariables, additionalSubmitArgs);
    end
end

for ii=1:numel(commandsToRun)
    commandToRun = commandsToRun{ii};
    jobIDs{ii} = iSubmitJobUsingCommand(commandToRun, job, logFile);
end

% Calculate the schedulerIDs
if useJobArrays
    % The scheduler ID of each task is a combination of the job ID and the
    % scheduler array index. cellfun pairs each job ID with its
    % corresponding scheduler array indices in schedulerJobArrayIndices and
    % returns the combination of both. For example, if jobIDs = {1,2} and
    % schedulerJobArrayIndices = {[1,2];[3,4]}, the schedulerID is given by
    % combining 1 with [1,2] and 2 with [3,4], in the canonical form of the
    % scheduler.
    schedulerIDs = cellfun(@(jobID,arrayIndices) strrep(jobID, "[]", ...
        "[" + arrayIndices + "]"), jobIDs, schedulerJobArrayIndices, ...
        'UniformOutput',false);
    schedulerIDs = vertcat(schedulerIDs{:});
else
    % The scheduler ID of each task is the job ID.
    schedulerIDs = string(jobIDs);
end

% Store the scheduler ID for each task and the job cluster data
jobData = struct('type', 'generic');
if verLessThan('matlab', '9.7') % schedulerID stored in job data
    jobData.ClusterJobIDs = schedulerIDs;
else % schedulerID on task since 19b
    set(tasks, 'SchedulerID', schedulerIDs);
end
cluster.setJobClusterData(job, jobData);

end

function [useJobArrays, maxJobArraySize] = iGetJobArrayProps(cluster)
% Look for useJobArrays and maxJobArray size in the following order:
% 1.  Additional Properties
% 2.  User Data
% 3.  Query scheduler for MaxJobArraySize

useJobArrays = validatedPropValue(cluster.AdditionalProperties, 'UseJobArrays', 'logical');
if isempty(useJobArrays)
    if isfield(cluster.UserData, 'UseJobArrays')
        useJobArrays = cluster.UserData.UseJobArrays;
    else
        useJobArrays = true;
    end
end

if ~useJobArrays
    % Not using job arrays so don't need the max array size
    maxJobArraySize = 0;
    return
end

maxJobArraySize = validatedPropValue(cluster.AdditionalProperties, 'MaxJobArraySize', 'numeric');
if ~isempty(maxJobArraySize)
    if maxJobArraySize < 1
        error('parallelexamples:GenericPBS:IncorrectArguments', ...
            'MaxJobArraySize must be a positive integer');
    end
    return
end

if isfield(cluster.UserData,'MaxJobArraySize')
    maxJobArraySize = cluster.UserData.MaxJobArraySize;
    return
end

% Define default return values
maxJobArraySize = 0;
useJobArrays = false;

if isTorque(cluster)
    % The job array integration in this plugin script does not support
    % Torque so disable job arrays.
    return
end

% If we get here, the scheduler is OpenPBS/PBS Pro.
% Get job array information by querying the scheduler.
commandToRun = 'qstat -Bf';
try
    % Make the shelled out call to run the command.
    [cmdFailed, cmdOut] = runSchedulerCommand(commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
if cmdFailed
    error('parallelexamples:GenericPBS:FailedToRetrieveInfo', ...
        'Failed to retrieve PBS configuration information using command:\n\t%s.\nReason: %s', ...
        commandToRun, cmdOut);
end

% Extract the maximum array size for job arrays.  For PBS Pro, the
% configuration line that contains the maximum array size looks like this:
% max_array_size = 10000
% Use a regular expression to extract this parameter.
tokens = regexp(cmdOut, 'max_array_size\s*=\s*(\d+)', 'tokens', 'once');

if isempty(tokens)
    % No job array support.
    return
end

useJobArrays = true;
maxJobArraySize = str2double(tokens{1});
end

function commandToRun = iGetCommandToRun(localJobDirectory, jobName, quote, ...
    quotedLogFile, quotedScriptName, environmentVariables, additionalSubmitArgs, jobArrayString)
if nargin < 8
    jobArrayString = [];
end

localScriptName = tempname(localJobDirectory);
createSubmitScript(localScriptName, jobName, quotedLogFile, quotedScriptName, ...
    environmentVariables, additionalSubmitArgs, jobArrayString);
% Create the command to run
commandToRun = sprintf('sh %s%s%s', quote, localScriptName, quote);
end

function jobID = iSubmitJobUsingCommand(commandToRun, job, logFile)
currFilename = mfilename;
% Ask the cluster to run the submission command.
dctSchedulerMessage(4, '%s: Submitting job %d using command:\n\t%s', currFilename, job.ID, commandToRun);
try
    % Make the shelled out call to run the command.
    [cmdFailed, cmdOut] = runSchedulerCommand(commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
if cmdFailed
    error('parallelexamples:GenericPBS:SubmissionFailed', ...
        'Submit failed with the following message:\n%s', cmdOut);
end

dctSchedulerMessage(1, '%s: Job output will be written to: %s\nSubmission output: %s\n', currFilename, logFile, cmdOut);

jobID = extractJobId(cmdOut);
if isempty(jobID)
    error('parallelexamples:GenericPBS:FailedToParseSubmissionOutput', ...
        'Failed to parse the job identifier from the submission output: "%s"', ...
        cmdOut);
end
end

function rangeString = iCreateJobArrayString (taskIDs)
if taskIDs(1) == taskIDs(end)
    % PBS Pro does not support a one-element interval. To submit a job
    % array of size 1, use a stepping factor that truncates the interval.
    rangeString = sprintf('%d-%d:2',taskIDs(1),taskIDs(end)+1);
else
    rangeString = sprintf('%d-%d',taskIDs(1),taskIDs(end));
end
end

function taskIDGroupsForJobArrays = iCalculateTaskIDGroupsForJobArrays(taskIDsToSubmit, maxJobArraySize)
% Calculates the groups of task IDs to be submitted as job arrays

% We can only put tasks with sequential IDs into the same job array
% (the taskIDs will not be sequential if any tasks have been cancelled or
% deleted). We also need to ensure that each job array is smaller than
% maxJobArraySize.  So we first identify the sequential task IDs, and then
% split them apart into chunks of maxJobArraySize.

% The end of a range of sequential task IDs can be identifed where
% diff(taskIDsToSubmit) > 1. We also know the last taskID to be the end of
% a range.
isEndOfSequentialTaskIDs = [diff(taskIDsToSubmit) > 1; true];
endOfSequentialTaskIDsIdx = find(isEndOfSequentialTaskIDs);

% The difference between indices give the number of tasks in each range.
numTasksInEachRange = [endOfSequentialTaskIDsIdx(1); diff(endOfSequentialTaskIDsIdx)];

% The number of tasks in each job array must be less than maxJobArraySize.
jobArraySizes = arrayfun(@(x) iCalculateJobArraySizes(x, maxJobArraySize), numTasksInEachRange, 'UniformOutput', false);
jobArraySizes = [jobArraySizes{:}];
taskIDGroupsForJobArrays = mat2cell(taskIDsToSubmit, jobArraySizes);
end

function jobArraySizes = iCalculateJobArraySizes(numTasks, maxJobArraySize)
if isinf(maxJobArraySize)
    numJobArrays = 1;
else
    numJobArrays = ceil(numTasks./maxJobArraySize);
end
jobArraySizes = repmat(maxJobArraySize, 1, numJobArrays);
remainder = mod(numTasks, maxJobArraySize);
if remainder > 0
    jobArraySizes(end) = remainder;
end
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
