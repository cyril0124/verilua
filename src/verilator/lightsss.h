/***************************************************************************************
* Copyright (c) 2020-2023 Institute of Computing Technology, Chinese Academy of Sciences
* Copyright (c) 2020-2021 Peng Cheng Laboratory
*
* DiffTest is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

// Copy form https://github.com/OpenXiangShan/difftest

#ifndef __LIGHTSSS_H
#define __LIGHTSSS_H

#include <deque>
#include <list>
#include <signal.h>
#include <sys/ipc.h>
#include <sys/prctl.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <unistd.h>


#include <cassert>
#include <cerrno>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/time.h>

#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

#define eprintf(...) fprintf(stdout, ##__VA_ARGS__)

#ifdef DEBUG
#define Info(...)           \
  do {                      \
    eprintf(__VA_ARGS__); \
  } while (0)
#else
#define Info(...)
#endif

// -----------------------------------------------------------------------
// Checkpoint config
// -----------------------------------------------------------------------

// max number of checkpoint process at a time
#define SLOT_SIZE 2

// exit when error when fork
#define FAIT_EXIT    exit(EXIT_FAILURE);

// process sleep time
#define WAIT_INTERVAL 5

// time to save a snapshot
#define SNAPSHOT_INTERVAL 60 // unit: second

// if error, let simulator print debug info
#define ENABLE_SIMULATOR_DEBUG_INFO

// how many cycles child processes step forward when reaching error point
#define STEP_FORWARD_CYCLES 100

typedef struct shinfo {
  bool flag;
  bool notgood;
  uint64_t endCycles;
  pid_t oldest;
} shinfo;

class ForkShareMemory {
private:
  key_t key_n;
  int shm_id;

public:
  shinfo *info;

  ForkShareMemory();
  ~ForkShareMemory();

  void shwait();
};

const int FORK_OK = 0;
const int FORK_ERROR = 1;
const int FORK_CHILD = 2;

class LightSSS {
  pid_t pid = -1;
  int slotCnt = 0;
  int waitProcess = 0;
  // front() is the newest. back() is the oldest.
  std::deque<pid_t> pidSlot = {};
  ForkShareMemory forkshm;

public:
  int do_fork();
  int wakeup_child(uint64_t cycles);
  bool is_child();
  int do_clear();
  uint64_t get_end_cycles() {
    return forkshm.info->endCycles;
  }
};

#define FORK_PRINTF(format, args...)                       \
  do {                                                     \
    Info("[FORK_INFO pid(%d)] " format, getpid(), ##args); \
    fflush(stdout);                                        \
  } while (0);

#endif
