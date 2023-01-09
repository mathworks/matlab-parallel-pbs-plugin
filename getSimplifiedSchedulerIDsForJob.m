function schedulerIDs = getSimplifiedSchedulerIDsForJob(job)
%GETSIMPLIFIEDSCHEDULERIDSFORJOB Returns the smallest possible list of PBS job IDs that describe the MATLAB job.
%
% SCHEDULERIDS = getSimplifiedSchedulerIDsForJob(JOB) returns the smallest
% possible list of PBS job IDs that describe the MATLAB job JOB. The
% function converts child job IDs of a job array to the parent job ID of
% the array, and removes any duplicates.

% Copyright 2019-2022 The MathWorks, Inc.

if verLessThan('matlab', '9.7') % schedulerID stored in job data
    data = job.Parent.getJobClusterData(job);
    schedulerIDs = data.ClusterJobIDs;
else % schedulerID on task since 19b
    schedulerIDs = job.getTaskSchedulerIDs();
end

% Child jobs within a job array will have a schedulerID of the form
% <parent job ID>[<array index>].<server name>, whilst the ID of the array
% is of the form <parent job ID>[].<server name>. (PBS Pro does not
% recognise the ID if you omit the '[]').  Non array jobs do not contain
% '[]' after the ID number.
schedulerIDs = regexprep(schedulerIDs, '\[\d+\]', '[]');
schedulerIDs = unique(schedulerIDs, 'stable');
end
