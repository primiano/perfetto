#!/bin/bash
# Copyright (C) 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source $(dirname ${BASH_SOURCE[0]})/common.sh


# Save CI time by skipping runs on {UI,docs,infra}-only changes
if [[ $UI_DOCS_INFRA_ONLY_CHANGE == 1 ]]; then
echo "Detected non-code change, probably a UI-only change."
echo "skipping build + test runs"
exit 0
fi

tools/gn gen ${OUT_PATH} --args="${PERFETTO_TEST_GN_ARGS}" --check
tools/ninja -C ${OUT_PATH} ${PERFETTO_TEST_NINJA_ARGS}

# Run the tests

${OUT_PATH}/perfetto_unittests
${OUT_PATH}/perfetto_integrationtests
${OUT_PATH}/trace_processor_minimal_smoke_tests

# If this is a split host+target build, use the trace_processor_shell binary
# from the host directory. In some cases (e.g. lsan x86 builds) the host binary
# that is copied into the target directory (OUT_PATH) cannot run because depends
# on libc++.so within the same folder (which is built using target bitness,
# not host bitness).
HOST_OUT_PATH=${OUT_PATH}/gcc_like_host
if [ ! -f ${HOST_OUT_PATH}/trace_processor_shell ]; then
  HOST_OUT_PATH=${OUT_PATH}
fi

mkdir -p "$PERFETTO_ARTIFACTS_DIR/perf"

tools/diff_test_trace_processor.py \
  --perf-file=$PERFETTO_ARTIFACTS_DIR/perf/tp-perf-all.json \
  ${HOST_OUT_PATH}/trace_processor_shell

python/run_tests.py ${HOST_OUT_PATH}

# Don't run benchmarks under x86 (running out of address space because of 4GB)
# limit or debug (too slow and pointless).
HOST_CPU="$(tools/gn args --short --list=host_cpu ${OUT_PATH} | awk '{print $3}' | sed -e 's/^"//' -e 's/"$//')"
TARGET_CPU="$(tools/gn args --short --list=target_cpu ${OUT_PATH} | awk '{print $3}' | sed -e 's/^"//' -e 's/"$//')"
IS_DEBUG="$(tools/gn args --short --list=is_debug ${OUT_PATH} | awk '{print $3}')"
if [[ !("$TARGET_CPU" == "x86" || ("$TARGET_CPU" == "" && "$HOST_CPU" == "x86")) && "$IS_DEBUG" == "false" ]]; then
  BENCHMARK_FUNCTIONAL_TEST_ONLY=true ${OUT_PATH}/perfetto_benchmarks
fi
