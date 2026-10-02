#!/bin/bash

sed -i /etc/slurm/slurm.conf \
	-e 'd/JobComp/' \
	-e 'd/JobAcctGather/' \
	-e 'd/AcctGatherProfileType/' \
	-e 'd/Suspend/' \
	-e 'd/Resume/' \
	-e 'd/cloud/' \
	-e 'd/PrologFlags/' \
	-e 'd/X11Parameters/'

unlink /etc/slurm/acct_gather.conf
unlink /etc/slurm/plugstack.conf

cat <<EOF >>/etc/slurm/slurm.conf
SlurmctldParameters=enable_configless,idle_on_node_suspend,enable_rpc_queue,CONMGR_THREADS=128,CONMGR_MAX_CONNECTIONS=4096,CONMGR_READ_TIMEOUT=60,CONMGR_WRITE_TIMEOUT=60,CONMGR_CONNECT_TIMEOUT=60
MaxArraySize=1000000
MaxJobCount=1000000
MessageTimeout=100

SlurmdDebug=error
SlurmctldDebug=error

SchedulerParameters=default_queue_depth=10000,sched_interval=30,max_array_tasks=25000,ignore_prefer_validation,defer_batch,bf_busy_nodes,bf_window=30,bf_max_time=90,bf_interval=1,bf_resolution=600,bf_continue,bf_max_job_array_resv=1,bf_max_job_test=10000,max_rpc_cnt=150,yield_rpc_cnt=100,bf_min_prio_reserve=1000000,sched_min_interval=2000000,bf_yield_interval=500000,batch_sched_delay=3,bf_yield_sleep=100000,bf_ignore_cg_state,bf_start_on_avail_bitmap,enable_job_state_cache
SelectTypeParameters=CR_Core_Memory,CR_LLN
EOF
