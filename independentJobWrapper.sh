#!/bin/sh
# This wrapper script is intended to support independent execution.
#
# This script uses the following environment variables set by the submit MATLAB code:
# PARALLEL_SERVER_MATLAB_EXE  - the MATLAB executable to use
# PARALLEL_SERVER_MATLAB_ARGS - the MATLAB args to use

# Copyright 2010-2024 The MathWorks, Inc.

# If PARALLEL_SERVER_ environment variables are not set, assign any
# available values with form MDCE_ for backwards compatibility
PARALLEL_SERVER_MATLAB_EXE=${PARALLEL_SERVER_MATLAB_EXE:="${MDCE_MATLAB_EXE}"}
PARALLEL_SERVER_MATLAB_ARGS=${PARALLEL_SERVER_MATLAB_ARGS:="${MDCE_MATLAB_ARGS}"}

# Echo the node that the scheduler has allocated to this job:
echo "The scheduler has allocated the following node to this job: `hostname`"

# PBS will set TMPDIR to a folder it will create under the /var/tmp folder,
# but on slow filesystems we might try to use the folder before we see it's
# been created. Set TMPDIR back to /tmp here to avoid this.
export TMPDIR=/tmp

if [ ! -z "${PBS_ARRAY_INDEX}" ] ; then
    # Use job arrays
    export PARALLEL_SERVER_TASK_LOCATION="${PARALLEL_SERVER_JOB_LOCATION}/Task${PBS_ARRAY_INDEX}";
    export MDCE_TASK_LOCATION="${MDCE_JOB_LOCATION}/Task${PBS_ARRAY_INDEX}";
fi

# Construct the command to run.
CMD="\"${PARALLEL_SERVER_MATLAB_EXE}\" ${PARALLEL_SERVER_MATLAB_ARGS}"

# Echo the command so that it is shown in the output log.
echo "Executing: $CMD"

# Execute the command.
eval $CMD

EXIT_CODE=${?}
echo "Exiting with code: ${EXIT_CODE}"
exit ${EXIT_CODE}
