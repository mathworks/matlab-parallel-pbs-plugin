function submitString = getSubmitString(jobName, quotedLogFile, quotedCommand, ...
    varsToForward, additionalSubmitArgs, jobArrayString)
%GETSUBMITSTRING Gets the correct qsub command for a PBS cluster

% Copyright 2010-2022 The MathWorks, Inc.

envString = strjoin(varsToForward', ',');

% Submit to PBS using qsub. Note the following:
% "-N Job#" - specifies the job name
% "-J ..." - specifies a job array string
% "-j oe" joins together output and error streams
% "-o ..." specifies where standard output goes to
% envString has the "-v 'NAME,NAME2'" piece.

if ~isempty(jobArrayString)
    jobArrayString = strcat('-J ', jobArrayString);
end

submitString = sprintf('qsub -N %s %s -j oe -o %s -v %s %s %s', ...
    jobName, jobArrayString, quotedLogFile, envString, additionalSubmitArgs, quotedCommand);

end
