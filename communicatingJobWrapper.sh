#!/bin/sh
# This wrapper script is intended to be submitted to PBS to support
# communicating jobs.  It assumes that passwordless SSH is set up between
# all nodes on the cluster.
#
# This script uses the following environment variables set by the submit MATLAB code:
# PARALLEL_SERVER_CMR         - the value of ClusterMatlabRoot (may be empty)
# PARALLEL_SERVER_MATLAB_EXE  - the MATLAB executable to use
# PARALLEL_SERVER_MATLAB_ARGS - the MATLAB args to use
# PARALLEL_SERVER_TOTAL_TASKS - total number of workers to start
# PARALLEL_SERVER_NUM_THREADS - number of cores needed per worker
# PARALLEL_SERVER_DEBUG       - used to debug problems on the cluster
#
# The following environment variables are forwarded through mpiexec:
# PARALLEL_SERVER_DECODE_FUNCTION     - the decode function to use
# PARALLEL_SERVER_STORAGE_LOCATION    - used by decode function
# PARALLEL_SERVER_STORAGE_CONSTRUCTOR - used by decode function
# PARALLEL_SERVER_JOB_LOCATION        - used by decode function
#
# The following environment variables are set by PBS:
# PBS_NODEFILE - path to a file listing the hostnames allocated to this PBS job

# Copyright 2006-2023 The MathWorks, Inc.

# If PARALLEL_SERVER_ environment variables are not set, assign any
# available values with form MDCE_ for backwards compatibility
PARALLEL_SERVER_CMR=${PARALLEL_SERVER_CMR:="${MDCE_CMR}"}
PARALLEL_SERVER_MATLAB_EXE=${PARALLEL_SERVER_MATLAB_EXE:="${MDCE_MATLAB_EXE}"}
PARALLEL_SERVER_MATLAB_ARGS=${PARALLEL_SERVER_MATLAB_ARGS:="${MDCE_MATLAB_ARGS}"}
PARALLEL_SERVER_TOTAL_TASKS=${PARALLEL_SERVER_TOTAL_TASKS:="${MDCE_TOTAL_TASKS}"}
PARALLEL_SERVER_NUM_THREADS=${PARALLEL_SERVER_NUM_THREADS:="${MDCE_NUM_THREADS}"}
PARALLEL_SERVER_DEBUG=${PARALLEL_SERVER_DEBUG:="${MDCE_DEBUG}"}

# PBS will set TMPDIR to a folder it will create under the /var/tmp folder,
# but on slow filesystems we might try to use the folder before we see it's
# been created. Set TMPDIR back to /tmp here to avoid this.
export TMPDIR=/tmp

# Echo the nodes that the scheduler has allocated to this job:
echo -e "The scheduler has allocated the following nodes to this job:\n$(cat ${PBS_NODEFILE:?"Node file undefined"})"

# Create full path to mw_mpiexec if needed.
FULL_MPIEXEC=${PARALLEL_SERVER_CMR:+${PARALLEL_SERVER_CMR}/bin/}mw_mpiexec

# Label stdout/stderr with the rank of the process
MPI_VERBOSE=-l

# Increase the verbosity of mpiexec if PARALLEL_SERVER_DEBUG is set and not false
if [ ! -z "${PARALLEL_SERVER_DEBUG}" ] && [ "${PARALLEL_SERVER_DEBUG}" != "false" ] ; then
    MPI_VERBOSE="${MPI_VERBOSE} -v -print-all-exitcodes"
fi

# If the scheduler is Torque then we need to provide a customized version
# $PBS_NODEFILE to mpiexec to ensure workers are launched appropriately
# when NumThreads > 2. For example, consider 2 workers with NumThreads = 2
# on a cluster with two processors per node. $PBS_NODEFILE will be of the
# form:
#     A
#     A
#     B
#     B
# This will start both workers on node A.  To start a worker on each node,
# the nodefile needs to be:
#     A
#     B

# Determine whether the scheduler is Torque.
case "${PBS_VERSION}" in
    *TORQUE*) IS_TORQUE=1 ;;
    *)        IS_TORQUE=0 ;;
esac

ADDITIONAL_MPIEXEC_ARGS="${MPI_VERBOSE} -n ${PARALLEL_SERVER_TOTAL_TASKS}"
if [ ${IS_TORQUE} -eq 1 ] ; then
    CUSTOM_NODEFILE="/tmp/${PBS_JOBID}.nodefile.txt"
    
    # Install a trap to make sure the custom nodefile is deleted.
    trap "rm -f ${CUSTOM_NODEFILE}" 0 1 2 15
    
    # Select every N-th line from ${PBS_NODEFILE}, where N = NumThreads.
    awk "NR % ${PARALLEL_SERVER_NUM_THREADS} == 0" ${PBS_NODEFILE} > "${CUSTOM_NODEFILE}"
    
    echo -e "Starting ${PARALLEL_SERVER_TOTAL_TASKS} workers on the following nodes:\n$(cat ${CUSTOM_NODEFILE})"

    ADDITIONAL_MPIEXEC_ARGS="${ADDITIONAL_MPIEXEC_ARGS} -f \"${CUSTOM_NODEFILE}\""
fi

# Unset the hostname variables to ensure they don't get forwarded by mpiexec
unset HOST HOSTNAME

# Construct the command to run.
CMD="\"${FULL_MPIEXEC}\" -bind-to core:${PARALLEL_SERVER_NUM_THREADS} ${ADDITIONAL_MPIEXEC_ARGS} \
    \"${PARALLEL_SERVER_MATLAB_EXE}\" ${PARALLEL_SERVER_MATLAB_ARGS}"

# Echo the command so that it is shown in the output log.
echo $CMD

# Execute the command.
eval $CMD

MPIEXEC_EXIT_CODE=${?}
if [ ${MPIEXEC_EXIT_CODE} -eq 42 ] ; then
    # Get here if user code errored out within MATLAB. Overwrite this to zero in
    # this case.
    echo "Overwriting MPIEXEC exit code from 42 to zero (42 indicates a user-code failure)"
    MPIEXEC_EXIT_CODE=0
fi
echo "Exiting with code: ${MPIEXEC_EXIT_CODE}"
exit ${MPIEXEC_EXIT_CODE}
