#!/bin/bash -ex

##########CONFIGURE############
#Set full path to install directory
target=/opt/etherpad-lite
port=8080 #must be above 1024
###############################



#Check for Root
ifaces=/etc/network/interfaces
LUID=$(id -u)
if [[ $LUID -ne 0 ]]; then
	echo "$0 must be run as root"
	exit 1
fi

install ()
{
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get -y \
        -o DPkg::Options::=--force-confdef \
        -o DPkg::Options::=--force-confold \
        install $@
}

install gzip git-core curl python libssl-dev pkg-config build-essential npm nodejs

#git-clone to /opt/etherpad-lite
git clone git://github.com/Pita/etherpad-lite.git $target

#Create settings.json
cp $target/settings.json.template $target/settings.json

#configure etherpad
sed -i "s|9001|$port|" $target/settings.json

#Make sure dependencies are up to date
$target/bin/installDeps.sh

#useradd system user named etherpad-lite
useradd -MrU etherpad-lite
#create log directory
mkdir -p /var/log/etherpad-lite/
#permissions
chown -R etherpad-lite:etherpad-lite $target/
chown -R etherpad-lite:etherpad-lite /var/log/etherpad-lite/

#configure daemon
cat > /etc/init.d/etherpad-lite <<"EOF"
#!/bin/sh

### BEGIN INIT INFO
# Provides:          etherpad-lite
# Required-Start:    $local_fs $remote_fs $network $syslog
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts etherpad lite
# Description:       starts etherpad lite using start-stop-daemon
### END INIT INFO

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/node/bin"
LOGFILE="/var/log/etherpad-lite/etherpad-lite.log"
EPLITE_DIR="#target#"
EPLITE_BIN="bin/safeRun.sh"
USER="etherpad-lite"
GROUP="etherpad-lite"
DESC="Etherpad Lite"
NAME="etherpad-lite"

set -e

. /lib/lsb/init-functions

start() {
  echo "Starting $DESC... "
  
	start-stop-daemon --start --chuid "$USER:$GROUP" --background --make-pidfile --pidfile /var/run/$NAME.pid --exec $EPLITE_DIR/$EPLITE_BIN -- $LOGFILE || true
  echo "done"
}

#We need this function to ensure the whole process tree will be killed
killtree() {
    local _pid=$1
    local _sig=${2-TERM}
    for _child in $(ps -o pid --no-headers --ppid ${_pid}); do
        killtree ${_child} ${_sig}
    done
    kill -${_sig} ${_pid}
}

stop() {
  echo "Stopping $DESC... "
   while test -d /proc/$(cat /var/run/$NAME.pid); do
    killtree $(cat /var/run/$NAME.pid) 15
    sleep 0.5
  done
  rm /var/run/$NAME.pid
  echo "done"
}

status() {
  status_of_proc -p /var/run/$NAME.pid "" "etherpad-lite" && exit 0 || exit $?
}

case "$1" in
  start)
	  start
	  ;;
  stop)
    stop
	  ;;
  restart)
	  stop
	  start
	  ;;
  status)
	  status
	  ;;
  *)
	  echo "Usage: $NAME {start|stop|restart|status}" >&2
	  exit 1
	  ;;
esac

exit 0
EOF

#specify the etherpad install directory
sed -i "s|#target#|$target|" /etc/init.d/etherpad-lite

#Make daemon file executeable
chmod +x /etc/init.d/etherpad-lite

#Configure as a service
update-rc.d etherpad-lite defaults

