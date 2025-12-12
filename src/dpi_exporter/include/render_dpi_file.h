#pragma once

#include "dpi_exporter.h"

std::string renderDpiFile(std::vector<SignalGroup> &signalGroupVec, std::vector<SensitiveTriggerInfo> &sensitiveTriggerInfoVec, std::string topModuleName, bool distributeDPI, std::string metaInfoFilePath, bool relativeMetaPath = false);
