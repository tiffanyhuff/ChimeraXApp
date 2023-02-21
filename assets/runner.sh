
echo "TACC: job $SLURM_JOB_ID execution at: `date`"

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

# our node name
NODE_HOSTNAME=`hostname -s`
echo "TACC: running on node $NODE_HOSTNAME"

#CONDA=$(which conda 2> /dev/null)
#if [ ! -z "${CONDA}" ]; then
#    CONDA_ENV=$(conda info | grep active | cut -d ":" -f 2)
#    if [[ ! "${CONDA_ENV}" =~ "None" ]]; then
#        echo "TACC:"
#        echo "TACC: ERROR - active conda installation detected, which will break DCV"
#        echo "TACC: ERROR - deactivate conda with 'conda deactivate'"
#        echo "TACC: ERROR - then resubmit this job script"
#        echo "TACC: ERROR - Questions? Please submit a consulting ticket"
#        echo "TACC: ERROR - https://portal.tacc.utexas.edu/tacc-consulting/-/consult/tickets/create"
#        echo "TACC:"
#        echo "TACC: job ${SLURM_JOB_ID} execution finished at: $(date)"
#        exit 1
#    fi
#fi

# confirm DCV server is alive
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
DCV_HANDLE="$USER-session"
dcv create-session --init=$XSTARTUP $DCV_HANDLE
if ! `dcv list-sessions | grep -q $USER`; then
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
echo "TACC: local (compute node) DCV port is $LOCAL_VNC_PORT"

LOGIN_PORT=$(tap_get_port)
echo "TACC: got login node DCV port $LOGIN_PORT"

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

# Make a symlink to work in home dir to help with navigation
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

# wait a brief moment so vncserver can clean up after itself
sleep 1

# remove X11 sockets so DCV will find :0 next time
find /tmp/.X11-unix -user $USER -exec rm -f '{}' \;

echo "TACC: job $SLURM_JOB_ID execution finished at: `date`"
rm $STOCKYARD/ChimeraX_dcvserver.txt