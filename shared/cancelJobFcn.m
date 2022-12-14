function OK = cancelJobFcn(cluster, job)
%CANCELJOBFCN Cancels a job on PBS
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you cancel a job.

% Copyright 2010-2022 The MathWorks, Inc.

% Store the current filename for the errors, warnings and
% dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericPBS:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end
if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericPBS:NotSharedFileSystem', ...
        'The function %s is for use with shared filesystems.', currFilename)
end
% Get the information about the actual cluster used
data = cluster.getJobClusterData(job);
if isempty(data)
    % This indicates that the job has not been submitted, so return true
    dctSchedulerMessage(1, '%s: Job cluster data was empty for job with ID %d.', currFilename, job.ID);
    OK = true;
    return
end

% Get a simplified list of schedulerIDs to reduce the number of calls to
% the scheduler.
schedulerIDs = getSimplifiedSchedulerIDsForJob(job);
erroredJobAndCauseStrings = cell(size(schedulerIDs));
% Get the cluster to delete the job
for ii = 1:length(schedulerIDs)
    schedulerID = schedulerIDs{ii};
    commandToRun = sprintf('qdel "%s"', schedulerID);
    dctSchedulerMessage(4, '%s: Canceling job on cluster using command:\n\t%s.', currFilename, commandToRun);
    try
        % Make the shelled out call to run the command.
        [cmdFailed, cmdOut] = runSchedulerCommand(commandToRun);
    catch err
        cmdFailed = true;
        cmdOut = err.message;
    end
    % If a job is already in a terminal state, qdel will return a failed
    % error code and cmdOut will be one of the following forms:
    % - 'qdel: Request invalid for state of job MSG=invalid state for job - COMPLETE 1936' (Torque)
    % - 'qdel: nonexistent job id: 23' (Torque)
    % - 'qdel: Unknown Job Id 432[]' (PBS Pro)
    % - 'qdel: Job has finished' (PBS Pro)
    % If this happens we do not consider the command to have failed.
    if cmdFailed && ~contains(cmdOut, {'nonexistent job id', 'Request invalid for state of job', 'Unknown Job Id', 'Job has finished'})
        % Keep track of all jobs that errored when being cancelled, either
        % through a bad exit code or if an error was thrown. We'll report
        % these later on.
        erroredJobAndCauseStrings{ii} = sprintf('Job ID: %s\tReason: %s', schedulerID, strtrim(cmdOut));
        dctSchedulerMessage(1, '%s: Failed to cancel job %s on cluster.  Reason:\n\t%s', currFilename, schedulerID, cmdOut);
    end
end

% Now warn about those jobs that we failed to cancel.
erroredJobAndCauseStrings = erroredJobAndCauseStrings(~cellfun(@isempty, erroredJobAndCauseStrings));
if ~isempty(erroredJobAndCauseStrings)
    warning('parallelexamples:GenericPBS:FailedToCancelJob', ...
        'Failed to cancel the following jobs on the cluster:\n%s', ...
        sprintf('  %s\n', erroredJobAndCauseStrings{:}));
end
OK = isempty(erroredJobAndCauseStrings);

end
