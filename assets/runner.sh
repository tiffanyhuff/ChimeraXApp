
echo "TACC: job $SLURM_JOB_ID execution at: `date`"

# program and command line arguments run within xterm -e command
XTERM_CMD="${_XTERM_CMD}"
# Webhook callback url for job ready notification.
# Notifications are sent to INTERACTIVE_WEBHOOK_URL i.e. https://3dem.org/webhooks/interactive/
INTERACTIVE_WEBHOOK_URL="${_webhook_base_url}interactive/"


# our node name
NODE_HOSTNAME=`hostname -s`

# HPC system target. Used as DCV host
HPC_HOST=`hostname -d`

echo "TACC: running on node $NODE_HOSTNAME on $HPC_HOST"

TAP_FUNCTIONS="/share/doc/slurm/tap_functions"
if [ -f ${TAP_FUNCTIONS} ]; then
    . ${TAP_FUNCTIONS}
else
    echo "TACC:"
    echo "TACC: ERROR - could not find TAP functions file: ${TAP_FUNCTIONS}"
    echo "TACC: ERROR - Please submit a consulting ticket at the TACC user portal"
    echo "TACC: ERROR - https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
    echo "TACC:"
    echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
    exit 1
fi

# confirm DCV server is alive
SERVER_TYPE="DCV"

DCV_SERVER_UP=`systemctl is-active dcvserver`
if [ $DCV_SERVER_UP != "active" ]; then
    echo "TACC:"
    echo "TACC: ERROR - could not confirm dcvserver active, systemctl returned '$DCV_SERVER_UP'"
    echo "TACC: ERROR - Please submit a consulting ticket at the TACC user portal"
    echo "TACC: ERROR - https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
    echo "TACC:"
    echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
    exit 1
fi


# create an X startup file in /tmp
# source xinitrc-common to ensure xterms can be made
# then source the user's xstartup if it exists
XSTARTUP="/tmp/dcv-startup-$USER"
cat <<- EOF > $XSTARTUP
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
. /etc/X11/xinit/xinitrc-common
EOF
#if [ -x $HOME/.vnc/xstartup ]; then
#  cat $HOME/.vnc/xstartup >> $XSTARTUP
#else
#    echo "exec /etc/X11/xinit/xinitrc" >> $XSTARTUP
    echo "exec startxfce4" >> $XSTARTUP
#fi
chmod a+rx $XSTARTUP

# if X0 socket exists, then DCV will use a higher X display number and ruin our day
# therefore, cowardly bail out and appeal to an admin to fix the problem
if [ -f /tmp/.X11-unix/X0 ]; then
    echo "TACC:"
    echo "TACC: ERROR - X0 socket already exists. DCV script will fail."
    echo "TACC: ERROR - Please submit a consulting ticket at the TACC user portal"
    echo "TACC: ERROR - https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
    echo "TACC:"
    echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
    exit 1
fi

# create DCV session
DCV_HANDLE="${AGAVE_JOB_ID}-session"
dcv create-session --owner ${AGAVE_JOB_OWNER} --init=$XSTARTUP $DCV_HANDLE
if ! `dcv list-sessions | grep -q ${AGAVE_JOB_ID}`; then
    echo "TACC:"
    echo "TACC: ERROR - could not find a DCV session for $USER"
    echo "TACC: ERROR - This could be because all DCV licenses are in use."
    echo "TACC: ERROR - Consider using job.dcv2vnc which launches VNC if DCV is not available."
    echo "TACC: ERROR - If you receive this message repeatedly, "
    echo "TACC: ERROR - please submit a consulting ticket at the TACC user portal:"
    echo "TACC: ERROR - https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
    echo "TACC:"
    echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
    exit 1
fi


LOCAL_VNC_PORT=8443  # default DCV port
echo "TACC: local (compute node) ${SERVER_TYPE} port is $LOCAL_VNC_PORT"

LOGIN_PORT=$(tap_get_port)
echo "TACC: got login node DCV port $LOGIN_PORT"

# Wait a few seconds for good measure for the job status to update
sleep 3;

# create reverse tunnel port to login nodes.  Make one tunnel for each login so the user can just
# connect to ls6.tacc
for i in `seq 3`; do
    ssh -q -f -g -N -R $LOGIN_PORT:$NODE_HOSTNAME:$LOCAL_VNC_PORT login$i
done
echo "TACC: Created reverse ports on Lonestar6 logins"

echo "TACC: Your DCV session is now running!"
echo "TACC: To connect to your DCV session, please point a modern web browser to:"
echo "TACC:          https://ls6.tacc.utexas.edu:$LOGIN_PORT"


echo "TACC: Your DCV session is now running!" > $STOCKYARD/ChimeraX_dcvserver.txt
echo "TACC: To connect to your DCV session, please point a modern web browser to:" >> $STOCKYARD/ChimeraX_dcvserver.txt
echo "TACC:          https://ls6.tacc.utexas.edu:$LOGIN_PORT" >> $STOCKYARD/ChimeraX_dcvserver.txt

#Intiating webhooks

if [ "x${SERVER_TYPE}" == "xDCV" ]; then
  curl -k --data "event_type=WEB&address=https://$HPC_HOST:$LOGIN_PORT&owner=${AGAVE_JOB_OWNER}&job_uuid=${AGAVE_JOB_ID}" $INTERACTIVE_WEBHOOK_URL &
  echo "event_type=WEB&address=https://$HPC_HOST:$LOGIN_PORT&owner=${AGAVE_JOB_OWNER}&job_uuid=${AGAVE_JOB_ID}" $INTERACTIVE_WEBHOOK_URL
else
  # we should never get this message since we just checked this at LOCAL_PORT
  echo "TACC: "
  echo "TACC: ERROR - unknown server type '${SERVER_TYPE}'"
  echo "TACC: Please submit a consulting ticket at the TACC user portal"
  echo "TACC: https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
  echo "TACC:"
  echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
  exit 1
fi

if [ -d "$workingDirectory" ]; then
  cd ${workingDirectory}
fi

# Make a desktop folder with jobs archive
if [ ! -L $HOME/Desktop/Jobs ];
then
    ln -s $STOCKYARD/archive/ $HOME/Desktop/Jobs
fi

# silence xalt errors
module unload xalt

# run an xterm for the user; execution will hold here
mkdir -p $HOME/.tap
TAP_LOCKFILE=${HOME}/.tap/${SLURM_JOB_ID}.lock
sleep 1
DISPLAY=:0 xterm -fg white -bg red3 +sb -geometry 55x2+0+0 -T 'END SESSION HERE' -e "echo 'TACC: Press <enter> in this window to end your session' && read && rm ${TAP_LOCKFILE}" &
sleep 1

DISPLAY=:0 xterm -ls -geometry 80x24+100+50 -e 'singularity exec docker://maduprey/chimerax:1.5 chimerax' &


echo $(date) > ${TAP_LOCKFILE}
while [ -f ${TAP_LOCKFILE} ]; do
    sleep 1
done

# job is done!

echo "TACC: closing DCV session"
dcv close-session $DCV_HANDLE

echo "TACC: release port returned $(tap_release_port ${LOGIN_PORT} 2> /dev/null)"

# wait a brief moment so dcvserver can clean up after itself
sleep 1

# remove X11 sockets so DCV will find :0 next time
find /tmp/.X11-unix -user $USER -exec rm -f '{}' \;

echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
rm $STOCKYARD/ChimeraX_dcvserver.txt