function tf = isTorque(cluster)
%ISTORQUE True if we're submitting to a Torque scheduler, false for
% OpenPBS/PBS Pro.

% Copyright 2022 The MathWorks, Inc.

if isfield(cluster.UserData, 'IsTorque')
    tf = cluster.UserData.IsTorque;
    return
end

% The output of 'qstat --version' is different on OpenPBS/PBS Pro and
% Torque. On TORQUE it is of the form:
% 'Version: 6.1.2
%  Commit: 661e092552de43a785c15d39a3634a541d86898e'
% On OpenPBS/PBS Pro it is of the form:
% 'pbs_version = 19.0.0'.
commandToRun = 'qstat --version';
try
    % Make the shelled out call to run the command.
    [cmdFailed, cmdOut] = runSchedulerCommand(commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
if cmdFailed
    error('parallelexamples:GenericPBS:FailedToRetrieveInfo', ...
        'Failed to retrieve PBS version using command:\n\t%s.\nReason: %s', ...
        commandToRun, cmdOut);
end

tf = ~contains(cmdOut, 'pbs_version');
cluster.UserData.IsTorque = tf;

end
