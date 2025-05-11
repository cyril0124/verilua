#pragma once

#include "dpi_exporter.h"

std::string renderDpiFile(std::vector<SignalGroup> &signalGroupVec, std::string topModuleName, bool distributeDPI, std::string metaInfoFilePath);
