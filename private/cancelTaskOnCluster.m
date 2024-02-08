function OK = cancelTaskOnCluster(cluster, task)
%CANCELTASKONCLUSTER Cancels a task on the PBS scheduler

% Copyright 2020-2023 The MathWorks, Inc.

% Store the current filename for the errors, warnings and
% dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericPBS:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

% Get the information about the actual cluster used
data = cluster.getJobClusterData(task.Parent);
if isempty(data)
    % This indicates that the parent job has not been submitted, so return true
    dctSchedulerMessage(1, '%s: Job cluster data was empty for the parent job with ID %d.', currFilename, task.Parent.ID);
    OK = true;
    return
end
% We can't cancel a single task of a communicating job on the scheduler
% without cancelling the entire job, so warn and return in this case
if ~strcmpi(task.Parent.Type, 'independent')
    OK = false;
    warning('parallelexamples:GenericPBS:FailedToCancelTask', ...
        'Unable to cancel a single task of a communicating job. If you want to cancel the entire job, use the cancel function on the job object instead.');
    return
end

% Get the cluster to delete the task
if verLessThan('matlab', '9.7') % schedulerID stored in job data
    schedulerIDs = data.ClusterJobIDs;
    schedulerID = schedulerIDs{task.ID};
else % schedulerID on task since 19b
    schedulerID = task.SchedulerID;
end
erroredTaskAndCauseString = '';
commandToRun = sprintf('qdel "%s"', schedulerID);
dctSchedulerMessage(4, '%s: Canceling task on cluster using command:\n\t%s.', currFilename, commandToRun);
try
    [cmdFailed, cmdOut] = runSchedulerCommand(cluster, commandToRun);
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
    % Record if the task errored when being cancelled, either through a bad
    % exit code or if an error was thrown. We'll report this as a warning.
    erroredTaskAndCauseString = sprintf('Job ID: %s\tReason: %s', schedulerID, strtrim(cmdOut));
    dctSchedulerMessage(1, '%s: Failed to cancel task %s on cluster.  Reason:\n\t%s', currFilename, schedulerID, cmdOut);
end

% Warn if task cancellation failed.
OK = isempty(erroredTaskAndCauseString);
if ~OK
    warning('parallelexamples:GenericPBS:FailedToCancelTask', ...
        'Failed to cancel the task on the cluster:\n  %s\n', ...
        erroredTaskAndCauseString);
end

end
