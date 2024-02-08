function submitString = getSubmitString(jobName, quotedLogFile, quotedCommand, ...
    additionalSubmitArgs, jobArrayString)
%GETSUBMITSTRING Gets the correct qsub command for a PBS cluster

% Copyright 2010-2023 The MathWorks, Inc.

% Submit to PBS using qsub. Note the following:
% "-N Job#" - specifies the job name
% "-J ..." - specifies a job array string
% "-j oe" joins together output and error streams
% "-o ..." specifies where standard output goes to

if ~isempty(jobArrayString)
    jobArrayString = strcat('-J ', jobArrayString);
end

submitString = sprintf('qsub -N %s %s -j oe -o %s %s %s', ...
    jobName, jobArrayString, quotedLogFile, additionalSubmitArgs, quotedCommand);

end
