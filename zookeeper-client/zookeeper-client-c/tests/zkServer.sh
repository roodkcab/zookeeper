#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This is the port where zookeeper server runs on.
ZOOPORT=22181

if [ "x$1" == "x" ]
then
    echo "USAGE: $0 startClean|start|startReadOnly|stop hostPorts"
    exit 2
fi

case "`uname`" in
    CYGWIN*) cygwin=true ;;
    *) cygwin=false ;;
esac

if [ "x$1" == "xstartClean" ]
then
    if [ "x${base_dir}" == "x" ]
    then
    rm -rf /tmp/zkdata
    else
    rm -rf "${base_dir}/build/tmp"
    fi
fi

if $cygwin
then
    # cygwin has a "kill" in the shell itself, gets confused
    KILL=/bin/kill
else
    KILL=kill
fi

# Make sure nothing is left over from before
if [ -r "/tmp/zk.pid" ]
then
pid=`cat /tmp/zk.pid`
$KILL -9 $pid
rm -f /tmp/zk.pid
fi

if [ -r "${base_dir}/build/tmp/zk.pid" ]
then
pid=`cat "${base_dir}/build/tmp/zk.pid"`
$KILL -9 $pid
rm -f "${base_dir}/build/tmp/zk.pid"
fi

# [ZOOKEEPER-820] If lsof command is present, look for a process listening
# on ZOOPORT and kill it. 
which lsof &> /dev/null
if [ $? -eq 0  ]
then
    pid=`lsof -i :$ZOOPORT | grep LISTEN | awk '{print $2}'`
    if [ -n "$pid" ]
    then
        $KILL -9 $pid
    fi
fi

if [ "x${base_dir}" == "x" ]
then
zk_base="../../../"
else
zk_base="${base_dir}"
fi

CLASSPATH="$CLASSPATH:${zk_base}/build/classes"
CLASSPATH="$CLASSPATH:${zk_base}/conf"
CLASSPATH="$CLASSPATH:${zk_base}/zookeeper-server/target/classes"

for i in "${zk_base}"/build/lib/*.jar
do
    CLASSPATH="$CLASSPATH:$i"
done

for d in "${zk_base}"/zookeeper-server/target/lib/*.jar
do
    CLASSPATH="$d:$CLASSPATH"
done

for i in "${zk_base}"/zookeeper-server/src/main/resource/lib/*.jar
do
    CLASSPATH="$CLASSPATH:$i"
done

CLASSPATH="$CLASSPATH:${CLOVER_HOME}/lib/clover*.jar"

if $cygwin
then
    CLASSPATH=`cygpath -wp "$CLASSPATH"`
fi

case $1 in
start|startClean)
    if [ "x${base_dir}" == "x" ]
    then
        mkdir -p /tmp/zkdata
        java -cp "$CLASSPATH" org.apache.zookeeper.server.ZooKeeperServerMain $ZOOPORT /tmp/zkdata 3000 $ZKMAXCNXNS &> /tmp/zk.log &
        pid=$!
        echo -n $! > /tmp/zk.pid
    else
	tmpdir="${base_dir}/build/tmp"
        mkdir -p "${tmpdir}/zkdata"
        rm -f "${tmpdir}/zkdata/myid" && echo 1 > "${tmpdir}/zkdata/myid"

        sed "s#TMPDIR#${tmpdir}#g" ${base_dir}/zookeeper-client/zookeeper-client-c/tests/zoo.cfg > "${tmpdir}/zoo.cfg"

        java -cp "$CLASSPATH" org.apache.zookeeper.server.ZooKeeperServerMain ${tmpdir}/zoo.cfg &> "${base_dir}/build/tmp/zk.log" &
        pid=$!
        echo -n $pid > "${base_dir}/build/tmp/zk.pid"
    fi

    # wait max 120 seconds for server to be ready to server clients
    # this handles testing on slow hosts
    success=false
    for i in {1..120}
    do
        if ps -p $pid > /dev/null
        then
            java -cp "$CLASSPATH" org.apache.zookeeper.ZooKeeperMain -server localhost:$ZOOPORT ls / > /dev/null 2>&1
            if [ $? -ne 0  ]
            then
                # server not up yet - wait
                sleep 1
            else
                # server is up and serving client connections
                success=true
                break
            fi
        else
            # server died - exit now
            echo -n " ZooKeeper server process failed"
            break
        fi
    done

    if $success
    then
        ## in case for debug, but generally don't use as it messes up the
        ## console test output
        echo -n " ZooKeeper server started"
    else
        echo -n " ZooKeeper server NOT started"
    fi

    ;;
startReadOnly)
    if [ "x${base_dir}" == "x" ]
    then
        echo "this target is for unit tests only"
        exit 2
    else
        tmpdir="${base_dir}/build/tmp"
        mkdir -p "${tmpdir}/zkdata"
        rm -f "${tmpdir}/zkdata/myid" && echo 1 > "${tmpdir}/zkdata/myid"

        sed "s#TMPDIR#${tmpdir}#g" ${base_dir}/zookeeper-client/zookeeper-client-c/tests/quorum.cfg > "${tmpdir}/quorum.cfg"

        # force read-only mode
        java -cp "$CLASSPATH" -Dreadonlymode.enabled=true org.apache.zookeeper.server.quorum.QuorumPeerMain ${tmpdir}/quorum.cfg &> "${tmpdir}/zk.log" &
        pid=$!
        echo -n $pid > "${base_dir}/build/tmp/zk.pid"
        sleep 3 # wait until read-only server is up
    fi

    ;;
stop)
    # Already killed above
    ;;
*)
    echo "Unknown command " + $1
    exit 2
esac

