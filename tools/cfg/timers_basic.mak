CC_OPTS += -DUSE_TIMERS=1
CPP_OPTS += -DUSE_TIMERS=1
MEX_OPTS += -DUSE_TIMERS=1

ifeq ($(GPU),YES)
NVCC_OPTS +=  -DUSE_TIMERS=1
endif