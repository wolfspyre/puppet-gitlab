#! /bin/bash
# GITLAB
# Maintainer: @randx
# App Version: 5.2

### BEGIN CHKCONFIG INFO
# chkconfig 2345 70 29
#### END CHKCONFIG INFO

### BEGIN INIT INFO
# Provides:          gitlab
# Required-Start:    $local_fs $remote_fs $network $syslog redis-server
# Required-Stop:     $local_fs $remote_fs $network $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: GitLab git repository management
# Description:       GitLab git repository management
### END INIT INFO


APP_ROOT="/home/git/gitlab"
APP_USER="git"
DAEMON_OPTS="-C $APP_ROOT/config/puma.rb"
PID_PATH="$APP_ROOT/tmp/pids"
SOCKET_PATH="$APP_ROOT/tmp/sockets"
WEB_SERVER_PID="$PID_PATH/puma.pid"
NAME="gitlab"
DESC="GitLab service"

check_pid(){
  if [ -f $WEB_SERVER_PID ]; then
    PID=`cat $WEB_SERVER_PID`
    STATUS=`ps aux | grep $PID | grep -v grep | wc -l`
  else
    STATUS=0
    PID=0
  fi
}

execute() {
  sudo -u $APP_USER -H bash -l -c "$1"
}

start() {
  cd $APP_ROOT
  check_pid
  if [ "$PID" -ne 0 -a "$STATUS" -ne 0 ]; then
    # Program is running, exit with error code 1.
    echo "Error! $DESC $NAME is currently running!"
    exit 1
  else
    if [ `whoami` = root ]; then
      if [ -S "$SOCKET_PATH/gitlab.socket" ]; then
        execute "rm $SOCKET_PATH/gitlab.socket"
      fi
      execute "RAILS_ENV=production bundle exec puma $DAEMON_OPTS"
      echo "$DESC started"
    fi
  fi
}

stop() {
  cd $APP_ROOT
  check_pid
  if [ "$PID" -ne 0 -a "$STATUS" -ne 0 ]; then
    ## Program is running, stop it.
    kill -QUIT `cat $WEB_SERVER_PID`
    rm "$WEB_SERVER_PID" >> /dev/null
    echo "$DESC stopped"
  else
    ## Program is not running, exit with error.
    echo "Error! $DESC not started!"
    if [ -S "$SOCKET_PATH/gitlab.socket" ]; then
      execute "rm $SOCKET_PATH/gitlab.socket"
    fi     
    exit 1
  fi
}

restart() {
  cd $APP_ROOT
  check_pid
  if [ "$PID" -ne 0 -a "$STATUS" -ne 0 ]; then
    echo "Restarting $DESC..."
    kill -USR2 `cat $WEB_SERVER_PID`
    echo "$DESC restarted."
  else
    echo "Error, $NAME not running!"
    exit 1
  fi
}

status() {
  cd $APP_ROOT
  check_pid
  if [ "$PID" -ne 0 -a "$STATUS" -ne 0 ]; then
    echo "$DESC / Puma with PID $PID is running."
  elif [ -S "$SOCKET_PATH/gitlab.socket" ]; then
    echo "${DESC} is not running, but ${SOCKET_PATH}/gitlab.socket exists"
    exit 1
  else
    echo "$DESC is not running."
    exit 1
  fi
}

## Check to see if we are running as root first.
## Found at http://www.cyberciti.biz/tips/shell-root-user-check-script.html
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root"
    exit 1
fi

case "$1" in
  start)
        start
        ;;
  stop)
        stop
        ;;
  restart)
        restart
        ;;
  reload|force-reload)
        echo -n "Reloading $NAME configuration: "
        kill -HUP `cat $PID`
        echo "done."
        ;;
  status)
        status
        ;;
  *)
        echo "Usage: sudo service gitlab {start|stop|restart|reload}" >&2
        exit 1
        ;;
esac

exit 0